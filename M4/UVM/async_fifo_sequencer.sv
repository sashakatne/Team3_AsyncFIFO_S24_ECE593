import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

class write_sequencer extends uvm_sequencer #(transaction_write);
`uvm_component_utils(write_sequencer)

function new (string name = "write_sequencer", uvm_component parent);
super.new(name, parent);
`uvm_info("WRITE_SEQUENCER_CLASS", "Inside constructor",UVM_LOW)
endfunction

function void build_phase (uvm_phase phase);
super.build_phase(phase);
`uvm_info("WRITE_SEQUENCER_CLASS", "Build Phase",UVM_LOW)
endfunction

function void connect_phase (uvm_phase phase);
super.connect_phase(phase);
`uvm_info("WRITE_SEQUENCER_CLASS", "Connect Phase",UVM_LOW)
endfunction

endclass

class read_sequencer extends uvm_sequencer #(transaction_read);
`uvm_component_utils(read_sequencer)

function new (string name = "read_sequencer", uvm_component parent);
super.new(name, parent);
`uvm_info("READ_SEQUENCER_CLASS", "Inside constructor",UVM_LOW)
endfunction

function void build_phase (uvm_phase phase);
super.build_phase(phase);
`uvm_info("READ_SEQUENCER_CLASS", "Build Phase",UVM_LOW)
endfunction

function void connect_phase (uvm_phase phase);
super.connect_phase(phase);
`uvm_info("READ_SEQUENCER_CLASS", "Connect Phase",UVM_LOW)
endfunction

endclass

