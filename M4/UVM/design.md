# M4/UVM Review (Post-Fix)

## Scope

This directory is the M4 UVM verification environment for the
asynchronous FIFO. The fix pass keeps the M4 structure, but makes the
DUT and testbench self-checking enough to produce reliable farm
evidence.

## Fixes Applied

### D-1: Synchronizer Destination Domains

The original M4 RTL clocked both pointer synchronizers in the source
domain:

```systemverilog
synchronizer_r2w_inst (.clk(rclk), .rst_n(rrst), ...);
synchronizer_w2r_inst (.clk(wclk), .rst_n(wrst), ...);
```

The fixed RTL places each two-flop synchronizer in the destination
domain:

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

The drivers now drive on `negedge` so stimulus is stable before the DUT
samples on the next positive edge. The monitors sample request and
pre-edge flag state after the preceding `negedge`, then publish the
accepted transfer after the active edge.

That matters for writes that fill the FIFO: sampling `wFull` after the
posedge sees the newly asserted full flag and can incorrectly drop the
accepted write from the scoreboard model.

### T-2: Real Scoreboard Compare

The original scoreboard compared `txr.rData` against itself, so any
read data value passed. The fixed scoreboard pops the expected write
data from a queue, compares it against the DUT read data, raises
`uvm_error` on mismatch, and prints a final PASS/FAIL summary.

### C-1: Reproducible Run And Coverage Flow

`run.do` now guards `vdel`, compiles with `-source -lint`, instruments
code coverage only on `asynchronous_fifo(rtl)`, saves `async_fifo.ucdb`,
and emits text coverage reports. The old broad `-codeAll` flow and
HTML-only report were removed.

The M4 covergroup now targets reachable FIFO behavior: accepted and
blocked accesses, flag transitions, reset release, and coarse data
ranges.

## Farm Evidence

Baseline RED run:

- Remote dir: `~/claude-runs/2026-05-25T22-11-34Z_m4-uvm-baseline-red`
- Command: `timeout 180s vsim -c -do 'do run.do; quit -f'`
- Result: fresh farm run stopped at `vdel -all` because `work/` did
  not exist.

Full fixed M4 UVM run:

- Remote dir: `~/claude-runs/2026-05-25T22-36-16Z_m4-uvm-green-final2`
- Start UTC: `2026-05-25T22-36-37Z`
- End UTC: `2026-05-25T22-36-57Z`
- Command: `vsim -c -do 'do run.do; quit -f'`

Results:

```text
Writes observed       : 1267
Reads  observed       : 1267
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

- Remote dir: `~/claude-runs/2026-05-25T22-26-45Z_m4-flag-threshold-green`
- Start UTC: `2026-05-25T22-26-47Z`
- End UTC: `2026-05-25T22-26-51Z`
- Command: `vsim -c -do 'do run_flags.do; quit -f'`

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

- `transcript_farm.txt`: full fixed M4 UVM farm transcript.
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
