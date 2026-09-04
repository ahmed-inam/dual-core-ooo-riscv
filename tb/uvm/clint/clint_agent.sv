// The CLINT, which since S6-EXT belongs to the testbench.
class clint_agent extends uvm_agent;
  `uvm_component_utils(clint_agent)

  cpu_cfg       cfg;
  clint_seqr    seqr;
  clint_driver  drv;
  clint_monitor mon;

  uvm_analysis_port #(irq_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)) v_axi;
    virtual irq_if                             v_irq;

    super.build_phase(phase);

    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CLINT_AGENT", "no cpu_cfg")

    if (!uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::get(
          this, "", "s0_vif", v_axi))
      `uvm_fatal("CLINT_AGENT", "no s0_vif published by tb_top")

    if (!uvm_config_db #(virtual irq_if)::get(this, "", "irq_vif", v_irq))
      `uvm_fatal("CLINT_AGENT", "no irq_vif published by tb_top")

    uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::set(this, "drv", "vif", v_axi);
    uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::set(this, "mon", "vif", v_axi);
    uvm_config_db #(virtual irq_if)::set(this, "drv", "irq_vif", v_irq);
    uvm_config_db #(virtual irq_if)::set(this, "mon", "irq_vif", v_irq);
    uvm_config_db #(cpu_cfg)::set(this, "drv",  "cfg", cfg);
    uvm_config_db #(cpu_cfg)::set(this, "mon",  "cfg", cfg);
    uvm_config_db #(cpu_cfg)::set(this, "seqr", "cfg", cfg);

    seqr = clint_seqr   ::type_id::create("seqr", this);
    drv  = clint_driver ::type_id::create("drv",  this);
    mon  = clint_monitor::type_id::create("mon",  this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    drv.seq_item_port.connect(seqr.seq_item_export);

    drv.acc_ap.connect(seqr.acc_fifo.analysis_export);

    ap = mon.ap;
  endfunction

endclass
