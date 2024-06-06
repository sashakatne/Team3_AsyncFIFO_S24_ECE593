import uvm_pkg::*;
`include "uvm_macros.svh"
import fifo_pkg::*;

class transaction_write extends uvm_sequence_item;
        `uvm_object_utils(transaction_write)

        rand bit [DATA_SIZE-1:0] wData;
        rand bit winc;
        bit wFull;
        bit wHalfFull;

        function new(string name = "transaction_write");
                super.new(name);
        endfunction
endclass

class transaction_read extends uvm_sequence_item;
        `uvm_object_utils(transaction_read)

        logic [DATA_SIZE-1:0] rData;
        rand bit rinc;
        bit rEmpty;
        bit rHalfEmpty;

        function new(string name = "transaction_read");
                super.new(name);
        endfunction
endclass
