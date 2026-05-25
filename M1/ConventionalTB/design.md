# M1/ConventionalTB review (Style #2 async FIFO + queue scoreboard, POST-FIX)

## What lives here

This directory contains the team's first **engineered** async FIFO -- the
RTL was already a Cliff Cummings *Style #2* design (per-domain two-FF
Gray sync, (N+1)-bit pointers, no async direction comparator) and the
testbench had a real queue-based scoreboard.

After explicit user direction (2026-05-25) the DUT and TB were further
patched to correct three latent defects identified during a post-hoc
re-audit. The pre-fix run already produced `*** PASSED ***` with 100%
code coverage, so the fixes don't change end-to-end functional behaviour
under the existing TB -- they harden the design against latent
SystemVerilog LRM violations and CDC reset issues that random
simulation wasn't exercising.

## RTL structure (post-fix)

```
asynchronous_fifo (top)
├── fifo_memory    - dual-port RAM, single-driver write, single-driver read
├── write_pointer  - binary->Gray write pointer, wFull, AND wHalfFull (NEW)
├── read_pointer   - binary->Gray read pointer,  rEmpty, AND rHalfEmpty (NEW)
├── sync (w2r)     - two-FF synchroniser, wclk-domain Gray pointer -> rclk; reset by rrst (was wrst)
└── sync (r2w)     - two-FF synchroniser, rclk-domain Gray pointer -> wclk; reset by wrst (was rrst)
```

The hierarchy is unchanged; the difference is in *where each flag is
computed*. The pre-fix design had `fifo_count` -- a single register
driven by both `wclk` and `rclk` `always_ff` blocks (LRM violation) --
and `half_full` / `half_empty` derived from it. Post-fix, each
half-flag is computed in its own clock domain using that domain's
binary pointer and a gray-to-binary conversion of the synced opposite
pointer. No shared state across domains.

Pointer width is `[ADDR_SIZE:0]` (7 bits at default depth-64). The
extra MSB distinguishes "same position, one wrap apart" (full) from
"same position, no wraps apart" (empty), per the Style #2 convention.

## FSM applicability

No FSM diagram is generated. The DUT has no encoded state, no
`always_ff`/`always @(posedge ...)` state-transition machine. Sequential
elements are pointer counters, two-FF synchronisers, and registered
flags -- none are FSMs.

## Fixes applied (2026-05-25)

Each fix is a minimum-invasive correction; the original module/port
naming, the bug-injection `+define+` hooks, and the run.do are
preserved.

### Fix #A — Remove `fifo_count` dual-driver violation

The previous `fifo_memory` had two `always_ff` blocks both writing to a
shared `fifo_count` register: one clocked by `wclk` (incrementing on
`winc`), one clocked by `rclk` (decrementing on `rinc`). This violates
SystemVerilog's single-driver rule for `always_ff`. Questa accepted the
code in relaxed mode but the construct is non-portable and a real LRM
defect.

`fifo_count` has been removed entirely. The two half-flag outputs are
now computed locally in each pointer module using a gray-to-binary XOR
cascade on the synced opposite-domain pointer:

- `wHalfFull` (in `write_pointer`): `(binary_wptr - gray_to_bin(wq2_rptr))
  >= DEPTH/2`. Conservative on the "getting full" side because
  `wq2_rptr` lags the actual read pointer by 2 rclk cycles.
- `rHalfEmpty` (in `read_pointer`): `(gray_to_bin(rq2_wptr) - binary_rptr)
  <= DEPTH/2`. Conservative on the "getting empty" side because
  `rq2_wptr` lags the actual write pointer by 2 wclk cycles.

`fifo_memory` is now a pure-storage module: a write port gated by `winc`
(externally pre-gated by `winc & ~wFull` from `asynchronous_fifo`) and a
read port gated by `rinc` (externally pre-gated by `rinc & ~rEmpty`).
Each has exactly one `always_ff` driver per register.

### Fix #B — Sync flop reset-domain mismatch

The two `sync` instances now use the **destination domain's** reset
rather than the source domain's:

- `sync_w2r` (clocked by `rclk`, synchronises `wptr` into the read
  domain): reset by `rrst` (was `wrst`).
- `sync_r2w` (clocked by `wclk`, synchronises `rptr` into the write
  domain): reset by `wrst` (was `rrst`).

This matches the canonical pattern: a sync register samples from the
source domain and lives in the destination domain, so it should be
reset by the destination's reset signal. The pre-fix wiring sent a
reset signal asynchronous to the flop's clock, which is a CDC concern
even though it never failed under aligned-reset stimulus.

### Fix #C — Initialize `rData` on read-side reset

`fifo_memory`'s read-side `always_ff` previously only assigned `rData`
inside the `else if (rinc)` branch and left it untouched on reset. So
`rData` started as `X` and stayed `X` until the first read. The reset
branch now explicitly assigns `rData <= '0`, removing the X-propagation
window.

### Fix #D — TB `check_wFull` / `check_rEmpty` task semantics

The two flag-invariant tasks are now explicitly annotated as one-shot
spot-checks (with a comment explaining why) and the `fork ... join` is
changed to `fork ... join_none` so they don't block the main initial
block. The check logic is unchanged.

A true continuous monitor (`forever @(negedge clk)` per task) is NOT
applied here because the naive form would false-error every time the
sync window straddles a write or a read: `wdata_q` updates immediately
on every TB-side write, but the DUT's `rEmpty` lags by the two-FF
synchroniser, so for ~2 rclk cycles after the first write the condition
`rEmpty && wdata_q.size() != 0` would fire spuriously. A
CDC-aware continuous monitor is left as an open item.

## Pre-fix defects (for the historical record)

- **A.** `fifo_count` driven by two `always_ff` blocks across clock
  domains -- SV LRM single-driver violation.
- **B.** `sync_w2r` reset by `wrst`, `sync_r2w` reset by `rrst` -- each
  used the *source* domain's reset instead of the destination's.
- **C.** `rData` not reset; started as `X` at simulation time 0.
- **D.** `check_wFull` / `check_rEmpty` tasks under `fork ... join`
  fired once and then exited, despite their names suggesting they
  monitored continuously.

## Testbench structure

`async_fifo_tb.sv` is a `module top` driving the DUT through several
`initial` blocks:

- Reset block: holds both `wrst`/`rrst` low, releases after 40 wclk
  cycles.
- Write block: two bursts of `BURST_SIZE=420` ops at the negedge of
  `wclk`, with `winc` randomised via `$urandom % 2`. When `winc &&
  !wFull`, a random `wData` is generated, pushed into the `wdata_q`
  SystemVerilog queue, and `w_count` increments.
- Read block: two bursts of 420 ops at the negedge of `rclk`. When
  `rinc && !rEmpty`, `compare_data()` is invoked, which pops the
  expected data from `wdata_q` and `$error`s on mismatch.
- `check_wFull` / `check_rEmpty`: one-shot spot-checks (see Fix #D).
- After both bursts complete, the TB checks `error_flag` (latched by
  every `$error` call) and prints `*** PASSED ***` or `*** FAILED ***`,
  then `$finish`.

The TB also opens `dump.vcd` via `$dumpfile`/`$dumpvars`.

## Farm simulation artifacts

Generated by Questa 2021.3_1 on the remote host, batch:
```
vlib work
vsim -c -do 'do run.do; quit -f' 2>&1 | tee transcript_farm.txt
```

- `transcript_farm.txt` — full simulator transcript, including the
  per-stage `Errors: 0, Warnings: 0` lines and the `*** PASSED ***`
  print.
- `dump.vcd` — VCD dumped by the TB. Not committed (gitignored).
- `async_fifo.ucdb` — Questa UCDB with 100% code coverage on DUT.
  Not committed (gitignored).
- `waveform_samples.csv` — 1481 change events of the tracked signals
  across the full 0–17930 ns range.
- `waveforms.png` / `waveforms.svg` — windowed plot (0–2500 ns).

The two pre-existing transcripts (`transcript.txt`, `transcript2.txt`)
are the team's original Questa-2019.2_1 runs from June 2024,
preserved (with personal-info redactions applied per user request) for
milestone provenance.

## Open items (deliberately not addressed in this fix pass)

- **CDC-aware continuous flag monitor.** See Fix #D rationale. The
  proper form would either tolerate ~2 destination clocks of lag or
  use a CDC-corrected queue depth as the comparison reference.
- **No covergroups in the TB.** Only statement/branch/FEC code coverage
  is instrumented; functional coverage starts appearing in M4/M5/Post_M5.
- **No directed edge cases.** Random stimulus only; back-to-back wraps,
  simultaneous full/empty, reset during active traffic are tested in
  later milestones.

## Summary

A clean, self-checking pass demonstrating the team's transition to a
verifiable design + testbench, hardened against three latent SV/CDC
defects that the original random stimulus did not exercise hard enough
to surface. This run is the milestone-1 anchor for "the FIFO works";
everything from M2 onwards layers methodology (class-based, then UVM)
on top of essentially the same RTL.
