if {[file exists work]} {
  vdel -all
}
vlib work

vlog -source -lint async_fifo.sv
vlog -source -lint flag_threshold_tb.sv

vopt flag_threshold_tb -o flag_threshold_optimized +acc
vsim flag_threshold_optimized

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all
