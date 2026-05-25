`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Self-checking standalone testbench for the legacy fifo2 design.
//
// The FIFO under test has an asynchronous-read memory, so the expected read data
// is sampled before the read clock edge that advances the read pointer.  The
// test fills the FIFO, verifies that extra writes are blocked by `wfull`, drains
// every accepted word in order, and verifies that an extra read is blocked by
// `rempty`.
// -----------------------------------------------------------------------------

module top;

    localparam int DSIZE = 8;
    localparam int ASIZE = 6;
    localparam int DEPTH = 1 << ASIZE;
    localparam real CLK_PERIOD_WR = 12.5;
    localparam real CLK_PERIOD_RD = 20.0;

    logic [DSIZE-1:0] wdata;
    logic winc, wclk, wrst_n;
    logic rinc, rclk, rrst_n;
    wire [DSIZE-1:0] rdata;
    wire wfull, rempty;

    logic [DSIZE-1:0] expected_q[$];
    int accepted_writes;
    int accepted_reads;
    int blocked_writes;
    int blocked_reads;
    int error_count;

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

    always #(CLK_PERIOD_WR / 2.0) wclk = ~wclk;
    always #(CLK_PERIOD_RD / 2.0) rclk = ~rclk;

    task automatic record_error(input string msg);
        error_count++;
        $error("%s", msg);
    endtask

    task automatic apply_reset();
        wclk = 1'b0;
        rclk = 1'b0;
        wrst_n = 1'b0;
        rrst_n = 1'b0;
        winc = 1'b0;
        rinc = 1'b0;
        wdata = '0;
        accepted_writes = 0;
        accepted_reads = 0;
        blocked_writes = 0;
        blocked_reads = 0;
        error_count = 0;
        expected_q.delete();

        repeat (4) @(posedge wclk);
        wrst_n = 1'b1;
        repeat (4) @(posedge rclk);
        rrst_n = 1'b1;

        // Allow both independently-clocked flag pipelines to settle after reset
        // before issuing the first transfer.
        repeat (4) @(posedge wclk);
        repeat (4) @(posedge rclk);
    endtask

    task automatic write_attempt(input logic [DSIZE-1:0] data);
        bit pre_full;

        // Drive on the falling edge so the DUT samples stable stimulus on the
        // next rising edge.  `pre_full` models whether this request should be
        // accepted by the DUT at that edge.
        @(negedge wclk);
        winc = 1'b1;
        wdata = data;
        pre_full = wfull;

        @(posedge wclk);
        #1;
        if (!pre_full) begin
            expected_q.push_back(data);
            accepted_writes++;
        end else begin
            blocked_writes++;
        end
        winc = 1'b0;
    endtask

    task automatic read_attempt();
        bit pre_empty;
        logic [DSIZE-1:0] sampled_rdata;
        logic [DSIZE-1:0] expected;

        // fifo2 exposes the current read location through asynchronous memory
        // data.  Capture it before the read edge advances rptr.
        @(negedge rclk);
        rinc = 1'b1;
        pre_empty = rempty;
        sampled_rdata = rdata;

        @(posedge rclk);
        #1;
        if (!pre_empty) begin
            accepted_reads++;
            if (expected_q.size() == 0) begin
                record_error($sformatf("read accepted with empty expected queue, rdata=%0h", sampled_rdata));
            end else begin
                expected = expected_q.pop_front();
                if (sampled_rdata !== expected) begin
                    record_error($sformatf("data mismatch at read %0d: expected=%0h actual=%0h",
                                           accepted_reads, expected, sampled_rdata));
                end
            end
        end else begin
            blocked_reads++;
        end
        rinc = 1'b0;
    endtask

    task automatic finish_with_summary();
        $display("[SUMMARY fifo2] accepted_writes=%0d accepted_reads=%0d blocked_writes=%0d blocked_reads=%0d residual_q=%0d errors=%0d",
                 accepted_writes, accepted_reads, blocked_writes, blocked_reads, expected_q.size(), error_count);

        if (error_count == 0 && expected_q.size() == 0 && accepted_writes == DEPTH && accepted_reads == DEPTH &&
            blocked_writes > 0 && blocked_reads > 0) begin
            $display("*** PASSED ***");
            $finish;
        end

        $display("*** FAILED ***");
        $fatal(1, "fifo2 standalone self-check failed");
    endtask

    initial begin
        apply_reset();

        // Attempt more writes than the FIFO can hold.  Only the first DEPTH
        // requests should be accepted; later requests prove the full flag is
        // actually gating writes.
        for (int i = 0; i < DEPTH + 6; i++) begin
            write_attempt(DSIZE'(i + 1));
        end

        if (accepted_writes != DEPTH) begin
            record_error($sformatf("expected exactly %0d accepted writes, got %0d", DEPTH, accepted_writes));
        end
        if (wfull !== 1'b1) begin
            record_error($sformatf("wfull was not asserted after filling FIFO: wfull=%0b", wfull));
        end

        wait (rempty === 1'b0);
        repeat (2) @(posedge rclk);

        // Drain exactly the accepted write count.  The loop is bounded so a
        // broken empty flag cannot hang the farm simulation indefinitely.
        for (int i = 0; i < DEPTH + 8 && accepted_reads < accepted_writes; i++) begin
            read_attempt();
        end

        if (accepted_reads != accepted_writes) begin
            record_error($sformatf("read count did not catch write count: writes=%0d reads=%0d",
                                   accepted_writes, accepted_reads));
        end

        // One extra read should be rejected by rempty.
        wait (rempty === 1'b1);
        read_attempt();
        if (blocked_reads == 0) begin
            record_error("expected at least one blocked read after empty");
        end

        finish_with_summary();
    end

endmodule
