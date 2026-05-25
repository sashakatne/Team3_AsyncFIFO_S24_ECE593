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

    // VCD dump for the evidence-package waveform renderer.
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end

    // Functional coverage for M3. These bins target legal FIFO behavior and
    // avoid impossible reset/clock cross bins from the original covergroup.
    covergroup async_fifo_cover;
        option.per_instance = 1;

        cp_writedata : coverpoint in.wData iff (in.winc && !in.wFull) {
            option.comment = "write data";
            bins low_range  = {[0:63]};
            bins mid_range  = {[64:127]};
            bins high_range = {[128:255]};
        }

        cp_readdata : coverpoint in.rData iff (in.rinc && !in.rEmpty) {
            option.comment = "read data";
            bins low_range  = {[0:63]};
            bins mid_range  = {[64:127]};
            bins high_range = {[128:255]};
        }

        cp_write_access : coverpoint {in.winc, in.wFull} {
            option.comment = "write request against full flag";
            bins idle         = {2'b00, 2'b01};
            bins accepted     = {2'b10};
            bins blocked_full = {2'b11};
        }

        cp_read_access : coverpoint {in.rinc, in.rEmpty} {
            option.comment = "read request against empty flag";
            bins idle          = {2'b00, 2'b01};
            bins accepted      = {2'b10};
            bins blocked_empty = {2'b11};
        }

        cp_fullflag : coverpoint in.wFull {
            option.comment = "full flag";
            bins full_c   = (0 => 1);
            bins full_c1  = (1 => 0);
        }

        cp_emptyflag: coverpoint in.rEmpty {
            option.comment = "empty flag";
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

        cp_writeinc : coverpoint in.winc {
            option.comment = "write increment";
            bins incr_s = (0 => 1);
            bins incr_s1 = (1 => 0);
        }

        cp_readinc : coverpoint in.rinc {
            option.comment = "read increment";
            bins incr_sr = (0 => 1);
            bins incr_s1r = (1 => 0);
        }

        cp_writereset: coverpoint in.wrst {
            option.comment = "write reset signal";
            bins reset_low_to_high = (0 => 1);
        }

        cp_readreset: coverpoint in.rrst {
            option.comment = "read reset signal";
            bins reset_low_to_high = (0 => 1);
        }

    endgroup

    async_fifo_cover async_fifo_cov_inst;

    initial begin
        async_fifo_cov_inst = new();
        forever begin @(posedge wclk or posedge rclk)
            async_fifo_cov_inst.sample();
        end
    end

endmodule
