// Passive agent wrapping snoop_monitor.
class snoop_agent extends uvm_agent;
  `uvm_component_utils(snoop_agent)

  cpu_cfg       cfg;
  snoop_monitor mon;

  uvm_analysis_port #(snoop_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual snoop_if v;

    super.build_phase(phase);

    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SNOOP_AGENT", "no cpu_cfg")

    if (!uvm_config_db #(virtual snoop_if)::get(this, "", "snoop_vif", v))
      `uvm_fatal("SNOOP_AGENT",
        {"no snoop_vif. This interface is BOUND into cluster, not instantiated ",
         "in tb_top -- the publisher is a hierarchical reference to ",
         "u_dut.u_snoop_vif. See this file's header."})

    uvm_config_db #(virtual snoop_if)::set(this, "mon", "vif", v);
    uvm_config_db #(cpu_cfg)::set(this, "mon", "cfg", cfg);

    mon = snoop_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    ap = mon.ap;
  endfunction

endclass
