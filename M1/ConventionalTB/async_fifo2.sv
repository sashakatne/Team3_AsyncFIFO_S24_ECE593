module asynchronous_fifo #(
    parameter DATA_SIZE = 8,
    parameter ADDR_SIZE = 6  // Log2 of FIFO depth 64
)(
    input  logic                   wclk, rclk, wrst, rrst,
    input  logic                   winc, rinc,
    input  logic [DATA_SIZE-1:0]  wData,
    output logic [DATA_SIZE-1:0]  rData,
    output logic                   wFull, rEmpty, wHalfFull, rHalfEmpty
);

    // Internal signals for fifo_top
    logic [ADDR_SIZE:0] wptr, rptr;
    logic [ADDR_SIZE-1:0] waddr, raddr;
    logic [ADDR_SIZE:0] wq2_rptr, rq2_wptr;

    // Memory
    fifo_memory #(.DATA_SIZE(DATA_SIZE), .ADDR_SIZE(ADDR_SIZE)) mem_inst (
        .wclk(wclk),
        .rclk(rclk),
        .wrst(wrst),
        .rrst(rrst),
        .waddr(waddr),
        .raddr(raddr),
        .wData(wData),
        .rData(rData),
        .winc(winc & ~wFull),
        .rinc(rinc & ~rEmpty)
    );

    // Write Pointer and Full Flag Logic
    write_pointer #(.ADDR_SIZE(ADDR_SIZE)) write_ptr (
        .clk(wclk),
        .rst_n(wrst),
        .inc(winc),
        .wptr(wptr),
        .waddr(waddr),
        .wq2_rptr(wq2_rptr),
        .wFull(wFull),
        .wHalfFull(wHalfFull)
    );

    // Read Pointer and Empty Flag Logic
    read_pointer #(.ADDR_SIZE(ADDR_SIZE)) read_ptr (
        .clk(rclk),
        .rst_n(rrst),
        .inc(rinc),
        .rptr(rptr),
        .raddr(raddr),
        .rq2_wptr(rq2_wptr),
        .rEmpty(rEmpty),
        .rHalfEmpty(rHalfEmpty)
    );

    // Synchronization from write to read domain (clocked by rclk, reset by rrst)
    sync #(.ADDR_SIZE(ADDR_SIZE)) sync_w2r (
        .clk(rclk),
        .rst_n(rrst),
        .wData(wptr),
        .rData(rq2_wptr)
    );

    // Synchronization from read to write domain (clocked by wclk, reset by wrst)
    sync #(.ADDR_SIZE(ADDR_SIZE)) sync_r2w (
        .clk(wclk),
        .rst_n(wrst),
        .wData(rptr),
        .rData(wq2_rptr)
    );

endmodule

module fifo_memory #(
    parameter DATA_SIZE = 8,
    parameter ADDR_SIZE = 6
)(
    input  logic                      wclk, rclk,
    input  logic                      winc, rinc,
    input  logic                      wrst, rrst,
    input  logic  [ADDR_SIZE-1:0]    waddr, raddr,
    input  logic  [DATA_SIZE-1:0]    wData,
    output logic  [DATA_SIZE-1:0]    rData
);

    logic [DATA_SIZE-1:0] mem[2**ADDR_SIZE-1:0];

    // Write logic
    always_ff @(posedge wclk) begin
        if (winc) begin
            `ifdef WDATA_CORRUPTION_BUG
                mem[waddr] <= wData ^ 8'hFF; // Bug: corrupting the data
            `else
                mem[waddr] <= wData;
            `endif
        end
    end

    // Read logic (registered output)
    always_ff @(posedge rclk or negedge rrst) begin
        if (!rrst) begin
            rData <= '0;
        end else if (rinc) begin
            rData <= mem[raddr];
        end
    end

endmodule

module sync #(
    parameter ADDR_SIZE = 6
)(
    input  logic             clk, rst_n,
    input  logic [ADDR_SIZE:0] wData,
    output logic [ADDR_SIZE:0] rData
);

    logic [ADDR_SIZE:0] buffer;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rData <= '0;
            buffer <= '0;
        end else begin
            buffer <= wData;
            `ifdef SYNC_BUG
                rData <= wData;
            `else
                rData <= buffer;
            `endif
        end
    end

endmodule

module read_pointer #(
    parameter ADDR_SIZE = 6
)(
    input  logic                    clk, rst_n, inc,
    input  logic [ADDR_SIZE:0]     rq2_wptr,
    output logic [ADDR_SIZE:0]     rptr,
    output logic [ADDR_SIZE-1:0]   raddr,
    output logic                    rEmpty,
    output logic                    rHalfEmpty
);

    logic [ADDR_SIZE:0]    gray_rptr_next;
    logic [ADDR_SIZE:0]    binary_rptr, binary_rptr_next;
    logic                   empty_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr <= '0;
            binary_rptr <= '0;
            rEmpty <= '1;
        end
        else begin
            rptr <= gray_rptr_next;
            binary_rptr <= binary_rptr_next;
            rEmpty <= empty_next;
        end
    end

    assign empty_next = (gray_rptr_next == rq2_wptr);
    `ifdef RPTR_BUG
        assign gray_rptr_next = binary_rptr_next; // Bug: directly assigning binary_rptr_next
    `else
        assign gray_rptr_next = (binary_rptr_next >> 1) ^ binary_rptr_next;
    `endif
    assign binary_rptr_next = binary_rptr + (inc & ~rEmpty);
    assign raddr = binary_rptr[ADDR_SIZE-1:0];

    // Half-empty flag: computed locally in the read domain using the synced
    // write pointer (rq2_wptr is Gray, converted to binary by an XOR cascade).
    logic [ADDR_SIZE:0] rq2_wptr_bin;
    always_comb begin
        rq2_wptr_bin[ADDR_SIZE] = rq2_wptr[ADDR_SIZE];
        for (int i = ADDR_SIZE-1; i >= 0; i--)
            rq2_wptr_bin[i] = rq2_wptr_bin[i+1] ^ rq2_wptr[i];
    end
    assign rHalfEmpty = (rq2_wptr_bin - binary_rptr) <= (1 << (ADDR_SIZE-1));

endmodule

module write_pointer #(
    parameter ADDR_SIZE = 6
)(
    input  logic                    clk, rst_n, inc,
    input  logic [ADDR_SIZE:0]     wq2_rptr,
    output logic [ADDR_SIZE:0]     wptr,
    output logic [ADDR_SIZE-1:0]   waddr,
    output logic                    wFull,
    output logic                    wHalfFull
);

    logic   [ADDR_SIZE:0]  binary_wptr;
    logic   [ADDR_SIZE:0]  binary_wptr_next, gray_wptr_next;
    logic                   full_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= '0;
            binary_wptr <= '0;
            wFull <= '0;
        end
        else begin
            wptr <= gray_wptr_next;
            binary_wptr <= binary_wptr_next;
            wFull <= full_next;
        end
    end

    assign waddr = binary_wptr[ADDR_SIZE-1:0];
    assign binary_wptr_next = binary_wptr + (inc & ~wFull);
    assign gray_wptr_next = (binary_wptr_next>>1) ^ binary_wptr_next;

    `ifdef WPTR_FULLFLAG_BUG
        assign full_next = (gray_wptr_next == wq2_rptr); // Bug: directly comparing gray_wptr_next with wq2_rptr
    `else
        assign full_next =  ((gray_wptr_next[ADDR_SIZE-2:0] == wq2_rptr[ADDR_SIZE-2:0]) &&
                            (gray_wptr_next[ADDR_SIZE-1:0] != wq2_rptr[ADDR_SIZE-1:0]) &&
                            (gray_wptr_next[ADDR_SIZE] != wq2_rptr[ADDR_SIZE]));
    `endif

    // Half-full flag: computed locally in the write domain using the synced
    // read pointer (wq2_rptr is Gray, converted to binary by an XOR cascade).
    logic [ADDR_SIZE:0] wq2_rptr_bin;
    always_comb begin
        wq2_rptr_bin[ADDR_SIZE] = wq2_rptr[ADDR_SIZE];
        for (int i = ADDR_SIZE-1; i >= 0; i--)
            wq2_rptr_bin[i] = wq2_rptr_bin[i+1] ^ wq2_rptr[i];
    end
    assign wHalfFull = (binary_wptr - wq2_rptr_bin) >= (1 << (ADDR_SIZE-1));

endmodule
