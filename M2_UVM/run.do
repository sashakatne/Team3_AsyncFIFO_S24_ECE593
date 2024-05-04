
vdel -all
vlog -source -lint async_fifo.sv
vlog -source -lint async_fifo_package.sv
vlog -source -lint aysnc_fifo_interface.sv
vlog -source -lint async_fifo_top.sv
vlog -source -lint async_fifo_test.sv

vsim  async_fifo_top

#vsim -coverage top -voptargs="+cover=bcesfx"
#vlog -cover bcst async_fifo.sv
#vsim -coverage top -do "run -all; exit"
run -all
#coverage report -code bcesft
#vcover report -html coverage_results
#coverage report -codeAll


