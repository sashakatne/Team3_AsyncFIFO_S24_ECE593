# Post_M5/UVM Review (Post-Fix)

## Scope

This directory is the final Post_M5 UVM verification environment for
the asynchronous FIFO. The fix pass keeps the Post_M5 structure and
default reset-sequence flow, but makes the RTL and scoreboard robust
enough to support real farm evidence.

## Fixes Applied

### D-1: Synchronizer Reset Domains

The original Post_M5 RTL clocked each pointer synchronizer in the
destination domain, but reset it with the opposite/source reset. The
fixed RTL resets each synchronizer in the same destination domain as
its sampling clock:

```systemverilog
sync_w2r (.clk(rclk), .rst_n(rrst), ...);
sync_r2w (.clk(wclk), .rst_n(wrst), ...);
```

### D-2: Half Flags Use Pointer-Domain Occupancy

`wHalfFull` and `rHalfEmpty` were derived from a `fifo_count` register
written by both `wclk` and `rclk`. That was not a sound CDC model and
made the half flags depend on a dual-clock counter in the memory block.

The fixed design computes half flags in the pointer handlers from the
local next pointer and the synchronized remote pointer:

```systemverilog
assign wptr_diff = binary_wptr_next - binary_rptr_sync;
assign rptr_diff = binary_wptr_sync - binary_rptr_next;
```

### T-1: Race-Free Driver/Monitor Timing

The drivers now drive at `negedge`, before the DUT samples at the next
positive edge. The monitors sample request and pre-edge flag state after
the preceding `negedge`, then publish only accepted transfers after the
active edge.

### T-2: Reset-Aware Scoreboard

Post_M5 keeps `RESET_SEQUENCE` enabled in the default run. The
scoreboard now monitors `wrst`/`rrst`, flushes pending expected writes
on reset, counts reset flushes, and prints a final PASS/FAIL summary.
Unknown data, empty expected-queue reads, and data mismatches increment
the scoreboard error counter and raise `uvm_error`.

### R-1: Reproducible Farm Run

`run.do` now guards `vdel` so fresh farm directories do not fail before
compile. The run keeps DUT-only code coverage instrumentation and saves
`async_fifo.ucdb`. `tb_top` also dumps `dump.vcd` for reproducible
waveform artifacts.

## Farm Evidence

Baseline RED run:

- Remote dir: `~/claude-runs/2026-05-25T22-59-37Z_post-m5-uvm-baseline-red`
- Start UTC: `2026-05-25T22-59-37Z`
- End UTC: `2026-05-25T22-59-42Z`
- Command: `timeout 180s vsim -c -do 'do run.do; quit -f'`
- Result: fresh farm run stopped at `vdel -all` because `work/` did
  not exist.

Full fixed Post_M5 UVM run:

- Remote dir: `~/claude-runs/2026-05-25T23-03-19Z_post-m5-uvm-green-attempt2`
- Start UTC: `2026-05-25T23-03-19Z`
- End UTC: `2026-05-25T23-03-42Z`
- Command: `timeout 240s vsim -c -do 'do run.do; quit -f'`

Results:

```text
Writes observed       : 659
Reads  observed       : 596
Reset flushes         : 2
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

- Remote dir: `~/claude-runs/2026-05-25T23-04-42Z_post-m5-flag-threshold-green`
- Start UTC: `2026-05-25T23-04-42Z`
- End UTC: `2026-05-25T23-05-27Z`
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

- `transcript_farm.txt`: full fixed Post_M5 UVM farm transcript.
- `waveform_samples.csv`, `waveforms.svg`, `waveforms.png`: parsed
  full-run DUT signal waveform artifacts from `dump.vcd`.
- `flag_threshold_transcript_farm.txt`: directed flag-threshold farm
  transcript.
- `flag_debug_waveforms.svg/.png`: directed run with `wclk`, `rclk`,
  decimal binary `wptr`/`rptr`, `wen`, `ren`, and all four flags.
- `flag_debug_write_thresholds.svg/.png`: write-side half/full zoom.
- `flag_debug_read_thresholds.svg/.png`: read-side half/empty zoom.

Raw `dump.vcd`, `flag_threshold.vcd`, and `async_fifo.ucdb` are
gitignored simulator artifacts.
