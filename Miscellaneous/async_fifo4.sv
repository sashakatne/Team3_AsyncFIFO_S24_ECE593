`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Standalone synchronizer-based asynchronous FIFO.
//
// This is the cleaner Miscellaneous FIFO variant.  Unlike async_fifo2.sv, this
// design does not use an asynchronous pointer comparator.  Each clock domain
// exports a Gray-coded pointer to the opposite domain through a two-flop
// synchronizer, converts the synchronized Gray pointer back to binary locally,
// and computes status flags from local next-pointer occupancy.
//
// Important timing convention:
//   * Writes are accepted on wclk when `w_en && !full` was true before the edge.
//   * Reads are accepted on rclk when `r_en && !empty` was true before the edge.
//   * `full`, `empty`, `half_full`, and `half_empty` are registered in their
//     destination clock domains.
//
// The half flags intentionally use next-pointer occupancy, matching full/empty
// timing.  That makes the half-threshold flags assert on the same clock edge
// that accepts the transfer crossing the threshold instead of one clock late.
// -----------------------------------------------------------------------------

module asynchronous_fifo #(
  parameter DEPTH = 64,
  parameter DATA_WIDTH = 8
) (
  input wclk, wrst_n,
  input rclk, rrst_n,
  input w_en, r_en,
  input [DATA_WIDTH-1:0] data_in,
  output wire [DATA_WIDTH-1:0] data_out,
  output wire full, empty,
  output wire half_full, half_empty
);

  // DEPTH is expected to be a power of two.  PTR_WIDTH address bits index the
  // RAM; the extra pointer MSB distinguishes "same address, different wrap" for
  // full/empty detection.
  parameter PTR_WIDTH = $clog2(DEPTH);

  wire [PTR_WIDTH:0] g_wptr_sync, g_rptr_sync;
  wire [PTR_WIDTH:0] b_wptr, b_rptr;
  wire [PTR_WIDTH:0] g_wptr, g_rptr;

  synchronizer #(PTR_WIDTH) sync_wptr (
    .clk(rclk),
    .rst_n(rrst_n),
    .d_in(g_wptr),
    .d_out(g_wptr_sync)
  );

  synchronizer #(PTR_WIDTH) sync_rptr (
    .clk(wclk),
    .rst_n(wrst_n),
    .d_in(g_rptr),
    .d_out(g_rptr_sync)
  );

  wptr_handler #(PTR_WIDTH) wptr_h (
    .wclk(wclk),
    .wrst_n(wrst_n),
    .w_en(w_en),
    .g_rptr_sync(g_rptr_sync),
    .b_wptr(b_wptr),
    .g_wptr(g_wptr),
    .full(full),
    .half_full(half_full)
  );

  rptr_handler #(PTR_WIDTH) rptr_h (
    .rclk(rclk),
    .rrst_n(rrst_n),
    .r_en(r_en),
    .g_wptr_sync(g_wptr_sync),
    .b_rptr(b_rptr),
    .g_rptr(g_rptr),
    .empty(empty),
    .half_empty(half_empty)
  );

  fifo_mem #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH),
    .PTR_WIDTH(PTR_WIDTH)
  ) fifom (
    .wclk(wclk),
    .w_en(w_en),
    .rclk(rclk),
    .r_en(r_en),
    .b_wptr(b_wptr),
    .b_rptr(b_rptr),
    .data_in(data_in),
    .full(full),
    .empty(empty),
    .data_out(data_out)
  );

endmodule

module synchronizer #(
  parameter PTR_WIDTH = 6
) (
  input clk,
  input rst_n,
  input [PTR_WIDTH:0] d_in,
  output reg [PTR_WIDTH:0] d_out
);

  reg [PTR_WIDTH:0] q1;

  // Two destination-clock flops are the CDC boundary.  Gray coding guarantees
  // only one pointer bit changes at a time, so a two-flop synchronizer can
  // safely settle any metastability before local flag logic consumes d_out.
  always @(posedge clk) begin
    if (!rst_n) begin
      q1 <= '0;
      d_out <= '0;
    end else begin
      q1 <= d_in;
      d_out <= q1;
    end
  end

endmodule

module wptr_handler #(
  parameter PTR_WIDTH = 6
) (
  input wclk, wrst_n, w_en,
  input [PTR_WIDTH:0] g_rptr_sync,
  output reg [PTR_WIDTH:0] b_wptr, g_wptr,
  output reg full,
  output reg half_full
);

  localparam DEPTH = 1 << PTR_WIDTH;

  wire [PTR_WIDTH:0] b_wptr_next;
  wire [PTR_WIDTH:0] g_wptr_next;
  wire [PTR_WIDTH:0] b_rptr_sync;
  wire [PTR_WIDTH:0] wptr_diff;
  wire wfull, whalf_full;

  // The registered `full` flag gates pointer motion.  `wfull` below predicts
  // whether the accepted write at the next edge will make the FIFO full.
  assign b_wptr_next = b_wptr + (w_en & !full);
  assign g_wptr_next = (b_wptr_next >> 1) ^ b_wptr_next;

  // Convert the synchronized read pointer from Gray back to binary in the write
  // domain so occupancy can be calculated with normal subtraction.
  generate
    genvar i;
    assign b_rptr_sync[PTR_WIDTH] = g_rptr_sync[PTR_WIDTH];
    for (i = PTR_WIDTH - 1; i >= 0; i = i - 1) begin : gen_binary_conversion
      assign b_rptr_sync[i] = b_rptr_sync[i+1] ^ g_rptr_sync[i];
    end
  endgenerate

  // Half-full must use the same next write pointer that is about to be
  // registered.  Using b_wptr here makes half_full assert one wclk late at the
  // exact DEPTH/2 threshold.
  assign wptr_diff = b_wptr_next - b_rptr_sync;
  assign whalf_full = (wptr_diff >= (DEPTH >> 1));

  // Full is the standard Gray-pointer wrap comparison: the next write pointer
  // equals the synchronized read pointer with the two MSBs inverted.
  assign wfull = (g_wptr_next == {~g_rptr_sync[PTR_WIDTH:PTR_WIDTH-1], g_rptr_sync[PTR_WIDTH-2:0]});

  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      b_wptr <= '0;
      g_wptr <= '0;
    end else begin
      b_wptr <= b_wptr_next;
      g_wptr <= g_wptr_next;
    end
  end

  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      half_full <= 1'b0;
    end else begin
      half_full <= whalf_full;
    end
  end

  always @(posedge wclk or negedge wrst_n) begin
    if (!wrst_n) begin
      full <= 1'b0;
    end else begin
      full <= wfull;
    end
  end

endmodule

module rptr_handler #(
  parameter PTR_WIDTH = 6
) (
  input rclk, rrst_n, r_en,
  input [PTR_WIDTH:0] g_wptr_sync,
  output reg [PTR_WIDTH:0] b_rptr, g_rptr,
  output reg empty,
  output reg half_empty
);

  localparam DEPTH = 1 << PTR_WIDTH;

  wire [PTR_WIDTH:0] b_rptr_next;
  wire [PTR_WIDTH:0] g_rptr_next;
  wire [PTR_WIDTH:0] b_wptr_sync;
  wire [PTR_WIDTH:0] rptr_diff;
  wire rempty, rhalf_empty;

  // The registered `empty` flag gates pointer motion.  `rempty` predicts
  // whether the accepted read at the next edge will make the FIFO empty.
  assign b_rptr_next = b_rptr + (r_en & !empty);
  assign g_rptr_next = (b_rptr_next >> 1) ^ b_rptr_next;

  // Convert the synchronized write pointer from Gray back to binary in the read
  // domain for local occupancy math.
  generate
    genvar i;
    assign b_wptr_sync[PTR_WIDTH] = g_wptr_sync[PTR_WIDTH];
    for (i = PTR_WIDTH - 1; i >= 0; i = i - 1) begin : gen_binary_conversion
      assign b_wptr_sync[i] = b_wptr_sync[i+1] ^ g_wptr_sync[i];
    end
  endgenerate

  // Half-empty must use the same next read pointer that is about to be
  // registered.  Using b_rptr here makes half_empty assert one rclk late when
  // the accepted read drops occupancy to DEPTH/2.
  assign rptr_diff = b_wptr_sync - b_rptr_next;
  assign rhalf_empty = (rptr_diff <= (DEPTH >> 1));

  // Empty asserts when the synchronized write pointer equals the next read
  // pointer, so the final accepted read raises empty immediately.
  assign rempty = (g_wptr_sync == g_rptr_next);

  always @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      b_rptr <= '0;
      g_rptr <= '0;
    end else begin
      b_rptr <= b_rptr_next;
      g_rptr <= g_rptr_next;
    end
  end

  always @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      half_empty <= 1'b1;
    end else begin
      half_empty <= rhalf_empty;
    end
  end

  always @(posedge rclk or negedge rrst_n) begin
    if (!rrst_n) begin
      empty <= 1'b1;
    end else begin
      empty <= rempty;
    end
  end

endmodule

module fifo_mem #(
  parameter DEPTH = 64,
  parameter DATA_WIDTH = 8,
  parameter PTR_WIDTH = 6
) (
  input wclk, w_en,
  input rclk, r_en,
  input [PTR_WIDTH:0] b_wptr, b_rptr,
  input [DATA_WIDTH-1:0] data_in,
  input full, empty,
  output wire [DATA_WIDTH-1:0] data_out
);

  reg [DATA_WIDTH-1:0] fifo [0:DEPTH-1];

  // Write side is synchronous to wclk and is protected by the registered full
  // flag from the write domain.
  always @(posedge wclk) begin
    if (w_en & !full) begin
      fifo[b_wptr[PTR_WIDTH-1:0]] <= data_in;
    end
  end

  // Read side is asynchronous in this standalone model: data_out always shows
  // the current read pointer location.  The testbenches therefore sample
  // data_out before the read edge that advances b_rptr.
  assign data_out = fifo[b_rptr[PTR_WIDTH-1:0]];

  // rclk/r_en/empty are part of the memory interface contract, even though this
  // behavioral asynchronous-read RAM does not need them internally.
endmodule
