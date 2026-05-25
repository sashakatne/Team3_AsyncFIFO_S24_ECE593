`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Main standalone self-checking test for async_fifo4.sv.
//
// This is intentionally not a UVM testbench.  It is a compact procedural
// regression for the Miscellaneous standalone FIFO: drive stable stimulus on the
// falling edge, let the DUT sample it on the rising edge, maintain a reference
// queue for accepted writes, and compare accepted reads against that queue.
//
// Because async_fifo4.sv models the RAM read port as asynchronous, `data_out`
// represents the current read pointer location before the read edge advances the
// pointer.  The read task samples `data_out` before the active read clock edge
// and performs the comparison after the DUT has accepted or rejected the read.
// -----------------------------------------------------------------------------

module top;

  localparam int DEPTH = 64;
  localparam int DATA_WIDTH = 8;
  localparam real WCLK_PERIOD = 12.5;
  localparam real RCLK_PERIOD = 20.0;

  wire [DATA_WIDTH-1:0] data_out;
  wire full;
  wire empty;
  wire half_full;
  wire half_empty;

  logic [DATA_WIDTH-1:0] data_in;
  logic w_en, wclk, wrst_n;
  logic r_en, rclk, rrst_n;

  logic [DATA_WIDTH-1:0] expected_q[$];
  int accepted_writes;
  int accepted_reads;
  int blocked_writes;
  int blocked_reads;
  int error_count;

  asynchronous_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) uut (
    .wclk(wclk),
    .wrst_n(wrst_n),
    .rclk(rclk),
    .rrst_n(rrst_n),
    .w_en(w_en),
    .r_en(r_en),
    .data_in(data_in),
    .data_out(data_out),
    .full(full),
    .empty(empty),
    .half_full(half_full),
    .half_empty(half_empty)
  );

  always #(WCLK_PERIOD / 2.0) wclk = ~wclk;
  always #(RCLK_PERIOD / 2.0) rclk = ~rclk;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end

  task automatic record_error(input string msg);
    error_count++;
    $error("%s", msg);
  endtask

  task automatic apply_reset();
    wclk = 1'b0;
    rclk = 1'b0;
    wrst_n = 1'b0;
    rrst_n = 1'b0;
    w_en = 1'b0;
    r_en = 1'b0;
    data_in = '0;
    accepted_writes = 0;
    accepted_reads = 0;
    blocked_writes = 0;
    blocked_reads = 0;
    error_count = 0;
    expected_q.delete();

    repeat (4) @(posedge wclk);
    wrst_n = 1'b1;
    repeat (4) @(posedge rclk);
    rrst_n = 1'b1;

    // Both domains need a few edges after reset release so synchronized pointer
    // values and registered flags are no longer in reset-only states.
    repeat (4) @(posedge wclk);
    repeat (4) @(posedge rclk);

    if (full !== 1'b0 || empty !== 1'b1 || half_full !== 1'b0 || half_empty !== 1'b1) begin
      record_error($sformatf("unexpected flags after reset: full=%0b empty=%0b half_full=%0b half_empty=%0b",
                             full, empty, half_full, half_empty));
    end
  endtask

  task automatic write_step(input logic [DATA_WIDTH-1:0] data, input bit request);
    bit pre_full;

    @(negedge wclk);
    w_en = request;
    data_in = data;
    pre_full = full;

    @(posedge wclk);
    #1;
    if (request && !pre_full) begin
      expected_q.push_back(data);
      accepted_writes++;
    end else if (request) begin
      blocked_writes++;
    end
    w_en = 1'b0;
  endtask

  task automatic read_step(input bit request);
    bit pre_empty;
    logic [DATA_WIDTH-1:0] sampled_data;
    logic [DATA_WIDTH-1:0] expected;

    @(negedge rclk);
    r_en = request;
    pre_empty = empty;
    sampled_data = data_out;

    @(posedge rclk);
    #1;
    if (request && !pre_empty) begin
      accepted_reads++;
      if (expected_q.size() == 0) begin
        record_error($sformatf("read accepted with empty expected queue, sampled_data=%0h", sampled_data));
      end else begin
        expected = expected_q.pop_front();
        if (sampled_data !== expected) begin
          record_error($sformatf("data mismatch at read %0d: expected=%0h actual=%0h",
                                 accepted_reads, expected, sampled_data));
        end
      end
    end else if (request) begin
      blocked_reads++;
    end
    r_en = 1'b0;
  endtask

  task automatic wait_for_read_visibility();
    // The write pointer reaches the read domain through a two-flop synchronizer.
    // Waiting for empty to drop proves the read side can see at least one entry.
    wait (empty === 1'b0);
    repeat (2) @(posedge rclk);
  endtask

  task automatic finish_with_summary();
    $display("[SUMMARY fifo4_main] accepted_writes=%0d accepted_reads=%0d blocked_writes=%0d blocked_reads=%0d residual_q=%0d errors=%0d",
             accepted_writes, accepted_reads, blocked_writes, blocked_reads, expected_q.size(), error_count);

    if (error_count == 0 && expected_q.size() == 0 && accepted_writes == accepted_reads &&
        accepted_writes > DEPTH && blocked_writes > 0 && blocked_reads > 0) begin
      $display("*** PASSED ***");
      $finish;
    end

    $display("*** FAILED ***");
    $fatal(1, "async_fifo4 standalone self-check failed");
  endtask

  initial begin
    apply_reset();

    // Fill past full.  The first DEPTH writes should be accepted and the extra
    // requests should be rejected by the registered write-domain full flag.
    for (int i = 0; i < DEPTH + 4; i++) begin
      write_step(DATA_WIDTH'(8'h40 + i), 1'b1);
    end
    if (accepted_writes != DEPTH || full !== 1'b1) begin
      record_error($sformatf("full-fill phase failed: writes=%0d full=%0b", accepted_writes, full));
    end

    wait_for_read_visibility();

    // Drain part of the FIFO, leaving room for another write burst.  This checks
    // pointer wrap pressure without requiring concurrent testbench threads.
    for (int i = 0; i < DEPTH / 2; i++) begin
      read_step(1'b1);
    end

    // Give the write domain enough time to see the moved read pointer, then
    // write another half-depth of data.  These writes should wrap the RAM index.
    repeat (6) @(posedge wclk);
    for (int i = 0; i < DEPTH / 2; i++) begin
      write_step(DATA_WIDTH'(8'ha0 + i), 1'b1);
    end

    wait_for_read_visibility();

    // Drain every queued item, then prove one extra read is rejected.
    for (int i = 0; i < (DEPTH + 8) && expected_q.size() > 0; i++) begin
      read_step(1'b1);
    end
    wait (empty === 1'b1);
    read_step(1'b1);

    finish_with_summary();
  end

endmodule
