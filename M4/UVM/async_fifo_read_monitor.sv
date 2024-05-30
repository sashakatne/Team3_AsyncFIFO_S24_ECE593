import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

class read_monitor extends uvm_monitor;
`uvm_component_utils(read_monitor) 
 
virtual intf vif;
transaction_read txr;
bit write_complete_flag;

uvm_analysis_port#(transaction_read) port_read;

int trans_count_read;
int r_count;

function new (string name = "read_monitor", uvm_component parent);
super.new(name, parent);
`uvm_info("READ_MONITOR_CLASS", "Inside constructor",UVM_LOW)
endfunction

function void build_phase(uvm_phase phase);
super.build_phase(phase);
port_read = new("port_read", this);

     if (!uvm_config_db#(virtual intf)::get(this, "", "vif", vif)) begin
       `uvm_error("build_phase", "No virtual interface specified for this read_monitor instance")
     end
endfunction

function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
endfunction 
 

task run_phase(uvm_phase phase);
	super.run_phase(phase);
			fork 
				begin : read_monitor
	       				forever @(negedge vif.rclk)begin
        					mon_read();
    					end
				end
				begin

                  wait (r_count == trans_count_read);
                  
				end
			join_any
        
		
endtask
 
       
task mon_read;
     
  transaction_read txr;
if (vif.rinc==1)begin
txr=transaction_read::type_id::create("txr"); 
		fork
			begin
				@(negedge vif.rclk);
				txr.rData = vif.rData; 
              $display ("\t Monitor rinc = 1 \t rData = %0h \t \t rcount=%0d",  txr.rData, r_count+1);

   				port_read.write(txr);
				r_count= r_count +1;
			end
		join_none	
  	end
endtask
endclass
