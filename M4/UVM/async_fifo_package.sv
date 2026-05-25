package fifo_pkg;

	import uvm_pkg::*;
	`include "async_fifo_seq_item.sv"

	parameter DATA_SIZE = 8;
	parameter ADDR_SIZE = 6;
	parameter WCLK_PERIOD = 12.5;
	parameter RCLK_PERIOD = 20;
	parameter TX_COUNT_WR = 4000;
	parameter TX_COUNT_RD = 4000;

	`include "async_fifo_seq_test.sv"
	`include "async_fifo_seq_testrand.sv"

	`include "async_fifo_sequencer.sv"
	`include "async_fifo_driver.sv"
	`include "async_fifo_write_monitor.sv"
	`include "async_fifo_read_monitor.sv"
	`include "async_fifo_write_agent.sv"
	`include "async_fifo_read_agent.sv"
	`include "async_fifo_scoreboard.sv"

	
endpackage
