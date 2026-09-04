// Passive agent wrapping sys_monitor.
class sys_agent extends uvm_agent;
  `uvm_component_utils(sys_agent)

  cpu_cfg     cfg;
  sys_monitor mon;

  uvm_analysis_port #(sys_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual sys_if v;

    super.build_phase(phase);

    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SYS_AGENT", "no cpu_cfg")

    if (!uvm_config_db #(virtual sys_if)::get(this, "", "sys_vif", v))
      `uvm_fatal("SYS_AGENT", "no sys_vif published by tb_top")

    uvm_config_db #(virtual sys_if)::set(this, "mon", "vif", v);
    uvm_config_db #(cpu_cfg)::set(this, "mon", "cfg", cfg);

    mon = sys_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = mon.ap;
  endfunction

  function bit terminated();
    return mon.terminated;
  endfunction

  function word_t exit_payload();
    return mon.exit_payload;
  endfunction

endclass
