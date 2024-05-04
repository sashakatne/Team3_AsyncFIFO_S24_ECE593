class transaction;

    parameter DATA_SIZE = 8;
    bit wrst, rrst, wclk, rclk;
    rand bit [DATA_SIZE-1:0] wData;
    rand bit winc;
    rand bit rinc;

    //outputs 
    logic [DATA_SIZE-1:0] rData;
    bit rEmpty;
    bit wFull;
    bit rHalfEmpty;
    bit wHalfFull;

endclass
