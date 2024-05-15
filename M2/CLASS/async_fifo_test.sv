import async_fifo_pkg::*;

program test(intf in);
  environment env;
//  logic [5:0] read_request;
//  logic [5:0] write_request;
  
  initial begin
  
    $display("test environment start");
    //read_request = 5;
    //write_request = 5;

    env = new(in);
    env.gen.trans_count =30;
    /*env.gen.trans_count_write =5;
    env.driv.trans_count_read=5;
    env.driv.trans_count_write=5;
    env.mon.trans_count_write=5;
    env.mon.trans_count_read=5;*/

    env.no_of_transactions=120;

    env.run();
    $display("TEST FINISH");
    $finish;

  end

endprogram

