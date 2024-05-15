`include "async_fifo_test.sv"
`include "async_fifo_interface.sv"

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

    //coverage start
    covergroup async_fifo_cover;
        option.per_instance = 1;

        // Coverpoints for data inputs and outputs
        cp_writedata : coverpoint in.wData{
            option.comment = "write data";
            bins low_range  = {[0:63]};
            bins mid_range  = {[64:127]};
            bins high_range = {[128:255]};
        }

        // Coverpoints for flags
        cp_fullflag : coverpoint in.wFull {
            option.comment = "full flag";
            bins full_c   = (0 => 1);
            bins full_c1  = (1 => 0);
        }

        // Coverpoints for flags
        cp_emptyflag: coverpoint in.rEmpty {
            option.comment = "when rest is low check if empty";
            bins empty_c  = (0 => 1);
            bins empty_c1 = (1 => 0);
        }

        cp_halffullflag: coverpoint in.wHalfFull {
            option.comment = "half full flag";
            bins half_full_c  = (0 => 1);
            bins half_full_c1 = (1 => 0);
        }

        cp_halfemptyflag: coverpoint in.rHalfEmpty {
            option.comment = "half empty flag";
            bins half_empty_c  = (0 => 1);
            bins half_empty_c1 = (1 => 0);
        }

        // Coverpoints for flags
        cp_readdata : coverpoint in.rData{
            option.comment = "read data";
            bins low_range  = {[0:63]};
            bins mid_range  = {[64:127]};
            bins high_range = {[128:255]};	
        }

        // Coverpoints for increment signals
        cp_writeinc : coverpoint in.winc{
            option.comment = "write increment";
            bins incr_s = (0 => 1);
            bins incr_s1 = (1 => 0);
        }

        // Coverpoints for increment signals
        cp_readinc : coverpoint in.rinc{
            option.comment = "read increment";
            bins incr_sr = (0 => 1);
            bins incr_s1r = (1 => 0);
        }

        // Coverpoints for reset signals
        cp_writereset: coverpoint in.wrst {
            option.comment = "write reset signal";
            bins reset_low_to_high = (0 => 1);
            bins reset_high_to_low = (1 => 0);
        }

        // Coverpoints for reset signals
        cp_readreset: coverpoint in.rrst {
            option.comment = "read reset signal";
            bins reset_low_to_high = (0 => 1);
            bins reset_high_to_low = (1 => 0);
        }

        // Coverpoints for clock signals
        cp_writeclk: coverpoint in.wclk {
            option.comment = "write clock signal";
            bins clk_low_to_high = (0 => 1);
            bins clk_high_to_low = (1 => 0);
        }

        // Coverpoints for clock signals
        cp_readclk: coverpoint in.rclk {
            option.comment = "read clock signal";
            bins clk_low_to_high = (0 => 1);
            bins clk_high_to_low = (1 => 0);
        }

        // Cross coverage for write data, address and increment signals
        WRITExADDxDATA : cross cp_writeclk,cp_writeinc,cp_writedata;
        READxADDxDATA  : cross cp_readclk, cp_readinc, cp_readdata;
        READxWRITE     : cross  cp_writedata,cp_readdata;
        RESETxWRITE    : cross cp_writereset, cp_writedata;
        RESETxREAD     : cross cp_readreset , cp_readdata;

    endgroup

    async_fifo_cover async_fifo_cov_inst;

    initial begin
        async_fifo_cov_inst = new();
        forever begin @(posedge wclk or posedge rclk)
            async_fifo_cov_inst.sample();
        end
    end

endmodule
