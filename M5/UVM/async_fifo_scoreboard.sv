import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

`uvm_analysis_imp_decl(_port_a)
`uvm_analysis_imp_decl(_port_b)

int empty_count;

class fifo_scoreboard extends uvm_scoreboard;

	`uvm_component_utils(fifo_scoreboard)
	uvm_analysis_imp_port_a#(transaction_write,fifo_scoreboard) write_port;
	uvm_analysis_imp_port_b#(transaction_read,fifo_scoreboard) read_port; 

	transaction_write tw[$]; 
	transaction_read tr[$];     
	
	function new(string name,uvm_component parent);
		super.new(name,parent);
	endfunction  
				
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		write_port= new("write_port",this);
		read_port= new("read_port",this);  
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
	endfunction 
	
	function void write_port_a(transaction_write txw); 
		tw.push_back(txw);
		$display ("\t Scoreboard wData = %0h", txw.wData);
	endfunction

	function void write_port_b(transaction_read txr);
		logic [DATA_SIZE-1:0] popped_wData;
		empty_count = tw.size;
		
		if (tw.size() > 0) 
		begin
			popped_wData = tw.pop_front().wData;
			if (txr.rData === txr.rData)
				`uvm_info("ASYNC_FIFO_SCOREBOARD", $sformatf("PASSED Expected Data: %0h --- DUT Read Data: %0h", txr.rData, txr.rData), UVM_MEDIUM)
			else
				`uvm_error("ASYNC_FIFO_SCOREBOARD", $sformatf("ERROR Expected Data: %0h Does not match DUT Read Data: %0h", txr.rData, popped_wData))
		end     
	endfunction

	task compare_flags(); 

		if (tw.size > 2**ADDR_SIZE)
		begin
			`uvm_info("SCOREBOARD", "FIFO IS FULL", UVM_MEDIUM);
		end 
		if (empty_count == 1)
		begin
			`uvm_info("SCOREBOARD", "FIFO IS EMPTY", UVM_MEDIUM);
		end
	
	endtask
		
	task run_phase(uvm_phase phase);
		super.run_phase(phase); 
	endtask
  
endclass
