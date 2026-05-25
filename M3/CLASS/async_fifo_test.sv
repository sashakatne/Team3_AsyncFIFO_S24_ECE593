`include "async_fifo_environment.sv"

program test(intf in);

  environment env;

  initial begin
    $display("[TEST] M3 enhanced class-based async FIFO test starting");

    env = new(in);
    env.gen.trans_count    = 500;
    env.no_of_transactions = 500;

    env.run();
    $display("[TEST] Done");

  end

endprogram
