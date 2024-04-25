module top;

    // Parameters
    localparam DSIZE = 8; // Data size
    localparam ASIZE = 6; // Address size
    localparam CLK_PERIOD_WR = 12.5; // Write clock period in ns
    localparam CLK_PERIOD_RD = 20; // Read clock period in ns

    // Testbench Signals
    reg [DSIZE-1:0] wdata;
    reg winc, wclk, wrst_n;
    reg rinc, rclk, rrst_n;
    wire [DSIZE-1:0] rdata;
    wire wfull, rempty;

    // Instantiate the Unit Under Test (UUT)
    fifo2 #(
        .DSIZE(DSIZE),
        .ASIZE(ASIZE)
    ) uut (
        .rdata(rdata),
        .wfull(wfull),
        .rempty(rempty),
        .wdata(wdata),
        .winc(winc),
        .wclk(wclk),
        .wrst_n(wrst_n),
        .rinc(rinc),
        .rclk(rclk),
        .rrst_n(rrst_n)
    );

    // Clock generation
    always #(CLK_PERIOD_WR/2) wclk = ~wclk;
    always #(CLK_PERIOD_RD/2) rclk = ~rclk;

    // Test sequence
    initial begin
        // Initialize
        wclk = 0;
        rclk = 0;
        wrst_n = 0;
        rrst_n = 0;
        winc = 0;
        rinc = 0;
        wdata = 0;

        // Reset
        #(CLK_PERIOD_WR*2) wrst_n = 1;
        #(CLK_PERIOD_RD*2) rrst_n = 1;

        // Write 120 items
        repeat (120) begin
            @(posedge wclk) begin
                if (!wfull) begin
                    wdata <= wdata + 1;
                    winc <= 1;
                end else begin
                    winc <= 0;
                end
            end
        end

        // Wait for some cycles
        #(CLK_PERIOD_WR*10);

        // Read items
        repeat (120) begin
            @(posedge rclk) begin
                if (!rempty) begin
                    rinc <= 1;
                end else begin
                    rinc <= 0;
                end
            end
        end

        // Complete
        #(CLK_PERIOD_RD*10);
        $finish;
    end

    // Monitor
    initial begin
        $monitor("Time=%t, wdata=%d, rdata=%d, wfull=%b, rempty=%b", $time, wdata, rdata, wfull, rempty);
    end

endmodule
   
