# Focused flag-threshold waveform run for async_fifo4.sv.
#
# Use this when debugging half/full/empty timing.  The generated
# flag_threshold.vcd is intentionally consumed by make_flag_debug_waveforms.py
# rather than committed directly.

if {[file exists work]} {
  vdel -all
}
vlib work

vlog -source -lint async_fifo4.sv
vlog -source -lint flag_threshold_tb.sv

vopt flag_threshold_tb -o flag_threshold_optimized +acc
vsim flag_threshold_optimized

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all
