`include "async_fifo_test.sv"
`include "aysnc_fifo_interface.sv"

module async_fifo_top;

parameter WCLK_PERIOD = 12.5;
parameter RCLK_PERIOD = 20;
bit rclk,wclk,rrst,wrst;
  
always #(WCLK_PERIOD/2) wclk = ~wclk;
always #(RCLK_PERIOD/2) rclk = ~rclk;
  
initial 
begin
	wclk = '0;
    rclk = '0;
    wrst = '0;
    rrst = '0;
    
    #(WCLK_PERIOD*2) wrst = '1;
    #(RCLK_PERIOD*2) rrst = '1;
end

intf in (wclk,rclk,wrst,rrst);
test t1 (in);

asynchronous_fifo DUT (.wData(in.wData),
            .wFull(in.wFull),
            .wHalfFull(in.wHalfFull),
            .rEmpty(in.rEmpty),
            .rHalfEmpty(in.rHalfEmpty),
            .winc(in.winc),
            .rinc(in.rinc),
            .wclk(in.wclk),
            .rclk(in.rclk),
            .rrst(in.rrst),
            .wrst(in.wrst),
            .rData(in.rData)
);

endmodule
