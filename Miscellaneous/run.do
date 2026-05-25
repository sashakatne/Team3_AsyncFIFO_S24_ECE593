# Main Miscellaneous standalone async_fifo4 data-ordering regression.
#
# This directory is not a UVM milestone, so the run is intentionally compact:
# compile the standalone RTL and procedural self-checking top, optimize with
# access enabled for VCD/debug, and run until the bench prints PASS/FAIL.

if {[file exists work]} {
  vdel -all
}
vlib work

vlog -source -lint async_fifo4.sv
vlog -source -lint async_fifo4_tb.sv

vopt top -o top_optimized +acc
vsim top_optimized

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all
