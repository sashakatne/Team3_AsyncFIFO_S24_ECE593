interface intf(input logic wclk,rclk,wrst,rrst);

parameter DATA_SIZE = 8;
//Inputs
logic [DATA_SIZE-1:0] wData;
logic winc;
logic rinc;

//outputs
logic [DATA_SIZE-1:0] rData;
logic rEmpty;
logic wFull;
logic rHalfEmpty;
logic wHalfFull;

// Clocking for driver domain
clocking driver_cb @(posedge wclk);
        output wData;                
      	output winc, rinc;
        input wFull, rEmpty;  
        input wHalfFull, rHalfEmpty;         
endclocking

// Clocking for read domain
clocking monitor_cb @(posedge rclk);
      	input winc, rinc;
        input rData;
        input wFull, rEmpty;
        input wHalfFull, rHalfEmpty;
endclocking

// Write-side observation clocking block. Default input skew is #1step, so
// samples are taken in the Preponed region of the next delta -- i.e. just
// BEFORE any NBA from a module's posedge wclk has fired. That matches what
// the DUT's always_ff @(posedge wclk) saw in its Active region, which is
// the only view that gives consistent transaction counts between the
// monitor (in a program, scheduled in the Reactive region) and the DUT.
clocking write_mon_cb @(posedge wclk);
        input winc;
        input wData;
        input wFull;
        input wHalfFull;
endclocking

//modport DRIVER (clocking driver_cb, input wclk, rclk, rrst,wrst);
modport DRIVER(clocking driver_cb, input wclk,wrst);
modport MONITOR(clocking monitor_cb, input rclk,rrst);

endinterface: intf
