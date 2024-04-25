if [file exists "work"] {vdel -all}
vlib work

vlog +acc -source -lint async_fifo.sv async_fifo_tb.sv
vsim -voptargs=+acc work.top

add wave -position insertpoint sim:/top/uut/*

add wave -position insertpoint sim:/top/uut/async_cmp/*
add wave -position insertpoint sim:/top/uut/fifomem/*
add wave -position insertpoint sim:/top/uut/rptr_empty/*
add wave -position insertpoint sim:/top/uut/wptr_full/*

run -all