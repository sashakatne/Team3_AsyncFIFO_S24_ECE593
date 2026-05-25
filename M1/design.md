# M1 root review (Style #1 async FIFO, POST-FIX)

## What lives here

`async_fifo2.sv` is the team's earliest async FIFO, structured as Cliff
Cummings's *Style #1*: a single-bit `direction` flop, set/cleared by quadrant
comparisons of the top two pointer bits, distinguishes full from empty when
the two N-bit Gray pointers are equal. The procedural testbench in
`async_fifo2_tb.sv` is `$monitor`-only — no scoreboard, no assertions.

This directory was originally preserved verbatim as a frozen milestone
snapshot. After explicit user direction (2026-05-25) it was patched to
correct the 6 DUT defects and 1 TB defect that the milestone-progression
documentation identified. The fixes preserve the Style #1 architecture
(no architectural rewrite to Style #2); only the specific defects are
addressed. The canonical Style #2 implementation continues to live in
`Post_M5/UVM/async_fifo.sv`.

## RTL structure (post-fix)

```
fifo2 (top)
├── async_cmp     - quadrant-based direction flop -> aempty_n, afull_n
├── fifomem       - dual-port RAM, addressed by BINARY pointers (was Gray)
├── rptr_empty    - GRAYSTYLE2 read-pointer + async-assert / sync-deassert empty
│                   + exposes binary `raddr` to fifomem
└── wptr_full     - GRAYSTYLE2 write-pointer + async-assert / sync-deassert full
                    + exposes binary `waddr` to fifomem
```

Default parameters: `DSIZE=8`, `ASIZE=6` (depth 64), `WCLK_PERIOD=12.5 ns`
(80 MHz), `RCLK_PERIOD=20 ns` (50 MHz). Pointer width is still `ASIZE` bits
(6) -- the Style #1 hallmark -- but memory addressing now uses the binary
pointer (also `ASIZE` bits) routed from the pointer modules.

## FSM applicability

No FSM diagram is generated. The DUT has no encoded state, no `always_ff`
or `always @(posedge ...)` state-transition machine. Its sequential elements
are pointer counters, two-bit flag synchronisers, and the asynchronous
`direction` flop -- none of which are FSMs.

## Fixes applied (2026-05-25)

Each fix is a minimum-invasive correction of a defect documented under
"Original defects" below; the original RTL/TB style was preserved.

### Fix #1 — Declare `aempty_n` / `afull_n` in `fifo2`

The two nets are now explicitly declared (`wire aempty_n, afull_n;`),
eliminating the two `vlog-2623` / `vopt-2623` implicit-net warnings. The
old behaviour (implicit-net auto-creation) happened to wire the nets
correctly, but a future rename of either submodule port would silently
break the connection.

### Fix #2 — Gate the memory write enable by `~wfull`

`fifo2` now passes `(winc & ~wfull)` as the `wclken` input to `fifomem`
(was bare `winc`). Without this gate, a `winc=1` arriving when the FIFO
was full -- which can happen because the original TB took one clock to
react to `wfull` -- would store the new `wdata` at the just-wrapped write
address, clobbering `mem[0]`. This was the root cause of the M1-root
`rdata=65` first-read artefact documented in pre-fix evidence.

### Fix #3 — Address memory with binary pointers

`fifomem.waddr` and `fifomem.raddr` are now driven by the binary
`wbin`/`rbin` values exposed as new output ports from `wptr_full` and
`rptr_empty`. Memory cells are filled in natural binary order
(`0, 1, 2, 3, …`) rather than the previous Gray order (`0, 1, 3, 2,
6, 7, 5, 4, …`). The Gray pointers (`wptr`, `rptr`) continue to feed
`async_cmp`, where Gray coding is needed for CDC robustness. This
separation of concerns matches the canonical Cummings reference design.

### Fix #4 — Add `rrst_n` to the `rempty` reset path

The always block that maintains `{rempty,rempty2}` now has `negedge
rrst_n` in its sensitivity list and resets the pair to `2'b11` (empty)
on assertion. Previously, only the async `aempty_n` path drove
`rempty` -- which itself depended on `direction`, which only cleared
through `wrst_n` via `async_cmp.dirclr_n`. The read domain is now
self-contained for reset purposes, symmetric with the existing
`wfull` reset on `wrst_n`.

### Fix #5 — Remove the unreachable `posedge high` branch

`async_cmp` used to declare `wire high = 1'b1;` and trigger its
direction flop on `posedge high or negedge dirset_n or negedge
dirclr_n`. The `posedge high` event can never fire (the wire is a
constant) so the `else direction <= high;` branch was dead code. The
sensitivity list is now `negedge dirset_n or negedge dirclr_n` and the
unreachable assignment is gone -- behaviour is unchanged.

### Fix #6 — Initialize `direction`

`async_cmp.direction` is now declared with `reg direction = 1'b0;`. On
real silicon the value used to be `X` until `wrst_n` propagated through
`dirclr_n`; this could briefly drive `aempty_n` / `afull_n` to `X`.
The explicit initial value removes that window.

### Fix #7 — TB drives stimulus at `negedge wclk` / `negedge rclk`

`async_fifo2_tb.sv` previously used non-blocking assignments to
`winc`/`wdata` inside an `@(posedge wclk)` block. The Verilog NBA
ordering meant that when the DUT raised `wfull` mid-edge, the TB still
had `winc=1` in flight from the previous cycle, so the DUT (before
Fix #2) wrote one extra word. The TB now waits for the falling edge
(when nothing else is happening), updates `winc`/`wdata` with blocking
assignments, and lets those signals settle before the next rising
edge. Combined with the DUT's `~wfull` gate this removes the race
two ways over.

## Original defects (pre-fix, for the historical record)

Issue #1 — Implicit nets for `aempty_n` / `afull_n` (HIGH style, LOW
functional). 2 `vlog-2623` warnings on every compile.

Issue #2 — Memory writes were NOT gated by `wfull`. The pointer was, but
`always @(posedge wclk) if (wclken) MEM[waddr] <= wdata;` fired
unconditionally on `winc`. When the TB issued the (one-cycle-late) extra
write, it clobbered `mem[wbin=0]`.

Issue #3 — Memory was addressed by Gray-coded pointers, conflating the
CDC role of the Gray encoding with the memory addressing role.

Issue #4 — Asymmetric reset on `rempty`. `wfull` had explicit `wrst_n`,
`rempty` did not.

Issue #5 — Unreachable `posedge high` branch in `async_cmp` (benign but
indicative of copy-paste from older code).

Issue #6 — `direction` register had no initial value; `X` propagation
window during reset.

Issue #TB-1 — TB used NBAs in `@(posedge wclk)`, lagging one cycle on
`wfull` and (combined with Issue #2) causing the overflow write.

## Farm simulation artifacts

Generated by Questa 2021.3_1 on the remote host, batch:
```
vsim -c -do 'do run.do; quit -f' 2>&1 | tee transcript.txt
```

- `transcript.txt` — full simulator transcript, zero compile warnings.
- `waveform_samples.csv` — 133 `$monitor` change events parsed from the
  transcript (one row per sampled change).
- `waveforms.png` / `waveforms.svg` — digital-waveform plot of `wfull`,
  `rempty`, `wdata`, `rdata` from 0 to 2910 ns.

The waveform now shows correct FIFO operation:
- t=0 to ~110 ns: reset window. `rempty=1`, `wfull=0`.
- t≈110 ns: `rempty` deasserts after the two-FF synchroniser settles.
- t≈110 to 834 ns: 64 writes accumulate. `wdata` increments to 64
  (was 65 pre-fix).
- t=834 ns: `wfull` asserts. TB stops issuing new writes.
- t=1650 to 2890 ns: reads return `1, 2, 3, …, 64` in order (was `65, 2,
  3, …, 64` pre-fix -- the `65` was the overflow-corrupted `mem[0]`).
- t=2910 ns: `rempty` re-asserts.
- t=4240 ns: TB hits `$finish`.

## Summary

| Item                       | Pre-fix                              | Post-fix                                |
| -------------------------- | ------------------------------------ | --------------------------------------- |
| `vlog` warnings            | 2 (implicit nets)                    | **0**                                   |
| `vopt` warnings            | 2                                    | **0**                                   |
| Reaches `$finish`?         | Yes (4210 ns)                        | Yes (4240 ns)                           |
| First read value           | 65 (overflow-clobbered mem[0])       | **1** (the first written word)          |
| Read sequence              | 65, 2, 3, …, 64                      | **1, 2, 3, …, 64**                      |
| `wfull` asserts at         | t=834 ns with `wdata=65`             | t=834 ns with **`wdata=64`**            |
| Self-checking?             | No -- `$monitor` only                | No -- `$monitor` only (TB unchanged)    |
| Code coverage?             | Not instrumented                     | Not instrumented (run.do unchanged)     |

## Open items (deliberately not addressed in this fix pass)

- **Style #2 migration.** Issue #6 in the original review was that
  Style #1 (async direction flop) is generally considered less robust
  than Style #2 ((N+1)-bit pointers, no async comparator). The fixes
  here preserve Style #1; a Style #2 rewrite is a separate decision and
  is already realised in `M1/ConventionalTB`, `M4/UVM`, `M5/UVM`, and
  `Post_M5/UVM`.
- **TB has no scoreboard.** The M1 root TB is still `$monitor`-only.
  Adding a queue-based checker would catch any future regression but is
  out of scope for "fix the bugs"; the scoreboarded variant already
  exists in `M1/ConventionalTB/async_fifo_tb.sv`.
- **`run.do` GUI artefacts.** `add wave -position insertpoint sim:/top/uut/*`
  lines still execute (harmlessly) after `run -all` in batch mode. Left
  untouched so the GUI run.do continues to behave as the original author
  intended.
