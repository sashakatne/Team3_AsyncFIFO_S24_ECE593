class scoreboard;

  parameter DATA_SIZE = 8;

  mailbox mon2scb_w;
  mailbox mon2scb_r;

  // Reference model: a SystemVerilog queue. Push on every accepted write,
  // pop on every observed read, compare against rData.
  bit [DATA_SIZE-1:0] expected_q [$];

  int wr_count;
  int rd_count;
  int error_count;

  function new(mailbox mon2scb_w, mailbox mon2scb_r);
    this.mon2scb_w   = mon2scb_w;
    this.mon2scb_r   = mon2scb_r;
    this.wr_count    = 0;
    this.rd_count    = 0;
    this.error_count = 0;
  endfunction

  task process_writes();
    transaction t;
    forever begin
      mon2scb_w.get(t);
      expected_q.push_back(t.wData);
      wr_count++;
    end
  endtask

  task process_reads();
    transaction t;
    bit [DATA_SIZE-1:0] expected;
    forever begin
      mon2scb_r.get(t);
      if (expected_q.size() == 0) begin
        $error("[SCB] Read observed at rd_count=%0d but expected queue is empty (rData=%0h)",
               rd_count, t.rData);
        error_count++;
      end else begin
        expected = expected_q.pop_front();
        if (t.rData !== expected) begin
          $error("[SCB] MISMATCH at rd_count=%0d: expected=%0h, got=%0h",
                 rd_count, expected, t.rData);
          error_count++;
        end
      end
      rd_count++;
    end
  endtask

  // main() is non-blocking: it forks the two consumer threads in the
  // background and returns. The environment runs the consumers in parallel
  // with the producer side.
  task main();
    fork
      process_writes();
      process_reads();
    join_none
  endtask

  function void final_report();
    $display("");
    $display("==================== SCOREBOARD SUMMARY ====================");
    $display("  Writes observed       : %0d", wr_count);
    $display("  Reads  observed       : %0d", rd_count);
    $display("  Residual expected_q   : %0d", expected_q.size());
    $display("  Mismatches / errors   : %0d", error_count);
    if (error_count == 0)
      $display("  Verdict: *** PASSED ***");
    else
      $display("  Verdict: *** FAILED ***");
    $display("============================================================");
  endfunction

endclass
