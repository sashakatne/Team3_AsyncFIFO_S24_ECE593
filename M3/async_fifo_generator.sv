class generator;

rand transaction trans;
int trans_count;
event driv2gen;
  
mailbox gen2driv;

function new(mailbox gen2driv, event driv2gen); 
	this.gen2driv = gen2driv;
    this.driv2gen = driv2gen;
endfunction

task main();
	
	repeat (trans_count) 
	begin         
		trans = new(); 
		if(!trans.randomize()) 
		$fatal ("Transaction randomization Failed");
		gen2driv.put(trans);
    end
    ->driv2gen;
endtask

endclass
