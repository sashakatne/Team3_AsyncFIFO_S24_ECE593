`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Legacy standalone asynchronous FIFO, "style #2" pointer comparison.
//
// This file is intentionally self-contained: it carries the FIFO top, memory,
// asynchronous pointer comparator, read pointer/empty flag logic, and write
// pointer/full flag logic in one source file so it can be compiled without the
// UVM milestone environment.  It is kept in Miscellaneous as a reference design
// variant, not as the canonical final FIFO implementation.
//
// The design uses Gray-coded read/write pointers and an asynchronous comparator
// that tracks the relative pointer quadrant in `direction`.  When Gray pointers
// are equal, `direction == 0` means the FIFO is empty and `direction == 1`
// means the FIFO is full.  This is a classic Cummings-style async compare FIFO
// approach; it is more timing-sensitive than the synchronizer-based FIFO in
// async_fifo4.sv, so the comments below call out the CDC-sensitive boundaries.
// -----------------------------------------------------------------------------

module fifo2 (rdata, wfull, rempty, wdata, winc, wclk, wrst_n, rinc, rclk, rrst_n);
    parameter DSIZE = 8;
    parameter ASIZE = 4;

    output [DSIZE-1:0] rdata;
    output wfull;
    output rempty;
    input [DSIZE-1:0] wdata;
    input winc, wclk, wrst_n;
    input rinc, rclk, rrst_n;

    // `wptr` and `rptr` are Gray pointers.  Their low ASIZE bits also serve as
    // RAM addresses, matching the original style-2 FIFO structure.
    wire [ASIZE-1:0] wptr, rptr;

    // The async comparator produces active-low intermediate flags.  These nets
    // were previously implicit, which compiled with warnings on Questa.  Keeping
    // them explicit makes the standalone file warning-clean without changing the
    // legacy architecture.
    wire aempty_n, afull_n;

    // Memory writes must be gated by the registered full flag, not raw `winc`.
    // The legacy file previously held the write pointer when full but still
    // allowed the RAM location under that held pointer to be overwritten by
    // over-full write attempts.  The self-checking bench now catches that data
    // corruption, so the memory enable is explicitly qualified here.
    wire write_accept = winc & !wfull;

    async_cmp  #(ASIZE) async_cmp  (.aempty_n(aempty_n), .afull_n(afull_n), .wptr(wptr), .rptr(rptr), .wrst_n(wrst_n));
    fifomem    #(DSIZE, ASIZE) fifomem    (.rdata(rdata), .wdata(wdata), .waddr(wptr), .raddr(rptr), .wclken(write_accept), .wclk(wclk));
    rptr_empty #(ASIZE) rptr_empty (.rempty(rempty), .rptr(rptr), .aempty_n(aempty_n), .rinc(rinc), .rclk(rclk), .rrst_n(rrst_n));
    wptr_full  #(ASIZE) wptr_full  (.wfull(wfull), .wptr(wptr), .afull_n(afull_n), .winc(winc), .wclk(wclk), .wrst_n(wrst_n));

endmodule

module fifomem (rdata, wdata, waddr, raddr, wclken, wclk);
    parameter DATASIZE = 8;       // Width of each FIFO entry.
    parameter ADDRSIZE = 4;       // Number of address bits; depth is 2**ADDRSIZE.
    parameter DEPTH = 1 << ADDRSIZE;

    output [DATASIZE-1:0] rdata;
    input [DATASIZE-1:0] wdata;
    input [ADDRSIZE-1:0] waddr, raddr;
    input wclken, wclk;

`ifdef VENDORRAM
    // Optional vendor RAM hook preserved from the original standalone design.
    // The default simulation path below uses a behavioral dual-port RAM.
    VENDOR_RAM MEM (.dout(rdata), .din(wdata), .waddr(waddr), .raddr(raddr), .wclken(wclken), .clk(wclk));
`else
    reg [DATASIZE-1:0] MEM [0:DEPTH-1];

    // Asynchronous read, synchronous write.  The testbench samples rdata before
    // the read pointer advances because rdata reflects the current raddr.
    assign rdata = MEM[raddr];

    always @(posedge wclk) begin
        if (wclken) begin
            MEM[waddr] <= wdata;
        end
    end
`endif

endmodule

module async_cmp (aempty_n, afull_n, wptr, rptr, wrst_n);
    parameter ADDRSIZE = 4;
    parameter N = ADDRSIZE - 1;

    output aempty_n, afull_n;
    input [N:0] wptr, rptr;
    input wrst_n;

    reg direction;
    wire high = 1'b1;

    // Quadrant decode:
    // - dirset_n pulses low when the write pointer trails the read pointer by
    //   one quadrant, meaning a future equal-pointer state should be "full".
    // - dirclr_n pulses low when the read pointer trails the write pointer by
    //   one quadrant, meaning a future equal-pointer state should be "empty".
    //
    // These equations are intentionally left close to the source material so the
    // standalone design remains recognizable for comparison/debug.
    wire dirset_n = ~((wptr[N] ^ rptr[N-1]) & ~(wptr[N-1] ^ rptr[N]));
    wire dirclr_n = ~((~(wptr[N] ^ rptr[N-1]) & (wptr[N-1] ^ rptr[N])) | ~wrst_n);

    // `high` gives this legacy latch-style block a deterministic set path in
    // event-driven simulation.  The reset/clear path dominates.
    always @(posedge high or negedge dirset_n or negedge dirclr_n) begin
        if (!dirclr_n) begin
            direction <= 1'b0;
        end else if (!dirset_n) begin
            direction <= 1'b1;
        end else begin
            direction <= high;
        end
    end

    // Active-low intermediate flags are consumed by the registered read/write
    // domain flag blocks below.
    assign aempty_n = ~((wptr == rptr) && !direction);
    assign afull_n  = ~((wptr == rptr) &&  direction);

endmodule

module rptr_empty (rempty, rptr, aempty_n, rinc, rclk, rrst_n);
    parameter ADDRSIZE = 4;

    output rempty;
    output [ADDRSIZE-1:0] rptr;
    input aempty_n;
    input rinc, rclk, rrst_n;

    reg [ADDRSIZE-1:0] rptr, rbin;
    reg rempty, rempty2;
    wire [ADDRSIZE-1:0] rgnext, rbnext;

    // Binary pointer is used for arithmetic; Gray pointer crosses the async
    // comparator boundary.  The registered Gray pointer is the module output.
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin <= 0;
            rptr <= 0;
        end else begin
            rbin <= rbnext;
            rptr <= rgnext;
        end
    end

    // Advance only on requested reads while the read domain believes the FIFO is
    // non-empty.
    assign rbnext = !rempty ? rbin + rinc : rbin;
    assign rgnext = (rbnext >> 1) ^ rbnext;

    // Synchronize the active-low asynchronous empty indication into rclk.  The
    // asynchronous assertion is preserved so empty is seen immediately when the
    // two Gray pointers become equal in the empty direction.
    always @(posedge rclk or negedge aempty_n) begin
        if (!aempty_n) begin
            {rempty, rempty2} <= 2'b11;
        end else begin
            {rempty, rempty2} <= {rempty2, ~aempty_n};
        end
    end

endmodule

module wptr_full (wfull, wptr, afull_n, winc, wclk, wrst_n);
    parameter ADDRSIZE = 4;

    output wfull;
    output [ADDRSIZE-1:0] wptr;
    input afull_n;
    input winc, wclk, wrst_n;

    reg [ADDRSIZE-1:0] wptr, wbin;
    reg wfull, wfull2;
    wire [ADDRSIZE-1:0] wgnext, wbnext;

    // Binary write pointer feeds the incrementer; Gray write pointer is exported
    // to the asynchronous comparator.
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin <= 0;
            wptr <= 0;
        end else begin
            wbin <= wbnext;
            wptr <= wgnext;
        end
    end

    // Advance only on requested writes while the write domain believes the FIFO
    // is not full.  Full protection therefore uses the registered write-domain
    // flag, not a testbench-side occupancy count.
    assign wbnext = !wfull ? wbin + winc : wbin;
    assign wgnext = (wbnext >> 1) ^ wbnext;

    // Synchronize the active-low asynchronous full indication into wclk.  The
    // asynchronous assertion is preserved so full is seen immediately when the
    // two Gray pointers become equal in the full direction.
    always @(posedge wclk or negedge wrst_n or negedge afull_n) begin
        if (!wrst_n) begin
            {wfull, wfull2} <= 2'b00;
        end else if (!afull_n) begin
            {wfull, wfull2} <= 2'b11;
        end else begin
            {wfull, wfull2} <= {wfull2, ~afull_n};
        end
    end

endmodule
