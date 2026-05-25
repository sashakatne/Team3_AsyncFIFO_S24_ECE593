# 'catch {}' so a fresh checkout (no work/ yet) does not fail on vdel.
catch {vdel -all}
vlib work

vlog -source -lint async_fifo.sv
vlog -source -lint async_fifo_package.sv
vlog -source -lint async_fifo_interface.sv
vlog -source -lint async_fifo_top.sv
vlog -source -lint async_fifo_test.sv

# Instrument code coverage on the DUT only. Covergroup coverage from
# async_fifo_top is still collected by running vsim with -coverage.
vopt async_fifo_top -o top_optimized +acc +cover=sbfec+asynchronous_fifo(rtl).
vsim top_optimized -coverage

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all

coverage save async_fifo.ucdb
vcover report async_fifo.ucdb
vcover report async_fifo.ucdb -cvg -details
