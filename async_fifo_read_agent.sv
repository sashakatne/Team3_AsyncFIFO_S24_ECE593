 import uvm_pkg::*;
`include "uvm_macros.svh"
 import fifo_pkg::*;
 
class read_agent extends uvm_agent;
`uvm_component_utils(read_agent)


read_sequencer rs;
read_driver rd;
read_monitor rm;

function new (string name = "read_agent", uvm_component parent);
super.new(name, parent);
`uvm_info("READ_AGENT_CLASS", "Inside constructor",UVM_LOW);
endfunction

function void build_phase(uvm_phase phase);
super.build_phase(phase);
	
		rs = read_sequencer::type_id::create("rs", this);
		rd = read_driver::type_id::create("rd", this);
		rm = read_monitor::type_id::create("rm", this);

endfunction

function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
rd.seq_item_port.connect(rs.seq_item_export);

endfunction

task run_phase(uvm_phase phase);
super.run_phase(phase);
endtask
endclass
