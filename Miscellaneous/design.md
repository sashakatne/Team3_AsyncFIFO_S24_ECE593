# Miscellaneous Standalone FIFO Review

## Scope

`Miscellaneous/` contains standalone FIFO experiments that compile without the
UVM milestone infrastructure:

- `async_fifo2.sv`: legacy async-comparator FIFO reference.
- `async_fifo4.sv`: synchronizer-based async FIFO reference.
- `async_fifo*_tb.sv` and `flag_threshold_tb.sv`: procedural self-checking
  benches for data ordering and flag timing.

## Fixes Applied

### D-1: fifo2 Warning Cleanup

`async_fifo2.sv` previously relied on implicit nets for `aempty_n` and
`afull_n`, which produced Questa lint warnings.  The nets are now declared
explicitly.

### D-2: fifo2 Full-Gated RAM Write

The legacy fifo2 top held the write pointer when `wfull` was asserted, but the
RAM write enable was still raw `winc`.  Over-full write attempts could therefore
overwrite the held write-address location.  The RAM enable is now:

```systemverilog
wire write_accept = winc & !wfull;
```

The new fifo2 self-check caught the original corruption before the fix.

### D-3: async_fifo4 Half Flags Use Next Occupancy

`half_full` and `half_empty` used current local pointers, making the flags one
destination-clock late at the exact half threshold.  They now use the same
next-pointer timing convention as full/empty:

```systemverilog
assign wptr_diff = b_wptr_next - b_rptr_sync;
assign rptr_diff = b_wptr_sync - b_rptr_next;
```

### T-1: Race-Free Standalone Benches

The standalone benches now drive enables/data on the falling clock edge and let
the DUT sample on the next rising edge.  Reads sample asynchronous `data_out`
before the read pointer advances, then compare against a reference queue after
the edge confirms acceptance.

### T-2: Exact Flag-Threshold Case

`flag_threshold_tb.sv` drives the exact flag cases:

- Fill to 32 entries: `half_full` must assert immediately.
- Fill to 64 entries: `full` must assert immediately.
- Attempt overflow: write must be blocked.
- Drain to 32 entries: `half_empty` must assert immediately.
- Drain to 0 entries: `empty` must assert immediately.

## Farm Evidence

Standalone regression:

- Remote dir: `~/claude-runs/2026-05-25T23-21-44Z_misc-standalone-green-final2`
- Command sequence:
  - `timeout 240s vsim -c -do "do run_fifo2.do; quit -f"`
  - `timeout 240s vsim -c -do "do run.do; quit -f"`
  - `timeout 240s vsim -c -do "do run_flags_compat.do; quit -f"`
- Result: all compile/vopt/sim phases report `Errors: 0, Warnings: 0`.

Key summaries:

```text
[SUMMARY fifo2] accepted_writes=64 accepted_reads=64 blocked_writes=6 blocked_reads=1 residual_q=0 errors=0
[SUMMARY fifo4_main] accepted_writes=96 accepted_reads=96 blocked_writes=4 blocked_reads=1 residual_q=0 errors=0
[SUMMARY fifo4_flags] accepted_writes=64 accepted_reads=64 occ=0 full=0 empty=1 half_full=0 half_empty=1 errors=0
```

Directed flag-threshold waveform run:

- Remote dir: `~/claude-runs/2026-05-25T23-22-25Z_misc-flag-threshold-green-final`
- Command: `timeout 240s vsim -c -do 'do run_flags.do; quit -f'`
- Result: compile, vopt, and sim all report `Errors: 0, Warnings: 0`.

Key flag evidence:

```text
[OK half_full_immediate] occ=32 wptr=32 rptr=0 half_full=1
[OK full_immediate] occ=64 accepted_writes=64 wptr=64 rptr=0 full=1
[OK overflow_blocked] occ=64 accepted_writes=64 wptr=64 rptr=0 full=1
[OK half_empty_immediate] occ=32 reads=32 wptr=64 rptr=32 half_empty=1
[OK empty_immediate] occ=0 reads=64 wptr=64 rptr=64 empty=1
[SUMMARY] half_full_lag_seen=0 half_empty_lag_seen=0 full_ok_seen=1 overflow_blocked_seen=1 empty_ok_seen=1 errors=0
```

## Artifacts

- `transcript_farm.txt`: full standalone farm regression transcript.
- `flag_threshold_transcript_farm.txt`: focused directed flag farm transcript.
- `waveform_samples.csv`, `waveforms.svg`, `waveforms.png`: main async_fifo4
  farm waveform render.
- `flag_debug_samples.csv`, `flag_debug_waveforms.svg/.png`: requested debug
  view with clocks, decimal pointers, `wen`, `ren`, and all four flags.
- `flag_debug_write_thresholds.svg/.png`: write-side half/full zoom.
- `flag_debug_read_thresholds.svg/.png`: read-side half-empty/empty zoom.

Raw `dump.vcd`, `flag_compat.vcd`, `flag_threshold.vcd`, `work/`, and simulator
database outputs are intentionally gitignored.
