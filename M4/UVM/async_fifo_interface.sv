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
      
//modport DRIVER (clocking driver_cb, input wclk, rclk, rrst,wrst);
modport DRIVER(clocking driver_cb, input wclk,wrst);
modport MONITOR(clocking monitor_cb, input rclk,rrst);
    
endinterface: intf
