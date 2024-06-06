package fifo_pkg;

	import uvm_pkg::*;
    `include "uvm_macros.svh"
	
    // Parameters for FIFO configuration
	parameter DATA_SIZE = 8, ADDR_SIZE = 6;
	parameter WCLK_PERIOD = 12.5;  // 80 MHz
	parameter RCLK_PERIOD = 20;    // 50 MHz
	
	// Parameters for the testbench	
	parameter TX_COUNT_WR = 2000;
	parameter TX_COUNT_RD = 2000;

	parameter RESET_PERIOD = TX_COUNT_WR * 10;

	parameter READ_DELAY_CLKS = 10;
	parameter WRITE_DELAY_CLKS = 10;

	`include "async_fifo_seq_item.sv"
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
