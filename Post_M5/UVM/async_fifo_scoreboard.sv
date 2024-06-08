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
	int fifo_count;
	
	function new(string name,uvm_component parent);
		super.new(name,parent);
		fifo_count = 0;
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
		fifo_count = fifo_count + 1;
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
		
		if ((tw.size() > 0) && (tw.size() < 2**ADDR_SIZE))
			begin
				popped_write_transaction = tw.pop_front();
				popped_wData = popped_write_transaction.wData;
				popped_wFull = popped_write_transaction.wFull;
				popped_wHalfFull = popped_write_transaction.wHalfFull;
				// $display("***** Queue Size: %0d *****", tw.size());
				// $display("***** Flag Status: wFull=%0h, wHalfFull=%0h, rEmpty=%0h, rHalfEmpty=%0h *****", popped_wFull, popped_wHalfFull, txr.rEmpty, txr.rHalfEmpty);
				check_flags(popped_wFull, txr.rEmpty, popped_wHalfFull, txr.rHalfEmpty);
				fifo_count = fifo_count - 1;
				if (txr.rData === popped_wData)
					`uvm_info("ASYNC_FIFO_SCOREBOARD", $sformatf("PASSED Expected Data: %0h --- DUT Read Data: %0h", popped_wData, txr.rData), UVM_MEDIUM)
				else
					`uvm_error("ASYNC_FIFO_SCOREBOARD", $sformatf("ERROR Expected Data: %0h Does not match DUT Read Data: %0h", popped_wData, txr.rData))
			end     
	endfunction

	task w_reset();
		tw.delete();
		fifo_count = 0;
		$display("Scoreboard w queue has been flushed due to reset.");
	endtask

	function void check_flags(logic wFull, logic rEmpty, logic wHalfFull, logic rHalfEmpty);
		if (fifo_count > 2**ADDR_SIZE)
			begin
				`uvm_info("SCOREBOARD", "FIFO IS FULL", UVM_MEDIUM)
				assert(wFull) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Full flag is not set when FIFO is full (fifo_count: %0d)", fifo_count))
			end 
		else
			begin
				assert(!wFull) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Full flag is set when FIFO is not full (fifo_count: %0d)", fifo_count))
			end

		if (fifo_count == 1)
			begin
				`uvm_info("SCOREBOARD", "FIFO IS EMPTY", UVM_MEDIUM)
				assert(rEmpty) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Empty flag is not set when FIFO is empty (fifo_count: %0d)", fifo_count))
			end
		else
			begin
				assert(!rEmpty) else
					`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Empty flag is set when FIFO is not empty (fifo_count: %0d)", fifo_count))
			end

		// if (fifo_count > 2**(ADDR_SIZE-1))
		// 	begin
		// 		assert(wHalfFull) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Full flag is not set when FIFO is half full (fifo_count: %0d)", fifo_count))
		// 	end
		// else
		// 	begin
		// 		assert(!wHalfFull) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Full flag is set when FIFO is not half full (fifo_count: %0d)", fifo_count))
		// 	end

		// if (fifo_count < 2**(ADDR_SIZE-1))
		// 	begin
		// 		assert(rHalfEmpty) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Empty flag is not set when FIFO is half empty (fifo_count: %0d)", fifo_count))
		// 	end
		// else
		// 	begin
		// 		assert(!rHalfEmpty) else
		// 			`uvm_error("SCOREBOARD", $sformatf("ASSERTION ERROR: FIFO Half Empty flag is set when FIFO is not half empty (fifo_count: %0d)", fifo_count))
		// 	end
	endfunction
		
	task run_phase(uvm_phase phase);
		super.run_phase(phase); 
	endtask
  
endclass
