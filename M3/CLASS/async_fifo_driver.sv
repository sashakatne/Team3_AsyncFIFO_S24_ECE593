class driver;

  // Per-side counters so the environment can sanity-check the run.
  int wr_trans;
  int rd_trans;

  virtual intf drv_if;
  mailbox gen2driv_w;
  mailbox gen2driv_r;

  function new(virtual intf drv_if, mailbox gen2driv_w, mailbox gen2driv_r);
    this.drv_if     = drv_if;
    this.gen2driv_w = gen2driv_w;
    this.gen2driv_r = gen2driv_r;
    this.wr_trans   = 0;
    this.rd_trans   = 0;
  endfunction

  // Park interface signals and block until both active-low reset domains have deasserted.
  task reset;
    $display("[DRIVER] Reset asserted; parking interface signals at 0");
    drv_if.wData <= '0;
    drv_if.winc  <= '0;
    drv_if.rinc  <= '0;
    wait(drv_if.wrst === 1'b1 && drv_if.rrst === 1'b1);
    $display("[DRIVER] Reset deasserted; ready to drive");
  endtask

  // Drive winc/wData on every wclk negedge from the write-side mailbox.
  // Stimulus is intentionally not gated by wFull; the DUT's internal
  // (w_en & !full) gate is what must reject overflow attempts.
  task drive_writes(int n);
    transaction t;
    for (int i = 0; i < n; i++) begin
      @(negedge drv_if.wclk);
      gen2driv_w.get(t);
      drv_if.winc <= t.winc;
      if (t.winc) drv_if.wData <= t.wData;
      wr_trans++;
    end
    @(negedge drv_if.wclk);
    drv_if.winc <= 1'b0;
  endtask

  // Drive rinc independently on the read clock. Empty reads are also sent
  // deliberately so the DUT-side (r_en & !empty) gate is exercised.
  task drive_reads(int n);
    transaction t;
    for (int i = 0; i < n; i++) begin
      @(negedge drv_if.rclk);
      gen2driv_r.get(t);
      drv_if.rinc <= t.rinc;
      rd_trans++;
    end
    @(negedge drv_if.rclk);
    drv_if.rinc <= 1'b0;
  endtask

  task main(int n);
    fork
      drive_writes(n);
      drive_reads(n);
    join
    $display("[DRIVER] Done: wr_trans=%0d rd_trans=%0d", wr_trans, rd_trans);
  endtask

endclass
