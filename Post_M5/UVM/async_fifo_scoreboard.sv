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
	transaction_read tr[$];     

	virtual intf vif;
	int w_count;
	int r_count;
	
	function new(string name,uvm_component parent);
		super.new(name,parent);
		w_count = 0;
		r_count = 0;
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
		w_count++;
		// $display ("\t Scoreboard wData = %0h", txw.wData);
		assert(!$isunknown(txw.wData)) else
			`uvm_error("ASSERTION ERROR", "Write Data is unknown")
	endfunction

	function void write_port_b(transaction_read txr);
		transaction_write popped_write_transaction;
		logic [DATA_SIZE-1:0] popped_wData;
		logic popped_wFull;
		logic popped_wHalfFull;

		assert(!$isunknown(txr.rData)) else
			`uvm_error("ASSERTION ERROR", "Read Data is unknown")
		
		if ((tw.size() > 0) && (tw.size() < 2**ADDR_SIZE-1))
			begin
				popped_write_transaction = tw.pop_front();
				popped_wData = popped_write_transaction.wData;
				popped_wFull = popped_write_transaction.wFull;
				popped_wHalfFull = popped_write_transaction.wHalfFull;
				$display("***** Queue Size: %0d *****", tw.size());
				check_flags(popped_wFull, txr.rEmpty, popped_wHalfFull, txr.rHalfEmpty);
				r_count++;
				if (txr.rData === popped_wData)
					`uvm_info("ASYNC_FIFO_SCOREBOARD", $sformatf("PASSED Expected Data: %0h --- DUT Read Data: %0h", popped_wData, txr.rData), UVM_MEDIUM)
				else
					`uvm_error("ASYNC_FIFO_SCOREBOARD", $sformatf("ERROR Expected Data: %0h Does not match DUT Read Data: %0h", popped_wData, txr.rData))
			end     
	endfunction

	task w_reset();
		tw.delete();
		w_count = 0;
		r_count = 0;
		$display("Scoreboard w queue has been flushed due to reset.");
	endtask

	function void check_flags(logic wFull, logic rEmpty, logic wHalfFull, logic rHalfEmpty);
		int fifo_count = w_count - r_count;
		if (fifo_count > 2**ADDR_SIZE)
			begin
				`uvm_info("SCOREBOARD", "FIFO IS FULL", UVM_MEDIUM)
				assert(wFull) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Full flag is not set when FIFO is full (w_count: %0d, r_count: %0d)", w_count, r_count))
			end 
		else
			begin
				assert(!wFull) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Full flag is set when FIFO is not full (w_count: %0d, r_count: %0d)", w_count, r_count))
			end

		if (fifo_count == 1)
			begin
				`uvm_info("SCOREBOARD", "FIFO IS EMPTY", UVM_MEDIUM)
				assert(rEmpty) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Empty flag is not set when FIFO is empty (w_count: %0d, r_count: %0d)", w_count, r_count))
			end
		else
			begin
				assert(!rEmpty) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Empty flag is set when FIFO is not empty (w_count: %0d, r_count: %0d)", w_count, r_count))
			end

		// Need to update this part
		// if (fifo_count > ((2**(ADDR_SIZE-1))-1))
		// 	begin
		// 		`uvm_info("SCOREBOARD", "FIFO IS HALF FULL", UVM_MEDIUM)
		// 		assert(wHalfFull) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Full flag is not set when FIFO is half full (w_count: %0d, r_count: %0d)", w_count, r_count))
		// 	end
		// else
		// 	begin
		// 		assert(!wHalfFull) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Full flag is set when FIFO is not half full (w_count: %0d, r_count: %0d)", w_count, r_count))
		// 	end

		// if (fifo_count < ((2**(ADDR_SIZE-1))+1))
		// 	begin
		// 		`uvm_info("SCOREBOARD", "FIFO IS HALF EMPTY", UVM_MEDIUM)
		// 		assert(rHalfEmpty) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Empty flag is not set when FIFO is half empty (w_count: %0d, r_count: %0d)", w_count, r_count))
		// 	end
		// else
		// 	begin
		// 		assert(!rHalfEmpty) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Empty flag is set when FIFO is not half empty (w_count: %0d, r_count: %0d)", w_count, r_count))
		// 	end
	endfunction
		
	task run_phase(uvm_phase phase);
		super.run_phase(phase); 
	endtask
  
endclass
