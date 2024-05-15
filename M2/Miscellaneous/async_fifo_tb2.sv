module top;

parameter DATA_WIDTH = 8;
parameter WCLK_PERIOD = 12.5;
parameter RCLK_PERIOD = 20;
parameter BURST_SIZE = 120;
parameter DEPTH = 64;

wire [DATA_WIDTH-1:0] data_out;
wire full, empty;
reg [DATA_WIDTH-1:0] data_in;
reg w_en, wclk, wrst_n;
reg r_en, rclk, rrst_n;
wire half_full, half_empty;
bit error_flag = '0;
integer write_count = 0; // Counter to keep track of the number of writes
integer read_count = 0; // Counter to keep track of the number of reads

// Queue to push data_in
reg [DATA_WIDTH-1:0] wdata_q[$], wdata;

asynchronous_fifo uut (
    .wclk(wclk), .wrst_n(wrst_n), .rclk(rclk), .rrst_n(rrst_n),
    .w_en(w_en), .r_en(r_en), .data_in(data_in), .data_out(data_out),
    .full(full), .empty(empty), .half_full(half_full), .half_empty(half_empty)
);

always #(WCLK_PERIOD/2) wclk = ~wclk;
always #(RCLK_PERIOD/2) rclk = ~rclk;

initial begin
    wclk = '0;
    wrst_n = '0;
    w_en = '0;

    data_in = '0;

    rclk = '0;
    rrst_n = '0;
    r_en = '0;

    // Reset
    #(WCLK_PERIOD*2) wrst_n = '1;
    #(RCLK_PERIOD*2) rrst_n = '1;

    // Write operations
    repeat(BURST_SIZE) begin
        @(posedge wclk) begin
            if (!full) begin
                data_in = $urandom;
                wdata_q.push_back(data_in);
                w_en = '1;
                write_count = write_count + 1;
            end else begin
                w_en = '0;
            end
        end
        @(negedge wclk) begin
            // Check if half_full flag is asserted correctly
            if (write_count > ((DEPTH / 2) + 1) && !half_full) begin
                $error("Time = %0t: half_full flag not asserted as expected", $time);
            end
            // Check if full flag is asserted correctly
            if (write_count > DEPTH && !full) begin
                $error("Time = %0t: full flag not asserted as expected", $time);
            end
        end
    end

    // Wait for some cycles
    repeat(8) @(posedge wclk);

    // Read operations
    repeat(BURST_SIZE) begin
        @(negedge rclk) begin
            if (!empty && r_en) begin
                wdata = wdata_q.pop_front();
                if(data_out !== wdata) begin
                    $error("Time = %0t: Comparison Failed: expected wr_data = %h, rd_data = %h", $time, wdata, data_out);
                    error_flag = '1;
                end else begin
                    $display("Time = %0t: Comparison Passed: wr_data = %h and rd_data = %h", $time, wdata, data_out);
                end
                read_count = read_count + 1;
                // Check if half_empty flag is asserted correctly
                if (read_count > ((DEPTH / 2) + 1) && !half_empty) begin
                    $error("Time = %0t: half_empty flag not asserted at read_count = %0d", $time, read_count);
                    error_flag = '1;
                end
                // Check if empty flag is asserted correctly
                if (read_count > DEPTH && !empty) begin
                    $error("Time = %0t: empty flag not asserted at read_count = %0d", $time, read_count);
                    error_flag = '1;
                end
            end
        end
        @(posedge rclk) begin
            if (!empty) begin
                r_en = '1;
            end else begin
                r_en = '0;
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