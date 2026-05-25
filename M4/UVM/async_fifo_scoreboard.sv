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
int write_count;
int read_count;
int error_count;
  
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
	write_count++;
endfunction

function void write_port_b(transaction_read txr);

parameter DATA_SIZE = 8;
logic [DATA_SIZE-1:0] popped_wData;
  
	if (tw.size() > 0) 
	begin
		popped_wData = tw.pop_front().wData;
		read_count++;
    
		if (txr.rData === popped_wData)
			`uvm_info("ASYNC_FIFO_SCOREBOARD", $sformatf("PASSED Expected Data: %0h --- DUT Read Data: %0h", popped_wData, txr.rData), UVM_HIGH)
		else
		begin
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
  
endtask

function void final_phase(uvm_phase phase);
	super.final_phase(phase);
	$display("");
	$display("==================== SCOREBOARD SUMMARY ====================");
	$display("  Writes observed       : %0d", write_count);
	$display("  Reads  observed       : %0d", read_count);
	$display("  Residual expected_q   : %0d", tw.size());
	$display("  Mismatches / errors   : %0d", error_count);
	if (error_count == 0)
		$display("  Verdict: *** PASSED ***");
	else
		$display("  Verdict: *** FAILED ***");
	$display("============================================================");
endfunction
  
endclass
