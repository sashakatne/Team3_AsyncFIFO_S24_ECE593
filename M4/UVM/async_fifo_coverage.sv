// M4 functional coverage focused on legal FIFO behavior and reachable flags.
covergroup FIFO_coverage;
  option.per_instance = 1;

  cp_writedata : coverpoint intf.wData iff (intf.winc && !intf.wFull) {
    bins low_range  = {[0:63]};
    bins mid_range  = {[64:127]};
    bins high_range = {[128:255]};
  }

  cp_readdata : coverpoint intf.rData iff (intf.rinc && !intf.rEmpty) {
    bins low_range  = {[0:63]};
    bins mid_range  = {[64:127]};
    bins high_range = {[128:255]};
  }

  cp_write_access : coverpoint {intf.winc, intf.wFull} {
    bins idle         = {2'b00, 2'b01};
    bins accepted     = {2'b10};
    bins blocked_full = {2'b11};
  }

  cp_read_access : coverpoint {intf.rinc, intf.rEmpty} {
    bins idle          = {2'b00, 2'b01};
    bins accepted      = {2'b10};
    bins blocked_empty = {2'b11};
  }

  cp_fullflag : coverpoint intf.wFull {
    bins full_c  = (0 => 1);
    bins full_c1 = (1 => 0);
  }

  cp_emptyflag : coverpoint intf.rEmpty {
    bins empty_c  = (0 => 1);
    bins empty_c1 = (1 => 0);
  }

  cp_halffullflag : coverpoint intf.wHalfFull {
    bins half_full_c  = (0 => 1);
    bins half_full_c1 = (1 => 0);
  }

  cp_halfemptyflag : coverpoint intf.rHalfEmpty {
    bins half_empty_c  = (0 => 1);
    bins half_empty_c1 = (1 => 0);
  }

  cp_writeinc : coverpoint intf.winc {
    bins incr_s  = (0 => 1);
    bins incr_s1 = (1 => 0);
  }

  cp_readinc : coverpoint intf.rinc {
    bins incr_sr  = (0 => 1);
    bins incr_s1r = (1 => 0);
  }

  cp_writereset : coverpoint intf.wrst {
    bins reset_low_to_high = (0 => 1);
  }

  cp_readreset : coverpoint intf.rrst {
    bins reset_low_to_high = (0 => 1);
  }
endgroup
