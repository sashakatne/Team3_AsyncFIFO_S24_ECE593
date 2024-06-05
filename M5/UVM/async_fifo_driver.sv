import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

class write_driver extends uvm_driver#(transaction_write);
	`uvm_component_utils(write_driver)

	virtual intf intf_vi;
	transaction_write txw;
	int trans_count_write;

	function new (string name = "write_driver", uvm_component parent);
		super.new(name, parent);
		`uvm_info("WRITE_DRIVER_CLASS", "Inside constructor",UVM_LOW)
	endfunction

	function void build_phase (uvm_phase phase);
		super.build_phase(phase);
		`uvm_info("WRITE_DRIVER_CLASS", "Build Phase",UVM_LOW)
		if(!(uvm_config_db #(virtual intf)::get (this, "*", "vif", intf_vi))) 
		`uvm_error("WRITE_DRIVER_CLASS", "FAILED to get intf_vi from config DB")
	endfunction

	function void connect_phase (uvm_phase phase);
		super.connect_phase(phase);
		`uvm_info("WRITE_DRIVER_CLASS", "Connect Phase",UVM_LOW)
	endfunction

	task drive_write(transaction_write txw);
		@(posedge intf_vi.wclk);
		this.intf_vi.winc = txw.winc;
		this.intf_vi.wData = txw.wData;
	endtask

	task run_phase (uvm_phase phase);
		super.run_phase(phase);
		`uvm_info("WRITE_DRIVER_CLASS", "Inside Run Phase",UVM_LOW)
		this.intf_vi.wData <= '0;
		this.intf_vi.winc <= '0;

		repeat(WRITE_DELAY_CLKS) @(posedge intf_vi.wclk);
				
		for (integer i = 0; i < trans_count_write ; i++)
		begin
			txw=transaction_write::type_id::create("txw");
			seq_item_port.get_next_item(txw);
			// $display("DEBUG: Total write transactions= %0d", trans_count_write);
			// $display("DEBUG: FIFO full flag status= %0h", intf_vi.wFull);
			// wait(intf_vi.wFull == '0);
			drive_write(txw);
			seq_item_port.item_done();
		end
		@(posedge intf_vi.wclk);
		this.intf_vi.winc = '0;
	endtask

endclass

class read_driver extends uvm_driver#(transaction_read);
	`uvm_component_utils(read_driver)

	virtual intf intf_vi;
	transaction_read txr;
	int trans_count_read;

	function new (string name = "read_driver", uvm_component parent);
		super.new(name, parent);
		`uvm_info("READ_DRIVER_CLASS", "Inside constructor",UVM_LOW)
	endfunction

	function void build_phase (uvm_phase phase);
		super.build_phase(phase);
		`uvm_info("READ_DRIVER_CLASS", "Build Phase",UVM_LOW)
		if(!(uvm_config_db #(virtual intf)::get (this, "*", "vif", intf_vi))) 
		`uvm_error("READ_DRIVER_CLASS", "FAILED to get intf_vi from config DB")
	endfunction

	function void connect_phase (uvm_phase phase);
		super.connect_phase(phase);
		`uvm_info("READ_DRIVER_CLASS", "Connect Phase",UVM_LOW)
	endfunction

	task drive_read(transaction_read txr);
		@(posedge intf_vi.rclk);
		this.intf_vi.rinc = txr.rinc;
	endtask

	task run_phase (uvm_phase phase);
		super.run_phase(phase);
		`uvm_info("READ_DRIVER_CLASS", "Inside Run Phase",UVM_LOW)
		this.intf_vi.rinc <= '0;

		repeat(READ_DELAY_CLKS) @(posedge intf_vi.rclk);

		for (integer j = 0; j < trans_count_read; j++)
			begin
				txr=transaction_read::type_id::create("txr");	
				seq_item_port.get_next_item(txr);
				// $display("DEBUG: Total read transactions= %0d", trans_count_read);
				// $display("DEBUG: FIFO empty flag status= %0h", intf_vi.rEmpty);
				// wait(intf_vi.rEmpty == '0);
				drive_read(txr);
				seq_item_port.item_done();
			end
		@(posedge intf_vi.rclk);
		this.intf_vi.rinc = '0;
	endtask
endclass
