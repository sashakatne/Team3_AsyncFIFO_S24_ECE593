// Covergroup for basic FIFO signals
covergroup cg_fifo;
    coverpoint intf.winc {
        bins winc = {1};
        bins winc_b = {0};
    }
    coverpoint intf.rinc {
        bins rinc = {1};
        bins rinc_b = {0};
    }
    coverpoint intf.wFull {
        bins full_true = {1};
        bins full_false = {0};
    }
    coverpoint intf.rEmpty {
        bins empty_true = {1};
        bins empty_false = {0};
    }
endgroup

// Covergroup for monitoring wHalfFull wFull and rEmpty states
covergroup cg_half_full_empty;
    coverpoint intf.rHalfEmpty {
        bins half_full_true = {1};
        bins half_full_false = {0};
    }
    coverpoint intf.wHalfFull {
        bins half_full_true = {1};
        bins half_full_false = {0};
    }
endgroup

// Covergroup for data integrity
covergroup cg_data_integrity;
    coverpoint intf.wData {
        bins data_low = {[0:63]};
        bins data_mid = {[64:127]};
        bins data_high = {[128:191]};
        bins data_max = {[192:255]};
    }
endgroup

// Covergroup for specific data patterns
covergroup cg_data_patterns;
    coverpoint intf.rData {
        bins pattern_zero = {8'h00};
        bins pattern_all_ones = {8'hFF};
        bins pattern_alt_ones = {8'h55, 8'hAA};
    }
    coverpoint intf.wData {
        bins pattern_zero = {8'h00};
        bins pattern_all_ones = {8'hFF};
        bins pattern_alt_ones = {8'h55, 8'hAA};
    }
endgroup

// Covergroup for burst w/r ops
covergroup cg_burst_ops;
    coverpoint intf.winc {
        bins burst_write = {1};
    }
    coverpoint intf.rinc {
        bins burst_read = {1};
    }
endgroup

// Covergroup for RST 
covergroup cg_reset;
    coverpoint intf.wrst {
        bins w_reset_active = {0};
        bins w_reset_inactive = {1};
    }
    coverpoint intf.rrst {
        bins r_reset_active = {0};
        bins r_reset_inactive = {1};
    }
endgroup

// Covergroup for idle cycles
covergroup cg_idle_cycles;
    coverpoint intf.winc iff (!intf.winc) {
        bins wr_en_idle = {0};
    }
    coverpoint intf.rinc iff (!intf.rinc) {
        bins rd_en_idle = {0};
    }
endgroup

// Covergroup for high-freq ops
covergroup cg_high_freq;
    coverpoint intf.wclk {
        bins clk_wr_high = {1};
    }
    coverpoint intf.rclk {
        bins clk_rd_high = {1};
    }
endgroup

// Covergroup for capturing abrupt changes in r/w rates
covergroup cg_abrupt_change;
    coverpoint intf.winc {
        bins wr_en_change = {1};
        bins wr_en_stable = {0};
    }
    coverpoint intf.rinc {
        bins rd_en_change = {1};
        bins rd_en_stable = {0};
    }
endgroup

// Covergroup for capturing throughput under varied conditions
covergroup cg_throughput;
    coverpoint intf.winc {
        bins wr_en_active = {1};
        bins wr_en_inactive = {0};
    }
    coverpoint intf.rinc {
        bins rd_en_active = {1};
        bins rd_en_inactive = {0};
    }
endgroup
