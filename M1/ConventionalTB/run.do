vdel -all

vlib work

# vlog -source -lint async_fifo.sv
vlog -source -lint async_fifo2.sv

vlog -source -lint async_fifo_tb.sv
# vlog -source -lint async_fifo_tb2.sv

vopt top -o top_optimized +acc +cover=sbfec+asynchronous_fifo(rtl).

vsim top_optimized -coverage

set NoQuitOnFinish 1
onbreak {resume}
log /* -r
run -all

coverage save async_fifo.ucdb
vcover report async_fifo.ucdb
vcover report async_fifo.ucdb -cvg -details

add wave -position insertpoint sim:/top/DUT/*
