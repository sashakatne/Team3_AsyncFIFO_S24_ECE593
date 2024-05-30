parameter DATA_SIZE = 8;

covergroup FIFO_coverage;
  
  coverpoint intf.wData {
    bins data_bin[] = {[0:(2**DATA_SIZE)-1]};
  }

  coverpoint intf.rData {
    bins data_bin[] = {[0:(2**DATA_SIZE)-1]};
  }
  
  coverpoint intf.wFull {
    bins full_bin[] = {0, 1};
  }

  coverpoint intf.wHalfFull {
    bins half_full_bin[] = {0, 1};
  }

  coverpoint intf.rEmpty {
    bins empty_bin[] = {0, 1};
  }

  coverpoint intf.rHalfEmpty {
    bins half_empty_bin[] = {0, 1};
  }

  cross intf.wData, intf.rData;
	
  cross intf.wData, intf.wFull;

  cross intf.rData, intf.rEmpty;

endgroup
