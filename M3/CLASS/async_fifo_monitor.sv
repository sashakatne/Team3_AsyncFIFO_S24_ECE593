class monitor;

  virtual intf mon_if;
  mailbox mon2scb_w;   // accepted writes -> scoreboard
  mailbox mon2scb_r;   // observed reads  -> scoreboard

  int wr_obs;
  int rd_obs;

  function new(virtual intf mon_if, mailbox mon2scb_w, mailbox mon2scb_r);
    this.mon_if    = mon_if;
    this.mon2scb_w = mon2scb_w;
    this.mon2scb_r = mon2scb_r;
    this.wr_obs    = 0;
    this.rd_obs    = 0;
  endfunction

  // Sample the write side through a clocking block so the monitor sees the
  // pre-edge values consumed by the DUT, not post-NBA flag updates.
  task observe_writes(int n);
    transaction t;
    for (int i = 0; i < n; i++) begin
      @(mon_if.write_mon_cb);
      if (mon_if.write_mon_cb.winc && !mon_if.write_mon_cb.wFull) begin
        t = new();
        t.winc      = mon_if.write_mon_cb.winc;
        t.wData     = mon_if.write_mon_cb.wData;
        t.wFull     = mon_if.write_mon_cb.wFull;
        t.wHalfFull = mon_if.write_mon_cb.wHalfFull;
        mon2scb_w.put(t);
        wr_obs++;
      end
    end
  endtask

  // Same idea for reads: sample through monitor_cb to observe the data word
  // associated with the pre-increment read pointer.
  task observe_reads(int n);
    transaction t;
    for (int i = 0; i < n; i++) begin
      @(mon_if.monitor_cb);
      if (mon_if.monitor_cb.rinc && !mon_if.monitor_cb.rEmpty) begin
        t = new();
        t.rinc       = mon_if.monitor_cb.rinc;
        t.rData      = mon_if.monitor_cb.rData;
        t.rEmpty     = mon_if.monitor_cb.rEmpty;
        t.rHalfEmpty = mon_if.monitor_cb.rHalfEmpty;
        mon2scb_r.put(t);
        rd_obs++;
      end
    end
  endtask

  task main(int n);
    fork
      observe_writes(n);
      observe_reads(n);
    join
    $display("[MONITOR] Done: wr_obs=%0d rd_obs=%0d", wr_obs, rd_obs);
  endtask

endclass
