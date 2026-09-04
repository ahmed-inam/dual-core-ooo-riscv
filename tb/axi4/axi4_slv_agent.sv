// One slave interface: driver, monitor.

class axi4_slv_agent;

  virtual axi4_if #(.ID_W(M_ID_W)) vif;
  int    idx;
  string name;

  axi4_slv_driver  drv;
  axi4_slv_monitor mon;

  function new(virtual axi4_if #(.ID_W(M_ID_W)) vif, int idx);
    this.vif  = vif;
    this.idx  = idx;
    this.name = $sformatf("SLV_AGT%0d", idx);
  endfunction

  function void build();
    drv = new(vif);
    mon = new(vif);
    drv.name = $sformatf("SLV_DRV%0d", idx);
    mon.name = $sformatf("SLV_MON%0d", idx);
    `TB_BUILD("axi4_slv_agent",   name);
    `TB_BUILD("axi4_slv_driver",  drv.name);
    `TB_BUILD("axi4_slv_monitor", mon.name);
  endfunction

  function void add_sub(mailbox #(axi4_txn) m);
    mon.add_sub(m);
  endfunction

  function void set_ideal();
    drv.w_stall_pct = 0;
    drv.b_hold_pct  = 0;
    drv.r_hold_pct  = 0;
    drv.r_gap_pct   = 0;
  endfunction

  task run();
    fork
      drv.run();
      mon.run();
    join_none
  endtask

endclass
