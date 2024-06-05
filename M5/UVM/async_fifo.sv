module asynchronous_fifo #(
    parameter DATA_SIZE = 8,   // Width of data in the FIFO
    parameter ADDR_SIZE = 6    // Width of address in the FIFO
) (
    input  logic winc, wclk, wrst,   // Write enable, write clock, write reset
    input  logic rinc, rclk, rrst,   // Read enable, read clock, read reset
    input  logic [DATA_SIZE-1:0] wData,  // Data input to FIFO
    output logic [DATA_SIZE-1:0] rData,  // Data output from FIFO
    output logic wFull, rEmpty,         // FIFO full and empty flags
    output logic wHalfFull, rHalfEmpty  // FIFO half-full and half-empty flags
);

    // Internal signals
    logic [ADDR_SIZE-1:0] waddr, raddr;       // Write and read addresses
    logic [ADDR_SIZE:0] g_wptr, g_rptr;       // Gray-coded write and read pointers
    logic [ADDR_SIZE:0] g_wptr_sync, g_rptr_sync; // Synchronized gray-coded pointers
    logic [ADDR_SIZE:0] wptr, rptr;           // Binary write and read pointers
    logic [ADDR_SIZE:0] wptr_s, rptr_s;       // Synchronized binary pointers

    // FIFO Memory instance
    fifo_mem #(DATA_SIZE, ADDR_SIZE) fifo_mem_inst (
        .wclk(wclk),
        .w_en(winc),
        .rclk(rclk),
        .r_en(rinc),
        .b_wptr(wptr),
        .b_rptr(rptr),
        .data_in(wData),
        .full(wFull),
        .empty(rEmpty),
        .data_out(rData)
    );

    // Synchronizer instances for read and write pointers
    synchronizer #(ADDR_SIZE) synchronizer_r2w_inst (
        .clk(rclk),
        .rst_n(rrst),
        .d_in(g_rptr),
        .d_out(g_rptr_sync)
    );

    synchronizer #(ADDR_SIZE) synchronizer_w2r_inst (
        .clk(wclk),
        .rst_n(wrst),
        .d_in(g_wptr),
        .d_out(g_wptr_sync)
    );

    // Read pointer handler instance
    rptr_handler #(ADDR_SIZE) rptr_handler_inst (
        .rclk(rclk),
        .rrst_n(rrst),
        .r_en(rinc),
        .g_wptr_sync(g_wptr_sync),
        .b_rptr(rptr),
        .g_rptr(g_rptr),
        .empty(rEmpty),
        .half_empty(rHalfEmpty)
    );

    // Write pointer handler instance
    wptr_handler #(ADDR_SIZE) wptr_handler_inst (
        .wclk(wclk),
        .wrst_n(wrst),
        .w_en(winc),
        .g_rptr_sync(g_rptr_sync),
        .b_wptr(wptr),
        .g_wptr(g_wptr),
        .full(wFull),
        .half_full(wHalfFull)
    );

endmodule

module fifo_mem #(
    parameter DATA_SIZE=8,   // Width of data in the FIFO
    parameter ADDR_SIZE=6    // Width of address in the FIFO
) (
    input wclk, w_en, rclk, r_en,   // Write clock, write enable, read clock, read enable
    input [ADDR_SIZE:0] b_wptr, b_rptr, // Binary write and read pointers
    input [DATA_SIZE-1:0] data_in,      // Data input to FIFO
    input full, empty,                  // FIFO full and empty flags
    output reg [DATA_SIZE-1:0] data_out // Data output from FIFO
);

    // FIFO depth
    localparam DEPTH = 1 << ADDR_SIZE;

    // FIFO memory array
    reg [DATA_SIZE-1:0] fifo[0:DEPTH-1];

    // Write operation
    always_ff @(posedge wclk) begin
        if(w_en & !full) begin
            fifo[b_wptr[ADDR_SIZE-1:0]] <= data_in;
        end
    end

    // Read operation
    always_ff @(posedge rclk) begin
        `ifdef INJECT_THE_BUG
            if(r_en & !empty) begin
                data_out <= fifo[b_rptr[ADDR_SIZE-1:0]] ^ 8'hFF; // Corrupting data by XORing with 0xFF
            end
        `else
            if(r_en & !empty) begin
                data_out <= fifo[b_rptr[ADDR_SIZE-1:0]];
            end
        `endif
    end

endmodule

module synchronizer #(
    parameter ADDR_SIZE = 6  // Width of address in the FIFO
) (
    input clk, rst_n,                 // Clock and active-low reset
    input [ADDR_SIZE:0] d_in,         // Data input
    output reg [ADDR_SIZE:0] d_out    // Synchronized data output
);

    reg [ADDR_SIZE:0] q1;  // Intermediate register

    // Synchronizer logic
    always @(posedge clk) begin
        if(!rst_n) begin
            q1 <= '0;
            d_out <= '0;
        end
        else begin
            `ifdef INJECT_THE_BUG
                q1 <= '0;    // Introduce bug: q1 is not assigned d_in
                d_out <= q1; // This results in q1 always being zero
            `else
                q1 <= d_in;
                d_out <= q1;
            `endif
        end
    end

endmodule

module rptr_handler #(
    parameter PTR_WIDTH=6  // Width of pointer
) (
    input rclk, rrst_n, r_en,               // Read clock, active-low reset, read enable
    input [PTR_WIDTH:0] g_wptr_sync,        // Synchronized gray-coded write pointer
    output reg [PTR_WIDTH:0] b_rptr, g_rptr,// Binary and gray-coded read pointers
    output reg empty,                       // FIFO empty flag
    output reg half_empty                   // FIFO half-empty flag
);

    reg [PTR_WIDTH:0] b_rptr_next;  // Next binary read pointer
    reg [PTR_WIDTH:0] g_rptr_next;  // Next gray-coded read pointer
    wire rempty, rhalf_empty;       // Intermediate empty and half-empty flags

    wire [PTR_WIDTH:0] b_wptr_sync; // Synchronized binary write pointer
    wire [PTR_WIDTH:0] rptr_diff;   // Difference between write and read pointers

    localparam DEPTH = 1 << PTR_WIDTH;  // FIFO depth

    // Calculate next read pointers
    assign b_rptr_next = b_rptr + (r_en & !empty);
    assign g_rptr_next = (b_rptr_next >>1) ^ b_rptr_next;

    // Convert gray-coded write pointer to binary
    generate
        genvar i;
        assign b_wptr_sync[PTR_WIDTH] = g_wptr_sync[PTR_WIDTH];
        for (i = PTR_WIDTH-1; i >= 0; i = i - 1) begin : gen_binary_conversion
            assign b_wptr_sync[i] = b_wptr_sync[i+1] ^ g_wptr_sync[i];
        end
    endgenerate

    // Calculate pointer difference and half-empty flag
    assign rptr_diff  = b_wptr_sync - b_rptr;
    assign rhalf_empty = (rptr_diff <= (DEPTH >> 1));

    `ifdef INJECT_THE_BUG
        // Introduce bug in empty flag calculation
        assign rempty = (g_wptr_sync == g_rptr_next) & (rptr_diff != 0);
    `else
        // Calculate empty flag
        assign rempty = (g_wptr_sync == g_rptr_next);
    `endif

    // Update read pointers and flags on clock edge or reset
    always_ff @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) begin
            b_rptr <= '0;
            g_rptr <= '0;
        end
        else begin
            b_rptr <= b_rptr_next;
            g_rptr <= g_rptr_next;
        end
    end

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) half_empty <= '1;
        else half_empty <= rhalf_empty;
    end

    always_ff @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) empty <= '1;
        else        empty <= rempty;
    end

endmodule

module wptr_handler #(
    parameter PTR_WIDTH=6  // Width of pointer
) (
    input wclk, wrst_n, w_en,               // Write clock, active-low reset, write enable
    input [PTR_WIDTH:0] g_rptr_sync,        // Synchronized gray-coded read pointer
    output reg [PTR_WIDTH:0] b_wptr, g_wptr,// Binary and gray-coded write pointers
    output reg full,                        // FIFO full flag
    output reg half_full                    // FIFO half-full flag
);

    reg [PTR_WIDTH:0] b_wptr_next;  // Next binary write pointer
    reg [PTR_WIDTH:0] g_wptr_next;  // Next gray-coded write pointer
    wire wfull, whalf_full;         // Intermediate full and half-full flags

    wire [PTR_WIDTH:0] b_rptr_sync; // Synchronized binary read pointer
    wire [PTR_WIDTH:0] wptr_diff;   // Difference between write and read pointers

    localparam DEPTH = 1 << PTR_WIDTH;  // FIFO depth
    
    // Calculate next write pointers
    assign b_wptr_next = b_wptr + (w_en & !full);
    assign g_wptr_next = (b_wptr_next >>1) ^ b_wptr_next;

    // Convert gray-coded read pointer to binary
    generate
        genvar i;
        assign b_rptr_sync[PTR_WIDTH] = g_rptr_sync[PTR_WIDTH];
        for (i = PTR_WIDTH-1; i >= 0; i = i - 1) begin : gen_binary_conversion
            assign b_rptr_sync[i] = b_rptr_sync[i+1] ^ g_rptr_sync[i];
        end
    endgenerate

    // Calculate pointer difference and half-full flag
    assign wptr_diff  = b_wptr - b_rptr_sync;
    assign whalf_full = (wptr_diff >= (DEPTH >> 1));

    `ifdef INJECT_THE_BUG
        // Introduce bug in full flag calculation
        assign wfull = (g_wptr_next == g_rptr_sync);
    `else
        // Calculate full flag
        assign wfull = (g_wptr_next == {~g_rptr_sync[PTR_WIDTH:PTR_WIDTH-1], g_rptr_sync[PTR_WIDTH-2:0]});
    `endif
    
    // Update write pointers and flags on clock edge or reset
    always_ff @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) begin
            b_wptr <= '0;
            g_wptr <= '0;
        end
        else begin
            b_wptr <= b_wptr_next;
            g_wptr <= g_wptr_next;
        end
    end

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) half_full <= '0;
        else half_full <= whalf_full;
    end

    always_ff @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) full <= '0;
        else        full <= wfull;
    end

endmodule
