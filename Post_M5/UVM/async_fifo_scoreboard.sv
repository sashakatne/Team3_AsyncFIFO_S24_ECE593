import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

`uvm_analysis_imp_decl(_port_a)
`uvm_analysis_imp_decl(_port_b)

class fifo_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(fifo_scoreboard)
	uvm_analysis_imp_port_a#(transaction_write,fifo_scoreboard) write_port;
	uvm_analysis_imp_port_b#(transaction_read,fifo_scoreboard) read_port;

	transaction_write tw[$];
	virtual intf vif;
	int write_count;
	int read_count;
	int error_count;
	int reset_count;
	
	function new(string name,uvm_component parent);
		super.new(name,parent);
	endfunction  
				
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		write_port= new("write_port",this);
		read_port= new("read_port",this);  
		if (!uvm_config_db#(virtual intf)::get(this, "", "vif", vif))
			`uvm_error("build_phase", "No virtual interface specified for scoreboard")
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
	endfunction 
	
	function void write_port_a(transaction_write txw); 
		tw.push_back(txw);
		write_count++;
		if ($isunknown(txw.wData)) begin
			error_count++;
			`uvm_error("ASSERTION ERROR", "Write Data is unknown")
		end
	endfunction

	function void write_port_b(transaction_read txr);
		transaction_write popped_write_transaction;
		logic [DATA_SIZE-1:0] popped_wData;

		if ($isunknown(txr.rData)) begin
			error_count++;
			`uvm_error("ASSERTION ERROR", "Read Data is unknown")
		end
		
		if (tw.size() > 0) begin
			popped_write_transaction = tw.pop_front();
			popped_wData = popped_write_transaction.wData;
			read_count++;
			if (txr.rData === popped_wData)
				`uvm_info("ASYNC_FIFO_SCOREBOARD", $sformatf("PASSED Expected Data: %0h --- DUT Read Data: %0h", popped_wData, txr.rData), UVM_HIGH)
			else begin
				error_count++;
				`uvm_error("ASYNC_FIFO_SCOREBOARD", $sformatf("ERROR Expected Data: %0h Does not match DUT Read Data: %0h", popped_wData, txr.rData))
			end
		end
		else begin
			error_count++;
			`uvm_error("ASYNC_FIFO_SCOREBOARD", $sformatf("Read observed with empty expected queue; DUT Read Data: %0h", txr.rData))
		end
	endfunction
		
	task run_phase(uvm_phase phase);
		super.run_phase(phase);
		forever begin
			@(negedge vif.wrst or negedge vif.rrst);
			if (tw.size() != 0)
				`uvm_info("SCOREBOARD", $sformatf("Reset flushed %0d queued expected writes", tw.size()), UVM_LOW)
			tw.delete();
			reset_count++;
		end
	endtask

	function void final_phase(uvm_phase phase);
		super.final_phase(phase);
		$display("");
		$display("==================== SCOREBOARD SUMMARY ====================");
		$display("  Writes observed       : %0d", write_count);
		$display("  Reads  observed       : %0d", read_count);
		$display("  Reset flushes         : %0d", reset_count);
		$display("  Residual expected_q   : %0d", tw.size());
		$display("  Mismatches / errors   : %0d", error_count);
		if (error_count == 0)
			$display("  Verdict: *** PASSED ***");
		else
			$display("  Verdict: *** FAILED ***");
		$display("============================================================");
	endfunction
  
endclass
