import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

class write_monitor extends uvm_monitor;
`uvm_component_utils(write_monitor) 
 
virtual intf vif;
transaction_write txw;

uvm_analysis_port#(transaction_write) port_write;

int trans_count_write;
int w_count;

function new (string name = "write_monitor", uvm_component parent);
super.new(name, parent);
`uvm_info("WRITE_MONITOR_CLASS", "Inside constructor",UVM_LOW)
endfunction

function void build_phase(uvm_phase phase);
super.build_phase(phase);
port_write = new("port_write", this);

     if (!uvm_config_db#(virtual intf)::get(this, "", "vif", vif)) begin
       `uvm_error("build_phase", "No virtual interface specified for this write_monitor instance")
     end
endfunction

function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
endfunction 
 
task run_phase(uvm_phase phase);
	super.run_phase(phase);

    	 fork
        	begin : write_monitor
            		forever @(negedge vif.wclk) begin
                	mon_write();
            		end
        	end

        	begin : write_completion
              wait (w_count == trans_count_write);
        	end
    	join

endtask
        
task mon_write;
     
  transaction_write txw;

   	if (vif.winc==1) begin
	
 	txw=transaction_write::type_id::create("txw");  
 	txw.winc = vif.winc;
  	txw.wData = vif.wData;
	$display ("\t Monitor winc = %0h \t wData = %0h \t w_count=%0d", txw.winc, txw.wData, w_count+1);
   	port_write.write(txw);
	w_count=w_count +1;
		 
	end
endtask
endclass