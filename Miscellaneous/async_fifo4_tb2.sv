`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Compatibility standalone flag-threshold test for async_fifo4.sv.
//
// This file keeps the original `async_fifo4_tb2.sv` entry point but upgrades it
// into an exact self-check for half/full/empty flag timing.  It is intentionally
// directed:
//   1. Fill to DEPTH/2 and require half_full immediately.
//   2. Fill to DEPTH and require full immediately.
//   3. Attempt one overflow write and require it to be blocked.
//   4. Drain to DEPTH/2 and require half_empty immediately.
//   5. Drain to zero and require empty immediately.
//
// The dedicated `flag_threshold_tb.sv` contains the same style of test with
// signal aliases arranged for waveform rendering.  This compatibility file is
// useful for the all-standalone `run.do` regression.
// -----------------------------------------------------------------------------

module top;

  localparam int DATA_WIDTH = 8;
  localparam int DEPTH = 64;
  localparam real WCLK_PERIOD = 12.5;
  localparam real RCLK_PERIOD = 20.0;

  wire [DATA_WIDTH-1:0] data_out;
  wire full, empty;
  wire half_full, half_empty;

  logic [DATA_WIDTH-1:0] data_in;
  logic w_en, wclk, wrst_n;
  logic r_en, rclk, rrst_n;

  int accepted_writes;
  int accepted_reads;
  int model_occ;
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
    $dumpfile("flag_compat.vcd");
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
    model_occ = 0;
    error_count = 0;

    repeat (4) @(posedge wclk);
    wrst_n = 1'b1;
    repeat (4) @(posedge rclk);
    rrst_n = 1'b1;
    repeat (4) @(posedge wclk);
    repeat (4) @(posedge rclk);
  endtask

  task automatic write_cycle(input logic [DATA_WIDTH-1:0] data);
    bit pre_full;

    @(negedge wclk);
    w_en = 1'b1;
    data_in = data;
    pre_full = full;

    @(posedge wclk);
    #1;
    if (!pre_full) begin
      accepted_writes++;
      model_occ++;
    end
    w_en = 1'b0;
  endtask

  task automatic read_cycle();
    bit pre_empty;

    @(negedge rclk);
    r_en = 1'b1;
    pre_empty = empty;

    @(posedge rclk);
    #1;
    if (!pre_empty) begin
      accepted_reads++;
      model_occ--;
    end
    r_en = 1'b0;
  endtask

  task automatic finish_with_summary();
    $display("[SUMMARY fifo4_flags] accepted_writes=%0d accepted_reads=%0d occ=%0d full=%0b empty=%0b half_full=%0b half_empty=%0b errors=%0d",
             accepted_writes, accepted_reads, model_occ, full, empty, half_full, half_empty, error_count);

    if (error_count == 0 && accepted_writes == DEPTH && accepted_reads == DEPTH && model_occ == 0 &&
        full === 1'b0 && empty === 1'b1 && half_full === 1'b0 && half_empty === 1'b1) begin
      $display("*** PASSED ***");
      $finish;
    end

    $display("*** FAILED ***");
    $fatal(1, "async_fifo4 flag threshold compatibility test failed");
  endtask

  initial begin
    apply_reset();

    $display("[CASE half_full] Fill to exactly DEPTH/2=%0d", DEPTH / 2);
    for (int i = 0; i < DEPTH / 2; i++) begin
      write_cycle(DATA_WIDTH'(i));
    end
    if (model_occ == DEPTH / 2 && half_full === 1'b1) begin
      $display("[OK half_full_immediate] occ=%0d half_full=%0b", model_occ, half_full);
    end else begin
      record_error($sformatf("[BUG half_full_late] occ=%0d half_full=%0b expected=1", model_occ, half_full));
    end

    $display("[CASE full] Continue filling to DEPTH=%0d", DEPTH);
    for (int i = DEPTH / 2; i < DEPTH; i++) begin
      write_cycle(DATA_WIDTH'(i));
    end
    if (model_occ == DEPTH && full === 1'b1) begin
      $display("[OK full_immediate] occ=%0d full=%0b", model_occ, full);
    end else begin
      record_error($sformatf("[BUG full] occ=%0d full=%0b expected=1", model_occ, full));
    end

    write_cycle(8'hff);
    if (model_occ == DEPTH && accepted_writes == DEPTH && full === 1'b1) begin
      $display("[OK overflow_blocked] occ=%0d accepted_writes=%0d full=%0b", model_occ, accepted_writes, full);
    end else begin
      record_error($sformatf("[BUG overflow] occ=%0d accepted_writes=%0d full=%0b",
                             model_occ, accepted_writes, full));
    end

    wait (empty === 1'b0);
    repeat (6) @(posedge rclk);
    #1;
    if (half_empty !== 1'b0) begin
      record_error($sformatf("[BUG half_empty_prefill] half_empty=%0b expected=0 after full sync", half_empty));
    end

    $display("[CASE half_empty] Drain to exactly DEPTH/2=%0d", DEPTH / 2);
    for (int i = 0; i < DEPTH / 2; i++) begin
      read_cycle();
    end
    if (model_occ == DEPTH / 2 && half_empty === 1'b1) begin
      $display("[OK half_empty_immediate] occ=%0d half_empty=%0b", model_occ, half_empty);
    end else begin
      record_error($sformatf("[BUG half_empty_late] occ=%0d half_empty=%0b expected=1", model_occ, half_empty));
    end

    $display("[CASE empty] Continue draining to zero");
    for (int i = DEPTH / 2; i < DEPTH; i++) begin
      read_cycle();
    end
    if (model_occ == 0 && empty === 1'b1) begin
      $display("[OK empty_immediate] occ=%0d empty=%0b", model_occ, empty);
    end else begin
      record_error($sformatf("[BUG empty] occ=%0d empty=%0b expected=1", model_occ, empty));
    end

    repeat (2) @(posedge wclk);
    repeat (2) @(posedge rclk);
    finish_with_summary();
  end

endmodule
