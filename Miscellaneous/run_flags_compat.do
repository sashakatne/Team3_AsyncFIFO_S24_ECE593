# Compatibility run for the original async_fifo4_tb2.sv entry point.
#
# The dedicated waveform run is run_flags.do.  This script simply proves the
# original tb2 filename now performs the same exact half/full/empty checks.

if {[file exists work]} {
  vdel -all
}
vlib work

vlog -source -lint async_fifo4.sv
vlog -source -lint async_fifo4_tb2.sv

vopt top -o flags_compat_optimized +acc
vsim flags_compat_optimized

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all
