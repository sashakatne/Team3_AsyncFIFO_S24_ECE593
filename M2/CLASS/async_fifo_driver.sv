class driver;

  // Per-side counters so the env can sanity-check the run.
  int wr_trans;
  int rd_trans;

  virtual intf drv_if;
  mailbox gen2driv_w;
  mailbox gen2driv_r;

  function new(virtual intf drv_if, mailbox gen2driv_w, mailbox gen2driv_r);
    this.drv_if    = drv_if;
    this.gen2driv_w = gen2driv_w;
    this.gen2driv_r = gen2driv_r;
    this.wr_trans  = 0;
    this.rd_trans  = 0;
  endfunction

  // Park interface signals and block until both reset domains have deasserted.
  // wrst and rrst are active-low here (driven 0 in top, then 1 after the reset
  // window), so 'deasserted' means '== 1'.
  task reset;
    $display("[DRIVER] Reset asserted; parking interface signals at 0");
    drv_if.wData <= '0;
    drv_if.winc  <= '0;
    drv_if.rinc  <= '0;
    wait(drv_if.wrst === 1'b1 && drv_if.rrst === 1'b1);
    $display("[DRIVER] Reset deasserted; ready to drive");
  endtask

  // Drive winc/wData on every wclk negedge from the write-side mailbox.
  // Sampling at negedge (with NBAs) means the signals are stable for the
  // DUT to capture at the following posedge. We deliberately do NOT gate
  // winc on !wFull here: the DUT's internal (w_en & !full) gate prevents
  // overflow writes, and exposing the DUT to (winc=1, wFull=1) cycles
  // closes the FEC bin in fifo_mem's `if(w_en & !full)` condition that
  // would otherwise stay 50% covered.
  task drive_writes(int n);
    transaction t;
    for (int i = 0; i < n; i++) begin
      @(negedge drv_if.wclk);
      gen2driv_w.get(t);
      drv_if.winc  <= t.winc;
      if (t.winc) drv_if.wData <= t.wData;
      wr_trans++;
    end
    @(negedge drv_if.wclk); drv_if.winc <= 1'b0;
  endtask

  // Drive rinc on every rclk negedge from the read-side mailbox. Same
  // reasoning as drive_writes: feed the DUT both 'good' (rinc=1, rEmpty=0)
  // and 'bad' (rinc=1, rEmpty=1) cycles so the rptr_handler FEC bins are
  // fully exercised. The DUT's internal (r_en & !empty) gate handles the
  // bad case correctly.
  task drive_reads(int n);
    transaction t;
    for (int i = 0; i < n; i++) begin
      @(negedge drv_if.rclk);
      gen2driv_r.get(t);
      drv_if.rinc <= t.rinc;
      rd_trans++;
    end
    @(negedge drv_if.rclk); drv_if.rinc <= 1'b0;
  endtask

  task main(int n);
    fork
      drive_writes(n);
      drive_reads(n);
    join
    $display("[DRIVER] Done: wr_trans=%0d rd_trans=%0d", wr_trans, rd_trans);
  endtask

endclass
