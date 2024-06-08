module top;

parameter DATA_SIZE = 8;
parameter ADDR_SIZE = 6;
parameter WCLK_PERIOD = 12.5;
parameter RCLK_PERIOD = 20;
parameter BURST_SIZE = 120;
parameter DEPTH = 64;

wire [DATA_SIZE-1:0] rData;
wire wFull, rEmpty;
reg [DATA_SIZE-1:0] wData;
reg winc, wclk, wrst;
reg rinc, rclk, rrst;
wire wHalfFull, rHalfEmpty;
bit error_flag = '0;
integer write_count = 0; // Counter to keep track of the number of writes
integer read_count = 0; // Counter to keep track of the number of reads

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
    wrst = '0;
    winc = '0;

    wData = '0;

    rclk = '0;
    rrst = '0;
    rinc = '0;

    // Reset
    #(WCLK_PERIOD*2) wrst = '1; rrst = '1;

    // Wait for some cycles
    repeat(8) @(posedge wclk);

    // Write operations
    repeat(BURST_SIZE) begin
        @(negedge wclk) begin
            if (!wFull) begin
                wData = $urandom;
                wdata_q.push_back(wData);
                winc = '1;
                write_count = write_count + 1;
            end else begin
                winc = '0;
            end
        end
        @(negedge wclk) begin
            // Check if half_full flag is asserted correctly
            if (write_count > ((DEPTH / 2) + 1) && !wHalfFull) begin
                $error("Time = %0t: wHalfFull flag not asserted as expected", $time);
            end
            // Check if full flag is asserted correctly
            if (write_count > DEPTH && !wFull) begin
                $error("Time = %0t: wFull flag not asserted as expected", $time);
            end
        end
    end

    // Wait for some cycles
    repeat(8) @(posedge wclk);

    // Read operations
    repeat(BURST_SIZE) begin
        @(negedge rclk) begin
            if (!rEmpty && rinc) begin
                wdata = wdata_q.pop_front();
                if(rData !== wdata) begin
                    $error("Time = %0t: Comparison Failed: expected wr_data = %h, rd_data = %h", $time, wdata, rData);
                    error_flag = '1;
                end else begin
                    $display("Time = %0t: Comparison Passed: wr_data = %h and rd_data = %h", $time, wdata, rData);
                end
                read_count = read_count + 1;
                // Check if half_empty flag is asserted correctly
                if (read_count > ((DEPTH / 2) + 1) && !rHalfEmpty) begin
                    $error("Time = %0t: rHalfEmpty flag not asserted at read_count = %0d", $time, read_count);
                    error_flag = '1;
                end
                // Check if empty flag is asserted correctly
                if (read_count > DEPTH && !rEmpty) begin
                    $error("Time = %0t: rEmpty flag not asserted at read_count = %0d", $time, read_count);
                    error_flag = '1;
                end
            end
        end
        @(negedge rclk) begin
            if (!rEmpty) begin
                rinc = '1;
            end else begin
                rinc = '0;
            end
        end
    end

    if (error_flag) begin
        $display("*** FAILED ***");
    end else begin
        $display("*** PASSED ***");
    end

    $finish;

end

initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
end
endmodule
