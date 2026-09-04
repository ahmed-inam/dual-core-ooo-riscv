// One master interface: sequence, driver, monitor.

class axi4_mst_agent;

  virtual axi4_if #(.ID_W(ID_WIDTH)) vif;
  int    idx;
  string name;

  axi4_seq         seq;
  axi4_mst_driver  drv;
  axi4_mst_monitor mon;

  mailbox #(axi4_txn) seq_out_mbx;
  mailbox #(axi4_txn) drv_in_mbx;

  function new(virtual axi4_if #(.ID_W(ID_WIDTH)) vif, int idx);
    this.vif  = vif;
    this.idx  = idx;
    this.name = $sformatf("MST_AGT%0d", idx);
  endfunction

  function void build();
    seq_out_mbx = new();
    drv_in_mbx  = new();
    seq = new(seq_out_mbx);
    drv = new(vif, drv_in_mbx);
    mon = new(vif);
    seq.name = $sformatf("SEQ%0d",     idx);
    drv.name = $sformatf("MST_DRV%0d", idx);
    mon.name = $sformatf("MST_MON%0d", idx);
    `TB_BUILD("axi4_mst_agent",   name);
    `TB_BUILD("axi4_seq",         seq.name);
    `TB_BUILD("axi4_mst_driver",  drv.name);
    `TB_BUILD("axi4_mst_monitor", mon.name);
  endfunction

  function void add_sub(mailbox #(axi4_txn) m);
    mon.add_sub(m);
  endfunction

  task run();
    fork
      drv.reset_watcher();
      drv.run();
      mon.run();
    join_none
  endtask

endclass
