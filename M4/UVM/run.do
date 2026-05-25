# Guard vdel so a fresh farm checkout does not fail when work/ is absent.
if {[file exists work]} {
  vdel -all
}
vlib work

vlog -source -lint async_fifo.sv
vlog -source -lint async_fifo_package.sv
vlog -source -lint async_fifo_top.sv
vlog -source -lint async_fifo_test.sv
vlog -source -lint async_fifo_driver.sv
vlog -source -lint async_fifo_env.sv
vlog -source -lint async_fifo_testrand.sv
vlog -source -lint async_fifo_interface.sv
vlog -source -lint async_fifo_read_agent.sv
vlog -source -lint async_fifo_scoreboard.sv
vlog -source -lint async_fifo_seq_item.sv
vlog -source -lint async_fifo_seq_test.sv
vlog -source -lint async_fifo_seq_testrand.sv
vlog -source -lint async_fifo_sequencer.sv
vlog -source -lint async_fifo_write_agent.sv
vlog -source -lint async_fifo_coverage.sv
vlog -source -lint async_fifo_read_monitor.sv
vlog -source -lint async_fifo_write_monitor.sv

# Instrument code coverage on the DUT only; covergroup data is still
# collected by running vsim with -coverage.
vopt tb_top -o top_optimized +acc +cover=sbfec+asynchronous_fifo(rtl).
vsim top_optimized -coverage

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all

coverage save async_fifo.ucdb
vcover report async_fifo.ucdb
vcover report async_fifo.ucdb -cvg -details
