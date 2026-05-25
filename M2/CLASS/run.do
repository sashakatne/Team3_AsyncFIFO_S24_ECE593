# 'catch {}' so a fresh checkout (no work/ yet) doesn't fail on vdel.
catch {vdel -all}
vlib work

vlog -source -lint async_fifo.sv
vlog -source -lint async_fifo_package.sv
vlog -source -lint aysnc_fifo_interface.sv
vlog -source -lint async_fifo_top.sv
vlog -source -lint async_fifo_test.sv

# Instrument code coverage on the DUT only (statement, branch, FEC, condition).
# Matches the M1/ConventionalTB pattern -- never broaden to the testbench.
vopt async_fifo_top -o top_optimized +acc +cover=sbfec+asynchronous_fifo(rtl).
vsim top_optimized -coverage

set NoQuitOnFinish 1
onbreak {resume}
log /* -r

run -all

coverage save async_fifo.ucdb
vcover report async_fifo.ucdb
vcover report async_fifo.ucdb -cvg -details
