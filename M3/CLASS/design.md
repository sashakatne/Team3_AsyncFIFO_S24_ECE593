# M3/CLASS review (enhanced class-based async FIFO TB, POST-FIX)

## What lives here

This directory is the M3 enhanced class-based verification environment
for the Style #2 asynchronous FIFO. It builds on the M2 class stack
with an in-top functional covergroup. Before this fix pass, M3 still
carried the same structural issues found in M2:

- both synchronizers were clocked in the source domain instead of the
  destination domain;
- driver, monitor, and scoreboard execution was effectively
  one-transaction-at-a-time;
- write and read stimulus were serialized instead of independent;
- the monitor sampled writes only from the read-clock view;
- the scoreboard printed mismatch text but did not raise `$error` or
  produce a final PASS/FAIL verdict;
- `run.do` mixed several incompatible coverage flows and ended with a
  `vcover-7` error in the original transcript.

The post-fix M3 code now follows the same architecture as the fixed M2
class environment, while preserving the M3 covergroup intent.

## RTL structure

```
asynchronous_fifo
|-- fifo_mem             combinational read from b_rptr, gated writes
|-- synchronizer_r2w     read pointer synchronized into write domain
|                         clk = wclk, rst_n = wrst
|-- synchronizer_w2r     write pointer synchronized into read domain
|                         clk = rclk, rst_n = rrst
|-- rptr_handler         binary/gray read pointer, rEmpty, rHalfEmpty
`-- wptr_handler         binary/gray write pointer, wFull, wHalfFull
```

Default parameters remain `DATA_SIZE=8` and `ADDR_SIZE=6`, giving a
64-entry FIFO with 7-bit wrap-aware binary and Gray pointers.

## Fixes applied

### D-1: Synchronizer clock/reset domains

Pre-fix:

```systemverilog
synchronizer_r2w_inst (.clk(rclk), .rst_n(rrst), .d_in(g_rptr), .d_out(g_rptr_sync));
synchronizer_w2r_inst (.clk(wclk), .rst_n(wrst), .d_in(g_wptr), .d_out(g_wptr_sync));
```

Both synchronizers were clocked by the source domain. That can look
fine in event-driven simulation but gives no real CDC protection,
because the two flops are not in the destination clock domain.

Post-fix:

```systemverilog
synchronizer_r2w_inst (.clk(wclk), .rst_n(wrst), .d_in(g_rptr), .d_out(g_rptr_sync));
synchronizer_w2r_inst (.clk(rclk), .rst_n(rrst), .d_in(g_wptr), .d_out(g_wptr_sync));
```

The synchronizer reset now follows the destination clock as well.

### D-2: `rData` X window documented, not hidden

`fifo_mem` still leaves the RAM array uninitialized and drives
`rData` combinationally from `fifo[b_rptr]`. That means `rData` is X
at time 0 until the first accepted write reaches the active read
slot. This pass documents that window and keeps the port list stable.
The monitor and scoreboard only compare accepted reads
`(rinc && !rEmpty)`, so the self-checking path does not consume the X.

### T-1: Threaded stimulus streams

The generator now emits two independent transaction streams:

- `gen2driv_w` for the write clock domain;
- `gen2driv_r` for the read clock domain.

The driver forks `drive_writes(n)` and `drive_reads(n)`, driving at
`negedge wclk` and `negedge rclk` respectively so stimulus is stable
before the DUT samples at the following positive edge.

The driver intentionally does not gate stimulus on `wFull` or
`rEmpty`. Overflow and underflow attempts are legal negative stimulus
for the DUT; the DUT's internal `(w_en & !full)` and `(r_en & !empty)`
gates must reject them.

### T-2: Clocking-block monitor

The monitor now has independent write and read observers:

- `observe_writes(n)` samples `write_mon_cb` at `posedge wclk`;
- `observe_reads(n)` samples `monitor_cb` at `posedge rclk`.

The write-side `write_mon_cb` was added to `async_fifo_interface.sv`.
This matters because the test is a `program`, so raw sampling at a
posedge sees post-NBA values. Clocking-block input skew gives the
pre-edge values consumed by the DUT.

### T-3: Queue scoreboard with real verdict

The scoreboard now uses a SystemVerilog queue as the reference model:

- accepted writes push `wData`;
- accepted reads pop and compare against `rData`;
- mismatches call `$error` and increment `error_count`;
- `final_report()` prints observed write/read counts, residual queue
  depth, mismatch count, and `*** PASSED ***` or `*** FAILED ***`.

### T-4: Reset wait fixed

The old driver reset wait short-circuited on a mixed active-low
condition. The fixed driver parks interface signals at 0 and waits for
both active-low resets to deassert:

```systemverilog
wait(drv_if.wrst === 1'b1 && drv_if.rrst === 1'b1);
```

### C-1: Functional coverage cleaned up

The original M3 covergroup crossed clock transitions and reset
high-to-low transitions with data bins. In the checked-in transcript,
those bins were impossible or unreachable for the reset scheme and
left functional coverage at 78.92%. The post-fix covergroup now
targets meaningful FIFO behavior:

- accepted write data ranges;
- accepted read data ranges;
- write request vs full flag (`idle`, `accepted`, `blocked_full`);
- read request vs empty flag (`idle`, `accepted`, `blocked_empty`);
- full/empty/half-full/half-empty transitions;
- reset low-to-high transitions only.

### C-2: Reproducible coverage flow

`run.do` now has one coherent flow:

```tcl
if {[file exists work]} {
  vdel -all
}
vlib work
vlog -source -lint ...
vopt async_fifo_top -o top_optimized +acc +cover=sbfec+asynchronous_fifo(rtl).
vsim top_optimized -coverage
run -all
coverage save async_fifo.ucdb
vcover report async_fifo.ucdb
vcover report async_fifo.ucdb -cvg -details
```

Code coverage is scoped to the DUT. Covergroup data from
`async_fifo_top` is still collected by `vsim -coverage`.

## Post-fix testbench structure

```
async_fifo_top
|-- intf in
|   |-- driver_cb      @(posedge wclk)
|   |-- monitor_cb     @(posedge rclk)
|   `-- write_mon_cb   @(posedge wclk)
|-- test t1
|   `-- environment
|       |-- generator     two randomized streams
|       |-- driver        forked write/read drivers
|       |-- monitor       forked write/read monitors
|       `-- scoreboard    queue reference model
|-- async_fifo_cover      M3 functional covergroup
`-- DUT
```

The test currently runs 500 stimulus cycles per side, then allows a
200-read-clock quiet period before the final scoreboard report.

## Farm simulation evidence

Generated on the PSU ECE farm with Questa 2021.3_1:

```sh
vsim -c -do 'do run.do; quit -f' 2>&1 | tee transcript_farm.txt
python3 make_artifacts.py
```

Run metadata:

- Start UTC: `2026-05-25T21-35-36Z`
- End UTC: `2026-05-25T21-35-42Z`
- Remote run dir: `~/claude-runs/2026-05-25T21-35-26Z_m3-class-sim`
- Exit status: `0`

The post-fix transcript proves the expected gate:

- all five `vlog` phases and `vopt` end with `Errors: 0, Warnings: 0`;
- the simulation reaches `$finish` at `async_fifo_environment.sv:58`,
  time `14070 ns`;
- the scoreboard prints `Verdict: *** PASSED ***`;
- observed transactions are balanced: `206` writes, `206` reads,
  residual queue size `0`, mismatches/errors `0`;
- `vcover report async_fifo.ucdb` reports 100% filtered coverage;
- `vcover report async_fifo.ucdb -cvg -details` reports 100%
  covergroup coverage, with 26/26 bins hit.

Code coverage:

```
/async_fifo_top/DUT/fifo_mem_inst         Branches 2/2, Conditions 2/2, Statements 3/3      100%
/async_fifo_top/DUT/synchronizer_r2w_inst Branches 2/2,                 Statements 5/5      100%
/async_fifo_top/DUT/synchronizer_w2r_inst Branches 2/2,                 Statements 5/5      100%
/async_fifo_top/DUT/rptr_handler_inst     Branches 6/6, Expressions 14/14, Statements 22/22 100%
/async_fifo_top/DUT/wptr_handler_inst     Branches 6/6, Expressions 14/14, Statements 22/22 100%
TOTAL filtered view                                                                           100%
```

Functional coverage:

```
async_fifo_cover: 26/26 bins hit, TOTAL COVERGROUP COVERAGE 100.00%
cp_write_access.blocked_full  hit 68
cp_read_access.blocked_empty  hit 109
```

Waveform evidence:

- `dump.vcd` from the farm run contains the full 0 - 14070 ns trace
  and is gitignored as a raw simulator artifact.
- `make_artifacts.py` parsed 836 tracked DUT-port signal changes into
  `waveform_samples.csv`.
- `waveforms.svg` and `waveforms.png` render the 0 - 2500 ns review
  window.

The checked-in `M3/docs/transcript.txt` remains the original pre-fix
student run. It compiled, reached 99.87% code coverage, but had only
78.92% covergroup coverage and ended with `vcover-7` because the old
script asked `vcover` to open `coverage_results` as a UCDB.

## Open items

- The `fifo_mem` reset port remains intentionally unchanged. Closing
  the X window in RTL requires a port-list change.
