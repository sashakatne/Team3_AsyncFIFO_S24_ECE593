
vdel -all

vlog -source -lint async_fifo.sv
vlog -source -lint async_fifo_package.sv
vlog -source -lint async_fifo_interface.sv
vlog -source -lint async_fifo_top.sv
vlog -source -lint async_fifo_test.sv

vsim  async_fifo_top


vsim -coverage async_fifo_top -voptargs="+cover=bcesfx"
vlog -cover bcst async_fifo.sv
vsim -coverage async_fifo_top -do "run -all; exit"
run -all
coverage report -code bcesft
coverage report -assert -binrhs -details -cvg
vcover report -html coverage_results
coverage report -codeAll

