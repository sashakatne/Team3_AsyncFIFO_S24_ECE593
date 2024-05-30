class scoreboard;

	parameter DATA_SIZE = 8;
	parameter ADDR_SIZE = 6;
	parameter DEPTH = 64;
	int no_trans; 
	logic [DATA_SIZE-1 : 0] fifo_mem [DEPTH-1 : 0];
	bit [ADDR_SIZE : 0] wr_count;
	bit [ADDR_SIZE : 0] rd_count;
	mailbox mon2scb;

	function new(mailbox mon2scb);
	this.mon2scb = mon2scb;
	foreach(fifo_mem[i])
	begin
		fifo_mem[i] = '0;
	end
	endfunction 

	virtual task main();
	begin   
	transaction trans_sb;
	mon2scb.get(trans_sb);
		
	if(trans_sb.winc)
	begin
		fifo_mem[wr_count] = trans_sb.wData;
		wr_count = wr_count + 1;
	end

	if(trans_sb.rinc)
	begin
		if(trans_sb.rData == fifo_mem[rd_count])
		begin
			$display("MATCH at address %0h - trans_sb.Data = %0h - Saved Data = %0h",rd_count, trans_sb.rData, fifo_mem[rd_count]);
			rd_count = rd_count + 1;
		end 
		else 
		begin
			$display("ERROR at address %0h - trans_sb.Data = %0h - Saved Data = %0h",rd_count, trans_sb.rData, fifo_mem[rd_count]);
		end
	end

	// Half Full & Half Empty checks
	if(trans_sb.wHalfFull)
	begin
		$display("FIFO is half full");
	end
	if(trans_sb.rHalfEmpty)
	begin
		$display("FIFO is half empty");
	end

	// Full & Empty checks
	if(trans_sb.wFull)
	begin
		$display("FIFO is full");
	end
	if(trans_sb.rEmpty)
	begin
		$display("FIFO is empty");
	end
	no_trans++;

	end
	endtask

endclass
