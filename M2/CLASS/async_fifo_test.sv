import async_fifo_pkg::*;

program test(intf in);
  environment env;

  initial begin
    $display("[TEST] M2 class-based async FIFO test starting");
    env = new(in);

    // 500 cycles per side is enough to exercise multiple fill/drain phases
    // through the depth-64 FIFO with ~50% winc/rinc randomization.
    env.gen.trans_count       = 500;
    env.no_of_transactions    = 500;

    env.run();
    $display("[TEST] Done");
  end

endprogram
