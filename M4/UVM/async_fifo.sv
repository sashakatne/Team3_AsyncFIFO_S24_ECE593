module asynchronous_fifo #(
    parameter DATA_SIZE = 8,
    parameter ADDR_SIZE = 6
) (
    input  logic winc, wclk, wrst,
    input  logic rinc, rclk, rrst,
    input  logic [DATA_SIZE-1:0] wData,
    output logic [DATA_SIZE-1:0] rData,
    output logic wFull, rEmpty, wHalfFull, rHalfEmpty
);
	
    //Internal Wires
    logic [ADDR_SIZE-1:0] waddr, raddr;   //Adress logics - Pointer modules to Memory array
    logic [ADDR_SIZE:0] g_wptr, g_rptr; //Grey Code Pointers
    logic [ADDR_SIZE:0] g_wptr_sync, g_rptr_sync; //Synchronized Grey Code Pointers
    logic [ADDR_SIZE:0] wptr, rptr;      //Pointers generated from Pointer modules
    logic [ADDR_SIZE:0] wptr_s, rptr_s; //Synchronized Pointers - output of Synchronizers to Full/Empty 

    //FIFO Memory
    fifo_mem #(DATA_SIZE, ADDR_SIZE) fifo_mem_inst (.wclk(wclk), .w_en(winc), .rclk(rclk), .r_en(rinc), .b_wptr(wptr), .b_rptr(rptr), .data_in(wData), .full(wFull), .empty(rEmpty), .data_out(rData));
    synchronizer #(ADDR_SIZE) synchronizer_r2w_inst (.clk(rclk), .rst_n(rrst), .d_in(g_rptr), .d_out(g_rptr_sync));
    synchronizer #(ADDR_SIZE) synchronizer_w2r_inst (.clk(wclk), .rst_n(wrst), .d_in(g_wptr), .d_out(g_wptr_sync));
    rptr_handler #(ADDR_SIZE) rptr_handler_inst (.rclk(rclk), .rrst_n(rrst), .r_en(rinc), .g_wptr_sync(g_wptr_sync), .b_rptr(rptr), .g_rptr(g_rptr), .empty(rEmpty), .half_empty(rHalfEmpty));
    wptr_handler #(ADDR_SIZE) wptr_handler_inst (.wclk(wclk), .wrst_n(wrst), .w_en(winc), .g_rptr_sync(g_rptr_sync), .b_wptr(wptr), .g_wptr(g_wptr), .full(wFull), .half_full(wHalfFull));

endmodule

module fifo_mem #(
    parameter DATA_SIZE=8,
    parameter ADDR_SIZE=6
  ) (
    input wclk, w_en, rclk, r_en,
    input [ADDR_SIZE:0] b_wptr, b_rptr,
    input [DATA_SIZE-1:0] data_in,
    input full, empty,
    output reg [DATA_SIZE-1:0] data_out
);

    localparam DEPTH = 1<<ADDR_SIZE;
    reg [DATA_SIZE-1:0] fifo[0:DEPTH-1];
    
    always_ff @(posedge wclk) begin
      if(w_en & !full) begin
        fifo[b_wptr[ADDR_SIZE-1:0]] <= data_in;
      end
    end

    // assign data_out = fifo[b_rptr[ADDR_SIZE-1:0]];
    
    always_ff @(posedge rclk) begin
      if(r_en & !empty) begin
        data_out <= fifo[b_rptr[ADDR_SIZE-1:0]];
      end
    end

endmodule

module synchronizer #(
    parameter ADDR_SIZE = 6
) (
    input clk, rst_n,
    input [ADDR_SIZE:0] d_in,
    output reg [ADDR_SIZE:0] d_out
);

    reg [ADDR_SIZE:0] q1;
    always@(posedge clk) begin
      if(!rst_n) begin
        q1 <= '0;
        d_out <= '0;
      end
      else begin
        q1 <= d_in;
        d_out <= q1;
      end
    end

endmodule

module rptr_handler #(
    parameter PTR_WIDTH=6
  ) (
    input rclk, rrst_n, r_en,
    input [PTR_WIDTH:0] g_wptr_sync,
    output reg [PTR_WIDTH:0] b_rptr, g_rptr,
    output reg empty,
    output reg half_empty
);

    reg [PTR_WIDTH:0] b_rptr_next;
    reg [PTR_WIDTH:0] g_rptr_next;
    wire rempty, rhalf_empty;

    wire [PTR_WIDTH:0] b_wptr_sync;
    wire [PTR_WIDTH:0] rptr_diff;

    localparam DEPTH = 1 << PTR_WIDTH;

    assign b_rptr_next = b_rptr + (r_en & !empty);
    assign g_rptr_next = (b_rptr_next >>1) ^ b_rptr_next;

    generate
        genvar i;
        // The MSB of the binary code is the same as the MSB of the Grey code
        assign b_wptr_sync[PTR_WIDTH] = g_wptr_sync[PTR_WIDTH];

        // For the rest of the bits, each bit is the XOR of the current Grey code bit and all more significant binary bits
        for (i = PTR_WIDTH-1; i >= 0; i = i - 1) begin : gen_binary_conversion
            assign b_wptr_sync[i] = b_wptr_sync[i+1] ^ g_wptr_sync[i];
        end
    endgenerate
    assign rptr_diff  = b_wptr_sync - b_rptr;
    assign rhalf_empty = (rptr_diff <= (DEPTH >> 1));

    assign rempty = (g_wptr_sync == g_rptr_next);

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
    parameter PTR_WIDTH=6
  ) (
    input wclk, wrst_n, w_en,
    input [PTR_WIDTH:0] g_rptr_sync,
    output reg [PTR_WIDTH:0] b_wptr, g_wptr,
    output reg full,
    output reg half_full
);

    reg [PTR_WIDTH:0] b_wptr_next;
    reg [PTR_WIDTH:0] g_wptr_next;
    wire wfull, whalf_full;

    wire [PTR_WIDTH:0] b_rptr_sync;
    wire [PTR_WIDTH:0] wptr_diff;

    localparam DEPTH = 1 << PTR_WIDTH;
    
    assign b_wptr_next = b_wptr + (w_en & !full);
    assign g_wptr_next = (b_wptr_next >>1) ^ b_wptr_next;

    generate
        genvar i;
        // The MSB of the binary code is the same as the MSB of the Grey code
        assign b_rptr_sync[PTR_WIDTH] = g_rptr_sync[PTR_WIDTH];

        // For the rest of the bits, each bit is the XOR of the current Grey code bit and all more significant binary bits
        for (i = PTR_WIDTH-1; i >= 0; i = i - 1) begin : gen_binary_conversion
            assign b_rptr_sync[i] = b_rptr_sync[i+1] ^ g_rptr_sync[i];
        end
    endgenerate
    assign wptr_diff  = b_wptr - b_rptr_sync;
    assign whalf_full = (wptr_diff >= (DEPTH >> 1));

    assign wfull = (g_wptr_next == {~g_rptr_sync[PTR_WIDTH:PTR_WIDTH-1], g_rptr_sync[PTR_WIDTH-2:0]});
    
    always_ff @(posedge wclk or negedge wrst_n) begin
      if(!wrst_n) begin
        b_wptr <= '0;
        g_wptr <= '0;
      end
      else begin
        b_wptr <= b_wptr_next; // incr binary write pointer
        g_wptr <= g_wptr_next; // incr gray write pointer
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
