# M2/CLASS review (Style #2 async FIFO + class-based scoreboard, POST-FIX)

## What lives here

This directory contains the team's first **class-based** async FIFO
testbench. The DUT (`async_fifo.sv`) was already a Cliff Cummings
*Style #2* design (per-domain pointer handlers, (N+1)-bit Gray pointers
with a wrap-aware full-compare, and a generic 2-flop synchroniser), and
the TB was an early generator/driver/monitor/scoreboard/environment
stack -- pre-UVM, but with the same separation of concerns. After
explicit user direction (2026-05-25) the DUT and TB were patched to
correct a critical CDC defect, several broken-iteration defects in the
class TB, and the missing PASS/FAIL verdict.

The pre-fix testbench compiled and "ran" but did not actually exercise
the FIFO: each invocation of `driver.main()` / `monitor.main()` /
`scoreboard.main()` had a `for (int i = 0; i < 1; i++)` loop -- one
mailbox `get` per call. The environment's outer loop refilled the
mailbox every iteration, so the back-pressure pattern was indeterminate
and the scoreboard's `$display("ERROR ...")` never set a flag or
called `$error`, so the simulator's transcript reported `Errors: 0`
regardless of data integrity. The post-fix TB drives 500 cycles per
side, the scoreboard is queue-based with explicit error counting, and
the run ends with an explicit `*** PASSED ***` / `*** FAILED ***`
print.

## RTL structure (post-fix)

```
asynchronous_fifo (top)
├── fifo_mem            - dual-port RAM; combinational read on b_rptr
├── synchronizer_r2w    - 2-FF gray pointer cross from read into write domain
│                         clk = wclk (destination), rst_n = wrst (destination)
├── synchronizer_w2r    - 2-FF gray pointer cross from write into read domain
│                         clk = rclk (destination), rst_n = rrst (destination)
├── rptr_handler        - binary -> gray rptr, rEmpty, rHalfEmpty (per-domain)
└── wptr_handler        - binary -> gray wptr, wFull,  wHalfFull  (per-domain)
```

Default parameters: `DATA_SIZE=8`, `ADDR_SIZE=6` (depth 64),
`WCLK_PERIOD=12.5 ns` (80 MHz), `RCLK_PERIOD=20 ns` (50 MHz). The
pointer width is `[ADDR_SIZE:0]` (7 bits) for the standard Style #2
wrap-aware compare. The half-full / half-empty flags are computed in
each pointer handler from `binary_wptr - gray_to_binary(g_rptr_sync)`
(and the symmetric form for half_empty), avoiding the dual-driver
`fifo_count` pattern seen in `M1/ConventionalTB`.

## FSM applicability

No FSM diagram is generated. The DUT has no encoded state, no
`always_ff` state-transition machine. Sequential elements are pointer
counters, two-FF synchronisers, and registered flags -- none are FSMs.

## Fixes applied (2026-05-25)

Each fix is the minimum surgery to correct the defect; module/port
names, file names, and the bug-injection (none) hooks are preserved.

### Fix #D-1 -- CDC synchroniser clock and reset domain

**Pre-fix:**
```
synchronizer_r2w_inst .clk(rclk) .rst_n(rrst)  // source-domain clock
synchronizer_w2r_inst .clk(wclk) .rst_n(wrst)  // source-domain clock
```

Both synchroniser instances were clocked by the **source** domain (the
domain that produces the gray pointer being synchronised). On real
silicon this gives zero metastability protection: both flops live in
the wrong domain, and the destination logic samples a signal that has
never been resynchronised. In event-driven simulation values resolve
deterministically and the bug is invisible -- which is why the
pre-fix transcript "passed" despite this being broken.

**Post-fix:**
```
synchronizer_r2w_inst .clk(wclk) .rst_n(wrst)  // destination-domain clock/reset
synchronizer_w2r_inst .clk(rclk) .rst_n(rrst)  // destination-domain clock/reset
```

Both sync flops now live in their destination domain, matching the
canonical Cummings pattern and giving the expected two-FF metastability
window. Reset is also routed from the destination domain, which is the
strictly-correct choice for a flop whose clock is the destination
clock.

### Fix #D-2 (deferred) -- `rData` X-propagation window

`fifo_mem.data_out = fifo[b_rptr[ADDR_SIZE-1:0]]` is combinational on
an unreset memory array. At simulation time 0 the array is `X`, so
`rData` is `X` until the first write reaches the active read slot.

We considered two fixes:

1. Initialise the array at elaboration: `reg [...] fifo[...] = '{default: '0};`.
   Questa 2021.3_1 rejects this under `vopt-7061` because the strict
   `always_ff` single-driver rule treats the elaboration initialiser
   as a competing process driver for `fifo`.
2. Add a reset port to `fifo_mem` and zero the array on reset.
   This changes the module port list, which is outside the scope of a
   "fix the bugs, don't restructure" pass.

The post-fix TB makes this defect benign: the read-side monitor and
the scoreboard both gate on `(rinc && !rEmpty)`, and `rEmpty` is
registered `1` at reset and stays asserted until the first write
propagates through both Gray pointers and the (now correctly clocked)
synchroniser. By the time a read transaction is observed, the
corresponding write has already populated the slot. No scoreboard
comparison ever sees the `X`. We document the defect rather than
hide it.

A future fix-pass that is willing to touch the `fifo_mem` port list
should add a reset path; the canonical Post_M5 design (`Post_M5/UVM/`)
has the same X-window for the same reason, with the same TB-side
mitigation.

### Fix #T-1 -- Driver / monitor / scoreboard iteration

**Pre-fix:** every class's `main()` had `for (int i = 0; i < 1; i++)`,
consuming one mailbox entry per invocation. The environment's outer
loop generated a fresh batch of 30 transactions every iteration and
the driver only consumed one, so 29 were silently discarded. Net
stimulus delivered was a tiny fraction of the nominal count.

**Post-fix:** the entire TB stack is rebuilt around long-running
threads:

- `generator.main()` emits `trans_count` randomised transactions to
  two independent mailboxes (`gen2driv_w`, `gen2driv_r`) -- one for
  each clock domain.
- `driver.main(n)` forks `drive_writes(n)` and `drive_reads(n)`. Each
  thread loops `n` times, sampling on its own clock's negedge,
  pulling one transaction per cycle.
- `monitor.main(n)` forks `observe_writes(n)` and `observe_reads(n)`,
  each looping `n` times on its own clock's posedge and pushing
  observed transactions to the scoreboard.
- `scoreboard.main()` forks `process_writes()` and `process_reads()`
  as forever-loops in `fork ... join_none`. Writes push to a
  `bit [DATA_SIZE-1:0] expected_q [$]` queue; reads pop and compare.

The environment's `run()` now does `pre_env -> test_run -> post_env`,
where `test_run` starts the scoreboard threads first then joins on
the producer + driver + monitor threads. `post_env` adds a 200-rclk
quiet period so the scoreboard can drain any in-flight observations.

### Fix #T-2 -- PASS / FAIL verdict

**Pre-fix:** the scoreboard printed `$display("ERROR ...")` on
mismatch but never set an error flag and never called `$error` or
`$fatal`. The transcript's `Errors:` line always read 0 regardless of
data integrity.

**Post-fix:** each mismatch now goes through `$error(...)` (which
increments the simulator's error count and triggers a Questa-side
`** Error` print) **and** increments an internal `error_count`. The
scoreboard's `final_report()` prints a clear `==== SCOREBOARD
SUMMARY ====` block at the end of the run, including
`Writes observed`, `Reads observed`, residual queue size, and a
`Verdict: *** PASSED ***` / `*** FAILED ***` line. The environment
calls `final_report()` from `post_env()` before `$finish`.

### Fix #T-3 -- Driver reset wait

**Pre-fix:**
```
wait(drv_if.wrst || drv_if.rrst);
drv_if.wData <= '0; drv_if.winc <= '0; drv_if.rinc <= '0;
wait(!drv_if.wrst || drv_if.rrst);
```

The second `wait` is logically backwards: with `wrst`/`rrst` active-low
and driven 0 at time 0 then 1 after the reset window, `!drv_if.wrst ||
drv_if.rrst` evaluates to 1 the moment `rrst` deasserts (regardless of
`wrst`), so the wait short-circuits.

**Post-fix:** signals are parked at 0 immediately, then a single
`wait(drv_if.wrst === 1'b1 && drv_if.rrst === 1'b1)` blocks until both
reset domains have deasserted. After that the driver proceeds.

### Fix #T-4 -- Independent write- and read-side stimulus

**Pre-fix:** the driver's `drive()` task issued a `winc` on `posedge
wclk`, then if `rinc` was also randomised true, waited two `posedge
rclk`s before continuing. This serialised the two clock domains --
the whole point of an *async* FIFO TB is that the two sides issue
independent stimulus.

**Post-fix:** the driver forks `drive_writes` (negedge wclk) and
`drive_reads` (negedge rclk) as independent threads. They share
nothing beyond the virtual interface. Same for the monitor.

### Fix #T-5 -- Write-side monitor

**Pre-fix:** there was only one monitor, sampling at `posedge rclk`,
which captured both write- and read-side signals from a read-clock
view. This made coherent write-vs-read scoreboard arithmetic
impossible: writes can occur at wclk edges that don't line up with
any rclk sample.

**Post-fix:** `monitor.observe_writes` samples at `posedge wclk` via
the new `write_mon_cb` clocking block; `monitor.observe_reads`
samples at `posedge rclk` via the existing `monitor_cb` clocking
block. The scoreboard consumes a write stream and a read stream
independently.

### Subtlety -- Clocking-block sampling

The monitor MUST use clocking blocks, not raw interface signal
references. Programs schedule in the Reactive region (per IEEE
1800-2017 §4.4), which fires **after** module-side NBAs. A program
that does `@(posedge clk); if (mon_if.winc && !mon_if.wFull)` samples
the **post-edge** state, so any flag that updates on this edge is
read with the new value -- undercounting boundary writes when
`wFull` transitions 0->1 and overcounting reads when `b_rptr`
increments. Sampling via `mon_if.write_mon_cb.winc` (default `#1step`
input skew) captures the pre-edge value, matching what the DUT's
Active-region `always_ff` saw. This was found by direct experiment:
with raw-signal sampling, a 500-cycle run reported 180 writes / 205
reads / 202 errors; with clocking-block sampling the same stimulus
reported 206 writes / 206 reads / 0 errors.

### Subtlety -- Coverage requires un-gated stimulus

The driver was initially gated as `winc = t.winc && !wFull` (and
`rinc = t.rinc && !rEmpty`). That gating protected the DUT from
overflow stimulus -- but the DUT was designed to handle that stimulus
correctly (via its internal `(w_en & !full)` gate in `fifo_mem` and
`(r_en & !empty)` gate in `b_rptr_next`). The driver-side gating
left the FEC bin in `fifo_mem`'s `if(w_en & !full)` for the
`(w_en=1, full=1)` case unhit -- the DUT had no chance to exercise
the `!full` half of the expression independently. The fix drops the
driver-side gate; the DUT's internal gate keeps data integrity
correct, the monitor still excludes the rejected cycles from its
count, and the coverage report reaches 100% on all instances.

## Pre-fix defects (for the historical record)

- **D-1.** Both synchronisers clocked by source domain.
- **D-2.** `rData` undriven until first write (deferred -- mitigated by TB).
- **T-1.** `for i<1` iteration on driver/monitor/scoreboard `main()`.
- **T-2.** No PASS/FAIL print, no error flag.
- **T-3.** Driver reset wait logically inverted.
- **T-4.** Write and read stimulus serialised in a single `drive()`.
- **T-5.** Single monitor sampling only on `posedge rclk`.

## Testbench structure (post-fix)

```
async_fifo_top (module)
├── intf in (wclk, rclk, wrst, rrst)
│     ├── clocking driver_cb      @(posedge wclk)  -- driver outputs
│     ├── clocking monitor_cb     @(posedge rclk)  -- read-monitor inputs
│     └── clocking write_mon_cb   @(posedge wclk)  -- write-monitor inputs (NEW)
├── test t1 (program)
│     └── env = new(in); env.run();
│         ├── env.pre_env()  : driver.reset()
│         ├── env.test_run() :
│         │     scb.main()                -- forks scoreboard consumers
│         │     fork
│         │       gen.main()              -- emit 500 to each mailbox
│         │       driv.main(500)          -- 500 cycles per side, threaded
│         │       mon.main(500)           -- 500 samples per side, threaded
│         │     join
│         └── env.post_env() : 200-rclk drain, then scb.final_report()
└── asynchronous_fifo DUT (.intf.in.*)
```

Total runtime ~14 us (500 rclk * 20 ns + drain).

## Farm simulation artifacts

Generated by Questa 2021.3_1 on the remote host, batch:
```
vsim -c -do 'do run.do; quit -f' 2>&1 | tee transcript_farm.txt
```

- `transcript_farm.txt` -- full simulator transcript including
  `Errors: 0, Warnings: 0` from every vlog/vopt phase and the
  `*** PASSED ***` print from the scoreboard.
- `dump.vcd` -- VCD generated by the top module's `$dumpfile` /
  `$dumpvars` (gitignored).
- `async_fifo.ucdb` -- Questa UCDB with 100% code coverage on every
  DUT instance (gitignored).
- `waveform_samples.csv` -- 848 change events of the tracked
  signals across the full 0 – 14070 ns range.
- `waveforms.png` / `waveforms.svg` -- windowed plot (0 – 2500 ns)
  showing the first fill-and-drain phase.

## Code coverage (per-instance)

```
/async_fifo_top/DUT/fifo_mem_inst        Branches 2/2,  Conditions 2/2,  Statements 3/3    100%
/async_fifo_top/DUT/synchronizer_r2w_inst Branches 2/2,                  Statements 5/5    100%
/async_fifo_top/DUT/synchronizer_w2r_inst Branches 2/2,                  Statements 5/5    100%
/async_fifo_top/DUT/rptr_handler_inst    Branches 6/6,  Expressions 14/14, Statements 22/22 100%
/async_fifo_top/DUT/wptr_handler_inst    Branches 6/6,  Expressions 14/14, Statements 22/22 100%
TOTAL                                                                                       100.00%
```

No covergroups are defined in the TB (functional coverage appears in
M4/M5/Post_M5), so `vcover report ... -cvg -details` reports `No
matching coverage data found`. That is not a regression.

## Open items (deliberately not addressed)

- **`fifo_mem` reset port.** D-2 mitigation is currently TB-side
  (rEmpty gating). A port-list change to add a reset path would close
  the silicon-side X window. Out of scope for this fix pass.
- **Filename typo.** `aysnc_fifo_interface.sv` (sic) is preserved
  because every reference in `async_fifo_top.sv` and the package
  uses this name. Renaming would be churn for no functional gain.
- **`transaction.sv` dead members.** `bit wrst, rrst, wclk, rclk`
  members exist but are unused. Preserved for milestone provenance.
- **No functional coverage / covergroups.** The TB only collects
  code coverage. Covergroups appear in M4 onward.

## Summary

The pre-fix M2 testbench compiled and the scoreboard printed
`MATCH`/`ERROR` lines but did not actually self-check (no
error_count, no `$error`, no PASS/FAIL print). The post-fix
testbench drives 500 stimulus cycles per clock domain through a
threaded driver/monitor, comparing every read against an
expected-data queue, and exits with an explicit verdict. The CDC
defect in both synchronisers (clock and reset on the source
instead of the destination domain) is corrected. The run reports
zero errors, zero warnings, and 100% code coverage on every
DUT instance.
