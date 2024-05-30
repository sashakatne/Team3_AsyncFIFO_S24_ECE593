vlib work
vlog async_fifo.sv
vlog async_fifo_package.sv
vlog async_fifo_top.sv
vlog async_fifo_test.sv
vlog async_fifo_driver.sv
vlog async_fifo_env.sv
#vlog async_fifo_test2.sv
vlog async_fifo_interface.sv
#vlog async_fifo_test3.sv
vlog async_fifo_read_agent.sv
vlog async_fifo_scoreboard.sv
vlog async_fifo_seq_item.sv
vlog async_fifo_seq_test.sv
vlog async_fifo_sequencer.sv
vlog async_fifo_write_agent.sv
vlog async_fifo_coverage.sv
vlog async_fifo_read_monitor.sv
vlog async_fifo_write_monitor.sv

add wave -r \*

vsim -coverage -vopt work.tb_top -c -do "coverage save -onexit -directive -codeAll test.ucdb; run -all"
