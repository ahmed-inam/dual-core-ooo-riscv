// The reactive AXI4 slave on s1_if.
class mem_agent extends uvm_agent;
  `uvm_component_utils(mem_agent)

  cpu_cfg     cfg;
  mem_seqr    seqr;
  mem_driver  drv;
  mem_monitor mon;

  uvm_analysis_port #(mem_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)) v;

    super.build_phase(phase);

    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MEM_AGENT", "no cpu_cfg")

    if (!uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::get(
          this, "", "s1_vif", v))
      `uvm_fatal("MEM_AGENT", "no s1_vif published by tb_top")

    uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::set(this, "drv", "vif", v);
    uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::set(this, "mon", "vif", v);
    uvm_config_db #(cpu_cfg)::set(this, "drv",  "cfg", cfg);
    uvm_config_db #(cpu_cfg)::set(this, "mon",  "cfg", cfg);
    uvm_config_db #(cpu_cfg)::set(this, "seqr", "cfg", cfg);

    seqr = mem_seqr   ::type_id::create("seqr", this);
    drv  = mem_driver ::type_id::create("drv",  this);
    mon  = mem_monitor::type_id::create("mon",  this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    drv.seq_item_port.connect(seqr.seq_item_export);

    drv.req_ap.connect(seqr.req_fifo.analysis_export);

    ap = mon.ap;
  endfunction

endclass
