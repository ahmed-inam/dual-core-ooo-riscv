// Passive agent wrapping one rvfi_monitor, one per hart.
class rvfi_agent extends uvm_agent;
  `uvm_component_utils(rvfi_agent)

  int unsigned hart_id;

  rvfi_monitor                  mon;
  uvm_analysis_port #(rvfi_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    mon = rvfi_monitor::type_id::create("mon", this);
    mon.hart_id = hart_id;

    begin
      virtual rvfi_if v;
      string key = $sformatf("rvfi_vif_%0d", hart_id);
      if (!uvm_config_db #(virtual rvfi_if)::get(this, "", key, v))
        `uvm_fatal("RVFI_AGENT", $sformatf(
          {"no virtual interface published under '%s'. tb_top publishes these ",
           "from INSIDE the rvfi generate block (a runtime loop indexing ",
           "g_rvfi[h] is an illegal hierarchical reference), and the main ",
           "initial waits on n_rvfi_published before run_test -- check that ",
           "wait is still there if this fires."}, key))
      uvm_config_db #(virtual rvfi_if)::set(this, "mon", "vif", v);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = mon.ap;
  endfunction

endclass
