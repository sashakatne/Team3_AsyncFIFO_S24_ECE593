module asynchronous_fifo #(parameter DEPTH=64, DATA_WIDTH=8) (
  input wclk, wrst_n,
  input rclk, rrst_n,
  input w_en, r_en,
  input [DATA_WIDTH-1:0] data_in,
  output reg [DATA_WIDTH-1:0] data_out,
  output reg full, empty,
  output reg half_full, half_empty
);
  
  parameter PTR_WIDTH = $clog2(DEPTH);
 
  reg [PTR_WIDTH:0] g_wptr_sync, g_rptr_sync;
  reg [PTR_WIDTH:0] b_wptr, b_rptr;
  reg [PTR_WIDTH:0] g_wptr, g_rptr;

  wire [PTR_WIDTH-1:0] waddr, raddr;

  synchronizer #(PTR_WIDTH) sync_wptr (rclk, rrst_n, g_wptr, g_wptr_sync); //write pointer to read clock domain
  synchronizer #(PTR_WIDTH) sync_rptr (wclk, wrst_n, g_rptr, g_rptr_sync); //read pointer to write clock domain 
  
  wptr_handler #(PTR_WIDTH) wptr_h(wclk, wrst_n, w_en, g_rptr_sync, b_wptr, g_wptr, full,  half_full);
  rptr_handler #(PTR_WIDTH) rptr_h(rclk, rrst_n, r_en, g_wptr_sync, b_rptr, g_rptr, empty,  half_empty);
  fifo_mem fifom(wclk, w_en, rclk, r_en, b_wptr, b_rptr, data_in, full, empty, data_out);

endmodule

module synchronizer #(parameter PTR_WIDTH=6) (input clk, rst_n, [PTR_WIDTH:0] d_in, output reg [PTR_WIDTH:0] d_out);
  reg [PTR_WIDTH:0] q1;
  always@(posedge clk) begin
    if(!rst_n) begin
      q1 <= 0;
      d_out <= 0;
    end
    else begin
      q1 <= d_in;
      d_out <= q1;
    end
  end
endmodule

module wptr_handler #(parameter PTR_WIDTH=6) (
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

  // assign b_rptr_sync = {g_rptr_sync[PTR_WIDTH:PTR_WIDTH-1], g_rptr_sync[PTR_WIDTH-2:0] ^ g_rptr_sync[PTR_WIDTH-1:PTR_WIDTH-1]};
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
  
  always@(posedge wclk or negedge wrst_n) begin
    if(!wrst_n) begin
      b_wptr <= '0;
      g_wptr <= '0;
    end
    else begin
      b_wptr <= b_wptr_next; // incr binary write pointer
      g_wptr <= g_wptr_next; // incr gray write pointer
    end
  end

  always @(posedge wclk or negedge wrst_n) begin
      if (!wrst_n) half_full <= '0;
      else half_full <= whalf_full;
  end

  always@(posedge wclk or negedge wrst_n) begin
    if(!wrst_n) full <= '0;
    else        full <= wfull;
  end

endmodule

module rptr_handler #(parameter PTR_WIDTH=6) (
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

  always@(posedge rclk or negedge rrst_n) begin
    if(!rrst_n) begin
      b_rptr <= '0;
      g_rptr <= '0;
    end
    else begin
      b_rptr <= b_rptr_next;
      g_rptr <= g_rptr_next;
    end
  end

  always @(posedge rclk or negedge rrst_n) begin
      if (!rrst_n) half_empty <= '1;
      else half_empty <= rhalf_empty;
  end

  always@(posedge rclk or negedge rrst_n) begin
    if(!rrst_n) empty <= '1;
    else        empty <= rempty;
  end
endmodule

module fifo_mem #(parameter DEPTH=64, DATA_WIDTH=8, PTR_WIDTH=6) (
  input wclk, w_en, rclk, r_en,
  input [PTR_WIDTH:0] b_wptr, b_rptr,
  input [DATA_WIDTH-1:0] data_in,
  input full, empty,
  output reg [DATA_WIDTH-1:0] data_out
);
  reg [DATA_WIDTH-1:0] fifo[0:DEPTH-1];
  
  always@(posedge wclk) begin
    if(w_en & !full) begin
      fifo[b_wptr[PTR_WIDTH-1:0]] <= data_in;
    end
  end

  assign data_out = fifo[b_rptr[PTR_WIDTH-1:0]];
endmodule