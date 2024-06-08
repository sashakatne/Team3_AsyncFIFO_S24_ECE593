module top;

  parameter DATA_SIZE = 8;
  parameter ADDR_SIZE = 6;
  parameter WCLK_PERIOD = 12.5;
  parameter RCLK_PERIOD = 20;
  parameter BURST_SIZE = 420;
  parameter NUM_BURSTS = 2;
  parameter FIFO_DEPTH = 1 << ADDR_SIZE;

  wire [DATA_SIZE-1:0] rData;
  wire wFull;
  wire rEmpty;
  reg [DATA_SIZE-1:0] wData;
  bit winc, wclk, wrst;
  bit rinc, rclk, rrst;
  wire wHalfFull, rHalfEmpty;
  bit error_flag = '0;

  int w_count;
  int r_count;


  // Queue to push data_in
  reg [DATA_SIZE-1:0] wdata_q[$], wdata;

  asynchronous_fifo #(DATA_SIZE, ADDR_SIZE) DUT (
    .winc(winc), .wclk(wclk), .wrst(wrst),
    .rinc(rinc), .rclk(rclk), .rrst(rrst),
    .wData(wData), .rData(rData),
    .wFull(wFull), .rEmpty(rEmpty),
    .wHalfFull(wHalfFull), .rHalfEmpty(rHalfEmpty)
  );

  always #(WCLK_PERIOD/2) wclk = ~wclk;
  always #(RCLK_PERIOD/2) rclk = ~rclk;

  initial begin

  wclk = '0;
  rclk = '0;
  wrst = '0;
  rrst = '0;
  
  winc = '0;
  rinc = '0;
  wData = '0;
  w_count = 0; r_count = 0;
  
  repeat(40) @(posedge wclk);
  wrst = '1; rrst = '1;

  end

  initial begin

    repeat(80) @(posedge wclk);

    repeat(NUM_BURSTS) begin
      for (int i=0; i<BURST_SIZE; i++) begin
        @(negedge wclk);
        winc = $urandom % 2;
        if (winc && !wFull) begin
          wData = $urandom;
          // wData = i;
          wdata_q.push_back(wData);
          // $display("Written data: %0d, Write count: %0d", wData, w_count);
          w_count++;
        end
      end
    end

  end

  initial begin

    repeat(80) @(posedge wclk);

    repeat(NUM_BURSTS) begin
      for (int i=0; i<BURST_SIZE; i++) begin
        rinc = $urandom % 2;
        @(negedge rclk) begin
          if (rinc && !rEmpty) begin
            compare_data();
            r_count++;
          end
        end
      end
    end

    if (error_flag) begin
        $display("*** FAILED ***");
    end else begin
        $display("*** PASSED ***");
    end

    repeat(10) @(posedge rclk);
    $finish;

  end

  // Task to compare data
  task compare_data;
    begin
      wdata = wdata_q.pop_front();
      if (rData !== wdata) begin
        // $display("Queue size: %0d", wdata_q.size());
        // $display("Read count: %0d, Write count: %0d", r_count, w_count);
        $error("Time = %0t: Comparison Failed: expected wr_data = %0d, rd_data = %0d", $time, wdata, rData);
        error_flag = '1;
      end
      // else begin
      //   $display("Read data: %0d, Read count: %0d", rData, r_count);
      // end
    end
  endtask

  // Task to check wFull flag
  task check_wFull;
    begin
      @(negedge wclk);
      if (wFull && wdata_q.size() != FIFO_DEPTH) begin
        $error("Time = %0t: wFull flag asserted incorrectly. Queue size: %0d", $time, wdata_q.size());
        error_flag = '1;
      end
      if (!wFull && wdata_q.size() == FIFO_DEPTH) begin
        $error("Time = %0t: wFull flag not asserted when queue is full. Queue size: %0d", $time, wdata_q.size());
        error_flag = '1;
      end
    end
  endtask

  // Task to check rEmpty flag
  task check_rEmpty;
    begin
      @(negedge rclk);
      if (rEmpty && wdata_q.size() != 0) begin
        $error("Time = %0t: rEmpty flag asserted incorrectly. Queue size: %0d", $time, wdata_q.size());
        error_flag = '1;
      end
      if (!rEmpty && wdata_q.size() == 0) begin
        $error("Time = %0t: rEmpty flag not asserted when queue is empty. Queue size: %0d", $time, wdata_q.size());
        error_flag = '1;
      end
    end
  endtask

  initial begin
    fork
      check_wFull();
      check_rEmpty();
    join
  end

  initial begin 
    $dumpfile("dump.vcd"); $dumpvars;
  end

endmodule
