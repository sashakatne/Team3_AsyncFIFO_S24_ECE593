# Legacy fifo2 standalone regression.
#
# fifo2 is a historical async-compare FIFO variant.  This run keeps it separate
# from async_fifo4 because both standalone testbenches intentionally use a top
# module named `top`.

if {[file exists work]} {
  vdel -all
}
vlib work

vlog -source -lint async_fifo2.sv
vlog -source -lint async_fifo2_tb.sv

vopt top -o fifo2_optimized +acc
vsim fifo2_optimized

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all
