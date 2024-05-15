import async_fifo_pkg::*;

class environment;
    
//Instantiate Generator and Driver
generator gen;
driver driv;
monitor mon;
scoreboard scb;
  
//Instantiate Communication between Generator and Driver
mailbox gen2driv;
mailbox mon2scb;
  
event driv2gen;
  
virtual intf vif;

int no_of_transactions;

function new(virtual intf vif);
	this.vif = vif;
    gen2driv = new();
    mon2scb	= new();
    gen	= new(gen2driv, driv2gen);
    driv = new (vif,gen2driv);
    mon = new (vif, mon2scb);
    scb	= new (mon2scb);
endfunction
  
 //reset task
task pre_env();
	driv.reset();
endtask
    
//Generate and Drive
task test();

	$display("********************************");
	$display("------Bursts requested %0d-------",gen.trans_count);
    $display("********************************");
    $display("********************************");
    
    gen.main();
	driv.main();
    mon.main();
	scb.main();

endtask

task post_env();
	$display("IN POST TEST");
    wait(driv2gen.triggered);
    $display("1 DONE");
    wait(gen.trans_count == driv.no_trans);
    $display("2 DONE");
    wait (gen.trans_count == scb.no_trans);
    $display("3 DONE");
endtask
    
//task run
task run();
	pre_env();
    for (int i = 0; i < no_of_transactions; i++) 
	begin
    	test(); // Call the original drive task
    end
    //post_env();
    $finish;
endtask
        
endclass
