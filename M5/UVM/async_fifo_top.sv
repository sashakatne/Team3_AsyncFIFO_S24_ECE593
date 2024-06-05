import uvm_pkg::*;
`include "uvm_macros.svh"
`include "async_fifo_interface.sv"

`ifdef BASE_TEST
    `include "async_fifo_test.sv"
`else
    `include "async_fifo_testrand.sv"
`endif

module tb_top;

	parameter WCLK_PERIOD = 12.5; // 80 MHz
	parameter RCLK_PERIOD = 20;  // 50 MHz

  parameter RESET_PERIOD = 40000; // 25 KHz

	bit rclk, wclk, rrst, wrst;

	always #(WCLK_PERIOD/2) wclk = ~wclk;
	always #(RCLK_PERIOD/2) rclk = ~rclk;

  always #(RESET_PERIOD) wrst = ~wrst;
  always #(RESET_PERIOD) rrst = ~rrst;
  
  intf intf (wclk, rclk, wrst, rrst);
    
  asynchronous_fifo DUT (.wData(intf.wData),
              .wFull(intf.wFull),
              .wHalfFull(intf.wHalfFull),
              .rEmpty(intf.rEmpty),
              .rHalfEmpty(intf.rHalfEmpty),
              .winc(intf.winc),
              .rinc(intf.rinc),
              .wclk(intf.wclk),
              .rclk(intf.rclk),
              .rrst(intf.rrst),
              .wrst(intf.wrst),
              .rData(intf.rData));
  
  initial 
  begin
    uvm_config_db#(virtual intf)::set(null, "*","vif", intf);
    `uvm_info("tb_top","uvm_config_db set for uvm_tb_top", UVM_LOW);
  end

	initial 
	begin
		`ifdef BASE_TEST
			run_test("fifo_base_test");
		`else
			run_test("fifo_random_test");
		`endif
	end

  initial 
  begin
    $display("Time: %0t: Starting the FIFO testbench...", $time);
    wclk = '0;
    rclk = '0;
    wrst = '0;
    rrst = '0;
    intf.rinc ='0;
    intf.winc = '0;
    #1;
    rrst = '1;
    wrst = '1;
  end

  `include "async_fifo_coverage.sv"
  cg_fifo cg_fifo_inst;
  cg_half_full_empty cg_half_full_empty_inst;
  cg_data_integrity cg_data_integrity_inst;
  cg_data_patterns cg_data_patterns_inst;
  cg_burst_ops cg_burst_ops_inst;
  cg_idle_cycles cg_idle_cycles_inst;
  cg_high_freq cg_high_freq_inst;
  cg_abrupt_change cg_abrupt_change_inst;
  cg_throughput cg_throughput_inst;

  initial begin
    cg_fifo_inst = new();
    cg_half_full_empty_inst = new();
    cg_data_integrity_inst = new();
    cg_data_patterns_inst = new();
    cg_burst_ops_inst = new();
    cg_idle_cycles_inst = new();
    cg_high_freq_inst = new();
    cg_abrupt_change_inst = new();
    cg_throughput_inst = new();
    forever begin @(posedge wclk or posedge rclk)
      cg_fifo_inst.sample();
      cg_half_full_empty_inst.sample();
      cg_data_integrity_inst.sample();
      cg_data_patterns_inst.sample();
      cg_burst_ops_inst.sample();
      cg_idle_cycles_inst.sample();
      cg_high_freq_inst.sample();
      cg_abrupt_change_inst.sample();
      cg_throughput_inst.sample();
    end
  end 

endmodule

