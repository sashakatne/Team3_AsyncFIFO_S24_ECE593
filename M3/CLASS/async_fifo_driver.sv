class driver;
    
	int no_trans;
	int write_count;

	generator gen;
	virtual intf drv_if;
	mailbox gen2driv;

	transaction trans2;

	//this function allows for communcation with mailbox and creates an interface
	function new(virtual intf drv_if, mailbox gen2driv);
		this.drv_if = drv_if;
		this.gen2driv = gen2driv;
	endfunction

	//reset when write or read reset
	task reset;
		$display("Reset Initiated");
		wait(drv_if.wrst || drv_if.rrst);
		drv_if.wData <= '0;
		drv_if.winc <= '0;
		drv_if.rinc <= '0;
		wait(!drv_if.wrst || drv_if.rrst);
		$display("Reset is Complete");
	endtask

	virtual task drive();
	begin 
		transaction trans1;
		drv_if.winc <= '0;
		drv_if.rinc <= '0;
		gen2driv.get(trans1);
	
		@(posedge drv_if.wclk);
		if(trans1.winc) 
			begin
				drv_if.winc <= trans1.winc;
				drv_if.wData <= trans1.wData;

				trans1.wFull = drv_if.wFull;
				trans1.wHalfFull = drv_if.wHalfFull;
				trans1.rEmpty = drv_if.rEmpty;
				trans1.rHalfEmpty = drv_if.rHalfEmpty;

				$display ("\t winc = %0h \t wData = %0h", trans1.winc, trans1.wData);
			end
		else 
			begin
				$display ("\t winc = %0h \t wData = %0h", trans1.winc, trans1.wData);
			end

		if(trans1.rinc)
			begin
				drv_if.rinc <= trans1.rinc;
				@(posedge drv_if.rclk);
				trans1.rData = drv_if.rData;

				trans1.wFull = drv_if.wFull;
				trans1.wHalfFull = drv_if.wHalfFull;
				trans1.rEmpty = drv_if.rEmpty;
				trans1.rHalfEmpty = drv_if.rHalfEmpty;

				$display ("\t rinc = %0h", trans1.rinc);
			end 
		else
			begin
				$display ("\t rinc = %0h", trans1.rinc);
			end
			
	end
	endtask   

	virtual task drive_write();
		begin

			// Loop for writing until the FIFO is full
			@(posedge drv_if.wclk);
			drv_if.winc <= '1;
			gen2driv.get(trans2); // Get a new transaction for writing
			drv_if.wData <= trans2.wData;

			trans2.wFull = drv_if.wFull;
			trans2.wHalfFull = drv_if.wHalfFull;
			trans2.rEmpty = drv_if.rEmpty;
			trans2.rHalfEmpty = drv_if.rHalfEmpty;

			$display ("\t winc = %0h \t wData = %0h", trans2.winc, trans2.wData);
			if (drv_if.wFull) begin
				drv_if.winc <= '0;

				trans2.wFull = drv_if.wFull;
				trans2.wHalfFull = drv_if.wHalfFull;
				trans2.rEmpty = drv_if.rEmpty;
				trans2.rHalfEmpty = drv_if.rHalfEmpty;

				$display ("FIFO is full");
			end
		end
	endtask

	virtual task drive_read();
		begin

			// Loop for reading until the FIFO is empty
			@(posedge drv_if.rclk);
			drv_if.rinc <= '1;
			trans2.rData = drv_if.rData;

			trans2.wFull = drv_if.wFull;
			trans2.wHalfFull = drv_if.wHalfFull;
			trans2.rEmpty = drv_if.rEmpty;
			trans2.rHalfEmpty = drv_if.rHalfEmpty;

			$display ("\t rinc = %0h \t rData = %0h", trans2.rinc, trans2.rData);
			if (drv_if.rEmpty) begin
				drv_if.rinc <= '0;

				trans2.wFull = drv_if.wFull;
				trans2.wHalfFull = drv_if.wHalfFull;
				trans2.rEmpty = drv_if.rEmpty;
				trans2.rHalfEmpty = drv_if.rHalfEmpty;

				$display ("FIFO is empty");
			end
		end
	endtask

	task  main();
		drive();
	endtask

	task  main_write();
		drive_write();
	endtask

	task  main_read();
		drive_read();
	endtask
         
endclass
