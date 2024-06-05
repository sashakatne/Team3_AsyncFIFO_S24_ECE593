vdel -all

vlib work

# vlog -source -lint async_fifo.sv
vlog +define+INJECT_THE_BUG -source -lint async_fifo.sv

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

# vsim +define+BASE_TEST -coverage -vopt work.tb_top -c -do "coverage save -onexit -directive -codeAll basetest.ucdb; run -all"
# vsim -coverage -vopt work.tb_top -c -do "coverage save -onexit -directive -codeAll randomtest.ucdb; run -all; exit"

# vcover merge output basetest.ucdb randomtest.ucdb
# vcover report -html output

vopt tb_top -o top_optimized +acc +cover=sbfec+asynchronous_fifo(rtl).

vsim top_optimized -coverage
# vsim +define+BASE_TEST top_optimized -coverage

set NoQuitOnFinish 1
onbreak {resume}
log /* -r
run -all

coverage save async_fifo.ucdb
vcover report async_fifo.ucdb
vcover report async_fifo.ucdb -cvg -details
