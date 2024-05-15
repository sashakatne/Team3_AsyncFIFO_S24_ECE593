`include "async_fifo_environment.sv"

program test(intf in);

  environment env;
  
  initial begin
  
    $display("ASYNC FIFO TEST START");

    env = new(in);
    env.gen.trans_count = 420;
    env.no_of_transactions = 420;

    env.run();
    $display("ASYNC FIFO TEST FINISH");
    $finish;

  end

endprogram

