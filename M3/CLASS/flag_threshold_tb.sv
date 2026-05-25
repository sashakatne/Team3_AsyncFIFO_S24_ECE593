`timescale 1ns/1ps

module flag_threshold_tb;

  localparam DATA_SIZE = 8;
  localparam ADDR_SIZE = 6;
  localparam DEPTH = 1 << ADDR_SIZE;
  localparam WCLK_PERIOD = 12.5;
  localparam RCLK_PERIOD = 20.0;

  bit wclk;
  bit rclk;
  bit wrst;
  bit rrst;
  bit winc;
  bit rinc;
  logic [DATA_SIZE-1:0] wData;
  logic [DATA_SIZE-1:0] rData;
  logic wFull;
  logic rEmpty;
  logic wHalfFull;
  logic rHalfEmpty;

  int accepted_writes;
  int accepted_reads;
  int model_occ;
  bit half_full_lag_seen;
  bit half_empty_lag_seen;
  bit full_ok_seen;
  bit overflow_blocked_seen;
  bit empty_ok_seen;

  asynchronous_fifo #(
    .DATA_SIZE(DATA_SIZE),
    .ADDR_SIZE(ADDR_SIZE)
  ) DUT (
    .winc(winc),
    .wclk(wclk),
    .wrst(wrst),
    .rinc(rinc),
    .rclk(rclk),
    .rrst(rrst),
    .wData(wData),
    .rData(rData),
    .wFull(wFull),
    .rEmpty(rEmpty),
    .wHalfFull(wHalfFull),
    .rHalfEmpty(rHalfEmpty)
  );

  always #(WCLK_PERIOD / 2.0) wclk = ~wclk;
  always #(RCLK_PERIOD / 2.0) rclk = ~rclk;

  initial begin
    $dumpfile("flag_threshold.vcd");
    $dumpvars;
  end

  task automatic apply_reset();
    wclk = 0;
    rclk = 0;
    wrst = 0;
    rrst = 0;
    winc = 0;
    rinc = 0;
    wData = '0;
    accepted_writes = 0;
    accepted_reads = 0;
    model_occ = 0;
    repeat (4) @(posedge wclk);
    wrst = 1;
    repeat (4) @(posedge rclk);
    rrst = 1;
    repeat (4) @(posedge wclk);
    repeat (4) @(posedge rclk);
  endtask

  task automatic write_cycle(input logic [DATA_SIZE-1:0] data);
    bit pre_full;
    @(negedge wclk);
    winc = 1;
    wData = data;
    pre_full = wFull;
    @(posedge wclk);
    #1;
    if (!pre_full) begin
      accepted_writes++;
      model_occ++;
    end
  endtask

  task automatic idle_wclk(input int cycles);
    @(negedge wclk);
    winc = 0;
    repeat (cycles) begin
      @(posedge wclk);
      #1;
    end
  endtask

  task automatic read_cycle();
    bit pre_empty;
    @(negedge rclk);
    rinc = 1;
    pre_empty = rEmpty;
    @(posedge rclk);
    #1;
    if (!pre_empty) begin
      accepted_reads++;
      model_occ--;
    end
  endtask

  task automatic idle_rclk(input int cycles);
    @(negedge rclk);
    rinc = 0;
    repeat (cycles) begin
      @(posedge rclk);
      #1;
    end
  endtask

  initial begin
    apply_reset();

    $display("[CASE half_full] Fill to exactly DEPTH/2=%0d entries", DEPTH / 2);
    for (int i = 0; i < (DEPTH / 2); i++) begin
      write_cycle(i[DATA_SIZE-1:0]);
    end

    if (model_occ != (DEPTH / 2)) begin
      $error("[MODEL] expected occupancy %0d, got %0d", DEPTH / 2, model_occ);
    end

    if (wHalfFull !== 1'b1) begin
      half_full_lag_seen = 1;
      $display("[BUG half_full_late] occ=%0d immediately after write #%0d, wHalfFull=%0b expected=1",
               model_occ, accepted_writes, wHalfFull);
    end else begin
      $display("[OK half_full_immediate] occ=%0d wHalfFull=1", model_occ);
    end

    idle_wclk(1);
    $display("[OBS half_full_after_idle] occ=%0d wHalfFull=%0b", model_occ, wHalfFull);

    $display("[CASE full] Continue filling to DEPTH=%0d entries", DEPTH);
    for (int i = DEPTH / 2; i < DEPTH; i++) begin
      write_cycle(i[DATA_SIZE-1:0]);
    end

    if (model_occ == DEPTH && wFull === 1'b1) begin
      full_ok_seen = 1;
      $display("[OK full_immediate] occ=%0d after write #%0d, wFull=%0b", model_occ, accepted_writes, wFull);
    end else begin
      $error("[BUG full] occ=%0d writes=%0d wFull=%0b expected=1", model_occ, accepted_writes, wFull);
    end

    write_cycle(8'hff);
    if (model_occ == DEPTH && accepted_writes == DEPTH && wFull === 1'b1) begin
      overflow_blocked_seen = 1;
      $display("[OK overflow_blocked] full write attempt rejected: occ=%0d accepted_writes=%0d wFull=%0b",
               model_occ, accepted_writes, wFull);
    end else begin
      $error("[BUG overflow] occ=%0d accepted_writes=%0d wFull=%0b", model_occ, accepted_writes, wFull);
    end
    idle_wclk(2);

    wait (rEmpty === 1'b0);
    repeat (4) @(posedge rclk);
    #1;
    if (rHalfEmpty !== 1'b0) begin
      $error("[BUG half_empty_prefill] after full sync, rHalfEmpty=%0b expected=0", rHalfEmpty);
    end

    $display("[CASE half_empty] Drain from full down to exactly DEPTH/2=%0d entries", DEPTH / 2);
    for (int i = 0; i < (DEPTH / 2); i++) begin
      read_cycle();
    end

    if (model_occ != (DEPTH / 2)) begin
      $error("[MODEL] expected occupancy %0d, got %0d", DEPTH / 2, model_occ);
    end

    if (rHalfEmpty !== 1'b1) begin
      half_empty_lag_seen = 1;
      $display("[BUG half_empty_late] occ=%0d immediately after read #%0d, rHalfEmpty=%0b expected=1",
               model_occ, accepted_reads, rHalfEmpty);
    end else begin
      $display("[OK half_empty_immediate] occ=%0d rHalfEmpty=1", model_occ);
    end

    idle_rclk(1);
    $display("[OBS half_empty_after_idle] occ=%0d rHalfEmpty=%0b", model_occ, rHalfEmpty);

    $display("[CASE empty] Continue draining to 0 entries");
    for (int i = DEPTH / 2; i < DEPTH; i++) begin
      read_cycle();
    end

    if (model_occ == 0 && rEmpty === 1'b1) begin
      empty_ok_seen = 1;
      $display("[OK empty_immediate] occ=%0d after read #%0d, rEmpty=%0b", model_occ, accepted_reads, rEmpty);
    end else begin
      $error("[BUG empty] occ=%0d reads=%0d rEmpty=%0b expected=1", model_occ, accepted_reads, rEmpty);
    end

    idle_rclk(2);
    $display("[SUMMARY] half_full_lag_seen=%0b half_empty_lag_seen=%0b full_ok_seen=%0b overflow_blocked_seen=%0b empty_ok_seen=%0b",
             half_full_lag_seen, half_empty_lag_seen, full_ok_seen, overflow_blocked_seen, empty_ok_seen);
    $finish;
  end

endmodule
