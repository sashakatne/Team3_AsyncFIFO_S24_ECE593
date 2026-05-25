import async_fifo_pkg::*;

class environment;

  generator  gen;
  driver     driv;
  monitor    mon;
  scoreboard scb;

  // Stimulus mailboxes (generator -> driver)
  mailbox gen2driv_w;
  mailbox gen2driv_r;

  // Observation mailboxes (monitor -> scoreboard)
  mailbox mon2scb_w;
  mailbox mon2scb_r;

  virtual intf vif;

  // Total stimulus cycles per side. Set by the test.
  int no_of_transactions;

  function new(virtual intf vif);
    this.vif    = vif;
    gen2driv_w  = new();
    gen2driv_r  = new();
    mon2scb_w   = new();
    mon2scb_r   = new();
    gen         = new(gen2driv_w, gen2driv_r);
    driv        = new(vif, gen2driv_w, gen2driv_r);
    mon         = new(vif, mon2scb_w, mon2scb_r);
    scb         = new(mon2scb_w, mon2scb_r);
  endfunction

  task pre_env();
    driv.reset();
  endtask

  task test_run();
    scb.main();
    fork
      gen.main();
      driv.main(gen.trans_count);
      mon.main(gen.trans_count);
    join
  endtask

  task post_env();
    repeat (200) @(posedge vif.rclk);
    scb.final_report();
  endtask

  task run();
    pre_env();
    $display("[ENV] Running %0d stimulus cycles per side", gen.trans_count);
    test_run();
    post_env();
    $finish;
  endtask

endclass
