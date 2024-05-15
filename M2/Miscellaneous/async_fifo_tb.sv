module top;

  parameter DATA_WIDTH = 8;
  parameter WCLK_PERIOD = 12.5;
  parameter RCLK_PERIOD = 20;
  parameter BURST_SIZE = 120;
  parameter NUM_BURSTS = 30;

  wire [DATA_WIDTH-1:0] data_out;
  wire full;
  wire empty;
  reg [DATA_WIDTH-1:0] data_in;
  reg w_en, wclk, wrst_n;
  reg r_en, rclk, rrst_n;
  wire half_full, half_empty;
  bit error_flag = '0;

  // Queue to push data_in
  reg [DATA_WIDTH-1:0] wdata_q[$], wdata;

  asynchronous_fifo uut (wclk, wrst_n, rclk, rrst_n, w_en, r_en, data_in, data_out, full, empty, half_full, half_empty);

  always #(WCLK_PERIOD/2) wclk = ~wclk;
  always #(RCLK_PERIOD/2) rclk = ~rclk;
  
  initial begin
    wclk = '0; wrst_n = '0;
    w_en = '0;
    data_in = 0;
    
    repeat(40) @(posedge wclk);
    wrst_n = '1;

    repeat(NUM_BURSTS) begin
      for (int i=0; i<BURST_SIZE; i++) begin
        @(posedge wclk iff !full);
        // w_en = '1;
        w_en = (i%2 == 0) ? '1 : '0;
        if (w_en) begin
          data_in = $urandom;
          wdata_q.push_back(data_in);
        end
      end
      // w_en = '0;
    end
  end

  initial begin
    rclk = '0; rrst_n = '0;
    r_en = '0;

    repeat(80) @(posedge rclk);
    rrst_n = '1;

    repeat(NUM_BURSTS) begin
      for (int i=0; i<BURST_SIZE; i++) begin
        @(posedge rclk iff !empty);
        // r_en = '1;
        r_en = (i%2 == 0) ? '1 : '0;
        if (r_en) begin
          wdata = wdata_q.pop_front();
          if(data_out !== wdata) begin
            $error("Time = %0t: Comparison Failed: expected wr_data = %h, rd_data = %h", $time, wdata, data_out);
            error_flag = '1;
          end
          else $display("Time = %0t: Comparison Passed: wr_data = %h and rd_data = %h",$time, wdata, data_out);
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

  initial begin 
    $dumpfile("dump.vcd"); $dumpvars;
  end

endmodule