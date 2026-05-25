`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Directed flag-threshold waveform test for async_fifo4.sv.
//
// This bench is the farm-backed debug case for the Miscellaneous standalone
// FIFO.  It intentionally drives the two exact boundary cases users care about:
// full-side fill (half_full at 32 entries, full at 64 entries) and read-side
// drain (half_empty at 32 entries, empty at 0 entries).
//
// Signal aliases `wen`, `ren`, `wptr`, and `rptr` are present only to make the
// generated VCD and rendered waveform easy to inspect.  The renderer plots both
// clocks with red rising-edge markers, decimal pointer locations, write/read
// enables, and all four flags.
// -----------------------------------------------------------------------------

module flag_threshold_tb;

  localparam int DATA_WIDTH = 8;
  localparam int DEPTH = 64;
  localparam int PTR_WIDTH = $clog2(DEPTH);
  localparam real WCLK_PERIOD = 12.5;
  localparam real RCLK_PERIOD = 20.0;

  logic wclk;
  logic rclk;
  logic wrst_n;
  logic rrst_n;
  logic w_en;
  logic r_en;
  logic [DATA_WIDTH-1:0] data_in;
  wire [DATA_WIDTH-1:0] data_out;
  wire full;
  wire empty;
  wire half_full;
  wire half_empty;

  // Waveform-friendly aliases requested for debug readability.
  wire wen = w_en;
  wire ren = r_en;
  wire [PTR_WIDTH:0] wptr = DUT.b_wptr;
  wire [PTR_WIDTH:0] rptr = DUT.b_rptr;

  int accepted_writes;
  int accepted_reads;
  int model_occ;
  int error_count;
  bit half_full_lag_seen;
  bit half_empty_lag_seen;
  bit full_ok_seen;
  bit overflow_blocked_seen;
  bit empty_ok_seen;

  asynchronous_fifo #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) DUT (
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
    $dumpfile("flag_threshold.vcd");
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
    half_full_lag_seen = 1'b0;
    half_empty_lag_seen = 1'b0;
    full_ok_seen = 1'b0;
    overflow_blocked_seen = 1'b0;
    empty_ok_seen = 1'b0;

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

  task automatic idle_wclk(input int cycles);
    @(negedge wclk);
    w_en = 1'b0;
    repeat (cycles) begin
      @(posedge wclk);
      #1;
    end
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

  task automatic idle_rclk(input int cycles);
    @(negedge rclk);
    r_en = 1'b0;
    repeat (cycles) begin
      @(posedge rclk);
      #1;
    end
  endtask

  task automatic finish_with_summary();
    $display("[SUMMARY] half_full_lag_seen=%0b half_empty_lag_seen=%0b full_ok_seen=%0b overflow_blocked_seen=%0b empty_ok_seen=%0b errors=%0d",
             half_full_lag_seen, half_empty_lag_seen, full_ok_seen, overflow_blocked_seen, empty_ok_seen, error_count);

    if (error_count == 0 && !half_full_lag_seen && !half_empty_lag_seen &&
        full_ok_seen && overflow_blocked_seen && empty_ok_seen) begin
      $display("*** PASSED ***");
      $finish;
    end

    $display("*** FAILED ***");
    $fatal(1, "flag-threshold waveform test failed");
  endtask

  initial begin
    apply_reset();

    $display("[CASE half_full] Fill to exactly DEPTH/2=%0d entries", DEPTH / 2);
    for (int i = 0; i < DEPTH / 2; i++) begin
      write_cycle(DATA_WIDTH'(i));
    end

    if (model_occ != DEPTH / 2) begin
      record_error($sformatf("[MODEL] expected occupancy %0d, got %0d", DEPTH / 2, model_occ));
    end
    if (half_full !== 1'b1) begin
      half_full_lag_seen = 1'b1;
      record_error($sformatf("[BUG half_full_late] occ=%0d wptr=%0d rptr=%0d half_full=%0b expected=1",
                             model_occ, wptr, rptr, half_full));
    end else begin
      $display("[OK half_full_immediate] occ=%0d wptr=%0d rptr=%0d half_full=1",
               model_occ, wptr, rptr);
    end

    idle_wclk(1);
    $display("[OBS half_full_after_idle] occ=%0d wptr=%0d rptr=%0d half_full=%0b",
             model_occ, wptr, rptr, half_full);

    $display("[CASE full] Continue filling to DEPTH=%0d entries", DEPTH);
    for (int i = DEPTH / 2; i < DEPTH; i++) begin
      write_cycle(DATA_WIDTH'(i));
    end

    if (model_occ == DEPTH && full === 1'b1) begin
      full_ok_seen = 1'b1;
      $display("[OK full_immediate] occ=%0d accepted_writes=%0d wptr=%0d rptr=%0d full=%0b",
               model_occ, accepted_writes, wptr, rptr, full);
    end else begin
      record_error($sformatf("[BUG full] occ=%0d accepted_writes=%0d wptr=%0d rptr=%0d full=%0b expected=1",
                             model_occ, accepted_writes, wptr, rptr, full));
    end

    write_cycle(8'hff);
    if (model_occ == DEPTH && accepted_writes == DEPTH && full === 1'b1) begin
      overflow_blocked_seen = 1'b1;
      $display("[OK overflow_blocked] occ=%0d accepted_writes=%0d wptr=%0d rptr=%0d full=%0b",
               model_occ, accepted_writes, wptr, rptr, full);
    end else begin
      record_error($sformatf("[BUG overflow] occ=%0d accepted_writes=%0d wptr=%0d rptr=%0d full=%0b",
                             model_occ, accepted_writes, wptr, rptr, full));
    end
    idle_wclk(2);

    // Wait until the full write pointer has crossed into the read domain.  At
    // that point a full FIFO should not be considered half-empty.
    wait (empty === 1'b0);
    repeat (6) @(posedge rclk);
    #1;
    if (half_empty !== 1'b0) begin
      record_error($sformatf("[BUG half_empty_prefill] after full sync, half_empty=%0b expected=0", half_empty));
    end

    $display("[CASE half_empty] Drain from full down to exactly DEPTH/2=%0d entries", DEPTH / 2);
    for (int i = 0; i < DEPTH / 2; i++) begin
      read_cycle();
    end

    if (model_occ != DEPTH / 2) begin
      record_error($sformatf("[MODEL] expected occupancy %0d, got %0d", DEPTH / 2, model_occ));
    end
    if (half_empty !== 1'b1) begin
      half_empty_lag_seen = 1'b1;
      record_error($sformatf("[BUG half_empty_late] occ=%0d reads=%0d wptr=%0d rptr=%0d half_empty=%0b expected=1",
                             model_occ, accepted_reads, wptr, rptr, half_empty));
    end else begin
      $display("[OK half_empty_immediate] occ=%0d reads=%0d wptr=%0d rptr=%0d half_empty=1",
               model_occ, accepted_reads, wptr, rptr);
    end

    idle_rclk(1);
    $display("[OBS half_empty_after_idle] occ=%0d wptr=%0d rptr=%0d half_empty=%0b",
             model_occ, wptr, rptr, half_empty);

    $display("[CASE empty] Continue draining to zero entries");
    for (int i = DEPTH / 2; i < DEPTH; i++) begin
      read_cycle();
    end

    if (model_occ == 0 && empty === 1'b1) begin
      empty_ok_seen = 1'b1;
      $display("[OK empty_immediate] occ=%0d reads=%0d wptr=%0d rptr=%0d empty=%0b",
               model_occ, accepted_reads, wptr, rptr, empty);
    end else begin
      record_error($sformatf("[BUG empty] occ=%0d reads=%0d wptr=%0d rptr=%0d empty=%0b expected=1",
                             model_occ, accepted_reads, wptr, rptr, empty));
    end

    idle_rclk(2);
    finish_with_summary();
  end

endmodule
