class generator;

  rand transaction trans;
  int trans_count;

  // Two independent stimulus streams: one for the write side (sampled at
  // posedge wclk) and one for the read side (sampled at posedge rclk).
  mailbox gen2driv_w;
  mailbox gen2driv_r;

  function new(mailbox gen2driv_w, mailbox gen2driv_r);
    this.gen2driv_w = gen2driv_w;
    this.gen2driv_r = gen2driv_r;
  endfunction

  // Emit trans_count transactions to each side. Each transaction is
  // independently randomized so the two domains drive uncorrelated stimulus.
  task main();
    transaction tw, tr;
    for (int i = 0; i < trans_count; i++) begin
      tw = new();
      if (!tw.randomize()) $fatal("[GEN] write-side randomization failed at i=%0d", i);
      gen2driv_w.put(tw);

      tr = new();
      if (!tr.randomize()) $fatal("[GEN] read-side randomization failed at i=%0d", i);
      gen2driv_r.put(tr);
    end
    $display("[GEN] Emitted %0d transactions to each side", trans_count);
  endtask

endclass
