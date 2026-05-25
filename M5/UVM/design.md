# M5/UVM Review (Post-Fix)

## Scope

This directory is the M5 UVM verification environment for the
asynchronous FIFO. The fix pass keeps the M5 UVM structure, restores a
clean default run, and adds farm-backed evidence for the randomized and
directed flag-threshold cases.

## Fixes Applied

### D-0: Default Build No Longer Injects Bugs

The original M5 `run.do` compiled `async_fifo.sv` with
`+define+INJECT_THE_BUG` enabled by default. That macro activated
multiple RTL defects at once. The fixed default build compiles the DUT
without any bug define and leaves explicit commented bug-injection lines:

```systemverilog
// +define+WDATA_CORRUPTION_BUG
// +define+SYNC_BUG
// +define+RPTR_BUG
// +define+WPTR_FULLFLAG_BUG
```

### D-1: Synchronizer Destination Domains

The original M5 RTL clocked both pointer synchronizers in the source
domain. The fixed RTL samples each pointer in its destination domain:

```systemverilog
synchronizer_r2w_inst (.clk(wclk), .rst_n(wrst), ...);
synchronizer_w2r_inst (.clk(rclk), .rst_n(rrst), ...);
```

### D-2: Half Flags Use Next Occupancy

`wHalfFull` and `rHalfEmpty` used current local pointers, making them
one destination-clock edge late at the 32-entry threshold. They now use
the same next-pointer timing model as `wFull` and `rEmpty`:

```systemverilog
assign wptr_diff = b_wptr_next - b_rptr_sync;
assign rptr_diff = b_wptr_sync - b_rptr_next;
```

### T-1: Race-Free Driver/Monitor Timing

The drivers now drive at `negedge`, before the DUT samples at the next
positive edge. The monitors sample request and pre-edge flag state after
the preceding `negedge`, then publish only accepted transfers after the
active edge.

### T-2: Scoreboard Summary Is Self-Checking

The scoreboard now counts accepted writes, accepted reads, residual
expected queue entries, and mismatches. Unknown read/write data and empty
expected-queue reads increment the error counter and raise `uvm_error`.

### R-1: Reproducible Farm Run

`run.do` now guards `vdel`, keeps DUT-only code coverage
instrumentation, saves `async_fifo.ucdb`, and emits text coverage
reports. The periodic reset loop in `tb_top` is gated under
`RESET_SEQUENCE` so the default random run does not reset the DUT while
the scoreboard queue contains expected data.

## Farm Evidence

Baseline RED run:

- Remote dir: `~/claude-runs/2026-05-25T22-43-35Z_m5-uvm-baseline-red`
- Start UTC: `2026-05-25T22-43-35Z`
- End UTC: `2026-05-25T22-43-39Z`
- Command: `timeout 180s vsim -c -do 'do run.do; quit -f'`
- Result: fresh farm run stopped at `vdel -all` because `work/` did
  not exist.

Full fixed M5 UVM run:

- Remote dir: `~/claude-runs/2026-05-25T22-48-44Z_m5-uvm-green-final`
- Start UTC: `2026-05-25T22-48-44Z`
- End UTC: `2026-05-25T22-49-20Z`
- Command: `timeout 240s vsim -c -do 'do run.do; quit -f'`

Results:

```text
Writes observed       : 1266
Reads  observed       : 1266
Residual expected_q   : 0
Mismatches / errors   : 0
Verdict: *** PASSED ***
UVM_WARNING : 0
UVM_ERROR   : 0
UVM_FATAL   : 0
TOTAL COVERGROUP COVERAGE: 100.00%
Total Coverage By Instance (filtered view): 100.00%
```

Directed flag-threshold run:

- Remote dir: `~/claude-runs/2026-05-25T22-47-25Z_m5-flag-threshold-green`
- Start UTC: `2026-05-25T22-47-25Z`
- End UTC: `2026-05-25T22-47-39Z`
- Command: `timeout 120s vsim -c -do 'do run_flags.do; quit -f'`

Results:

```text
[OK half_full_immediate] occ=32 wHalfFull=1
[OK full_immediate] occ=64 after write #64, wFull=1
[OK overflow_blocked] full write attempt rejected: occ=64 accepted_writes=64 wFull=1
[OK half_empty_immediate] occ=32 rHalfEmpty=1
[OK empty_immediate] occ=0 after read #64, rEmpty=1
[SUMMARY] half_full_lag_seen=0 half_empty_lag_seen=0 full_ok_seen=1 overflow_blocked_seen=1 empty_ok_seen=1
```

## Artifacts

- `transcript_farm.txt`: full fixed M5 UVM farm transcript.
- `waveform_samples.csv`, `waveforms.svg`, `waveforms.png`: parsed
  full-run DUT signal waveform artifacts from `dump.vcd`.
- `flag_threshold_transcript_farm.txt`: directed flag-threshold farm
  transcript.
- `flag_debug_waveforms.svg/.png`: directed run with `wclk`, `rclk`,
  decimal `wptr`/`rptr`, `wen`, `ren`, and all four flags.
- `flag_debug_write_thresholds.svg/.png`: write-side half/full zoom.
- `flag_debug_read_thresholds.svg/.png`: read-side half/empty zoom.

Raw `dump.vcd`, `flag_threshold.vcd`, and `async_fifo.ucdb` are
gitignored simulator artifacts.
