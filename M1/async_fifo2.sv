module fifo2 (rdata, wfull, rempty, wdata, winc, wclk, wrst_n, rinc, rclk, rrst_n);
    parameter DSIZE = 8;
    parameter ASIZE = 6;

    output [DSIZE-1:0] rdata;
    output wfull;
    output rempty;
    input [DSIZE-1:0] wdata;
    input winc, wclk, wrst_n;
    input rinc, rclk, rrst_n;
    wire [ASIZE-1:0] wptr, rptr;
    wire [ASIZE-1:0] waddr, raddr;
    wire aempty_n, afull_n;

    async_cmp  #(ASIZE)        async_cmp  (.aempty_n(aempty_n), .afull_n(afull_n), .wptr(wptr), .rptr(rptr), .wrst_n(wrst_n));
    fifomem    #(DSIZE, ASIZE) fifomem    (.rdata(rdata), .wdata(wdata), .waddr(waddr), .raddr(raddr), .wclken(winc & ~wfull), .wclk(wclk));
    rptr_empty #(ASIZE)        rptr_empty (.rempty(rempty), .rptr(rptr), .raddr(raddr), .aempty_n(aempty_n), .rinc(rinc), .rclk(rclk), .rrst_n(rrst_n));
    wptr_full  #(ASIZE)        wptr_full  (.wfull(wfull), .wptr(wptr), .waddr(waddr), .afull_n(afull_n), .winc(winc), .wclk(wclk), .wrst_n(wrst_n));

endmodule

module fifomem (rdata, wdata, waddr, raddr, wclken, wclk);
    parameter DATASIZE = 8; // Memory data word width
    parameter ADDRSIZE = 6; // Number of memory address bits
    parameter DEPTH = 1<<ADDRSIZE; // DEPTH = 2**ADDRSIZE

    output [DATASIZE-1:0] rdata;
    input [DATASIZE-1:0] wdata;
    input [ADDRSIZE-1:0] waddr, raddr;
    input wclken, wclk;

    reg [DATASIZE-1:0] MEM [0:DEPTH-1];
    assign rdata = MEM[raddr];
    always @(posedge wclk)
        if (wclken) MEM[waddr] <= wdata;

endmodule

module async_cmp (aempty_n, afull_n, wptr, rptr, wrst_n);
    parameter ADDRSIZE = 6;
    parameter N = ADDRSIZE-1;

    output aempty_n, afull_n;
    input [N:0] wptr, rptr;
    input wrst_n;
    reg direction = 1'b0;
    wire dirset_n = ~( (wptr[N]^rptr[N-1]) & ~(wptr[N-1]^rptr[N]));
    wire dirclr_n = ~((~(wptr[N]^rptr[N-1]) & (wptr[N-1]^rptr[N])) | ~wrst_n);
    always @(negedge dirset_n or negedge dirclr_n)
        if      (!dirclr_n) direction <= 1'b0;
        else if (!dirset_n) direction <= 1'b1;
    assign aempty_n = ~((wptr == rptr) && !direction);
    assign afull_n = ~((wptr == rptr) && direction);

endmodule

module rptr_empty (rempty, rptr, raddr, aempty_n, rinc, rclk, rrst_n);
    parameter ADDRSIZE = 6;

    output rempty;
    output [ADDRSIZE-1:0] rptr;
    output [ADDRSIZE-1:0] raddr;
    input aempty_n;
    input rinc, rclk, rrst_n;
    reg [ADDRSIZE-1:0] rptr, rbin;
    reg rempty, rempty2;
    wire [ADDRSIZE-1:0] rgnext, rbnext;

    assign raddr = rbin;

    //---------------------------------------------------------------
    // GRAYSTYLE2 pointer
    //---------------------------------------------------------------
    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n) begin
        rbin <= 0;
        rptr <= 0;
        end
        else begin
        rbin <= rbnext;
        rptr <= rgnext;
        end
    //---------------------------------------------------------------
    // increment the binary count if not empty
    //---------------------------------------------------------------
    assign rbnext = !rempty ? rbin + rinc : rbin;
    assign rgnext = (rbnext>>1) ^ rbnext; // binary-to-gray conversion
    always @(posedge rclk or negedge rrst_n or negedge aempty_n)
        if      (!rrst_n)   {rempty,rempty2} <= 2'b11;
        else if (!aempty_n) {rempty,rempty2} <= 2'b11;
        else                {rempty,rempty2} <= {rempty2,~aempty_n};

endmodule

module wptr_full (wfull, wptr, waddr, afull_n, winc, wclk, wrst_n);
    parameter ADDRSIZE = 6;

    output wfull;
    output [ADDRSIZE-1:0] wptr;
    output [ADDRSIZE-1:0] waddr;
    input afull_n;
    input winc, wclk, wrst_n;
    reg [ADDRSIZE-1:0] wptr, wbin;
    reg wfull, wfull2;
    wire [ADDRSIZE-1:0] wgnext, wbnext;

    assign waddr = wbin;

    //---------------------------------------------------------------
    // GRAYSTYLE2 pointer
    //---------------------------------------------------------------
    always @(posedge wclk or negedge wrst_n)
        if (!wrst_n) begin
        wbin <= 0;
        wptr <= 0;
        end
        else begin
        wbin <= wbnext;
        wptr <= wgnext;
        end
    //---------------------------------------------------------------
    // increment the binary count if not full
    //---------------------------------------------------------------
    assign wbnext = !wfull ? wbin + winc : wbin;
    assign wgnext = (wbnext>>1) ^ wbnext; // binary-to-gray conversion
    always @(posedge wclk or negedge wrst_n or negedge afull_n)
        if (!wrst_n ) {wfull,wfull2} <= 2'b00;
        else if (!afull_n) {wfull,wfull2} <= 2'b11;
        else {wfull,wfull2} <= {wfull2,~afull_n};

endmodule
