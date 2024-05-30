import uvm_pkg::*;
`include "uvm_macros.svh"
`include "async_fifo_interface.sv"

`ifdef BASE_TEST
    `include "async_fifo_test.sv"
`else
    `include "async_fifo_testrand.sv"
`endif

module tb_top;

	parameter WCLK_PERIOD = 12.5;
	parameter RCLK_PERIOD = 20;

	bit rclk,wclk,rrst,wrst;

	always #(WCLK_PERIOD/2) wclk = ~wclk;
	always #(RCLK_PERIOD/2) rclk = ~rclk;
  
  intf intf (wclk,rclk,wrst,rrst);
    
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
    wclk=0;
    rclk=0;
    wrst =0;
    rrst=0;
    intf.rinc=0;
    intf.winc=0;
    #1;
    rrst =1;
    wrst=1;
  end

    `include "async_fifo_coverage.sv"
    FIFO_coverage fifo_coverage_inst;
    initial begin
      fifo_coverage_inst = new();
      forever begin @(posedge wclk or posedge rclk)
        fifo_coverage_inst.sample();
      end
    end 

endmodule
