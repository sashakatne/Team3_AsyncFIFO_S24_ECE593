covergroup FIFO_coverage;
  
  coverpoint intf.wData {
    bins data_bin[] = {[0:255]}; 
  }

  coverpoint intf.rData {
    bins data_bin[] = {[0:255]}; 
  }
  
  coverpoint intf.wFull {
    bins full_bin[] = {0, 1};
  }

  coverpoint intf.rEmpty {
    bins empty_bin[] = {0, 1};
  }

  cross intf.wData, intf.rData;
	
  cross intf.wData, intf.wFull;

  cross intf.rData, intf.rEmpty;


endgroup
