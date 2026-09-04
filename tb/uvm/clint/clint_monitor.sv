// Watches the interrupt pins and the CLINT register bus.
class clint_monitor extends uvm_monitor;
  `uvm_component_utils(clint_monitor)

  virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)) vif;   // s0_if
  virtual irq_if                             irq;   // the pins
  cpu_cfg cfg;
  int     clk_period_ns = 10;

  uvm_analysis_port #(irq_txn) ap;

  protected logic [NUM_HARTS-1:0] msip_prev, mtip_prev;
  protected bit                   seen_first;

  protected longint unsigned mtip_rise_cycle [NUM_HARTS];
  protected longint unsigned msip_rise_cycle [NUM_HARTS];

  int unsigned n_mtip_rise, n_msip_rise, n_reg_access;
  longint unsigned max_mtip_pending;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::get(
          this, "", "vif", vif))
      `uvm_fatal("CLINT_MON", "no s0_if virtual interface")
    if (!uvm_config_db #(virtual irq_if)::get(this, "", "irq_vif", irq))
      `uvm_fatal("CLINT_MON", "no irq_if virtual interface")
    void'(uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg));
    void'(uvm_config_db #(int)::get(this, "", "clk_period_ns", clk_period_ns));
  endfunction

  protected function longint unsigned cycle_now();
    return longint'($time / clk_period_ns);
  endfunction

  task run_phase(uvm_phase phase);
    fork
      pin_thread();
      bus_thread();
    join
  endtask

  task pin_thread();
    forever begin
      @(posedge irq.clk);

      if (irq.rst_n !== 1'b1) begin
        seen_first = 0;
        msip_prev  = '0;
        mtip_prev  = '0;
        continue;
      end

      if (!seen_first) begin
        msip_prev  = irq.msip;
        mtip_prev  = irq.mtip;
        seen_first = 1;
        continue;
      end

      begin
        logic [NUM_HARTS-1:0] msip_rise = irq.msip & ~msip_prev;
        logic [NUM_HARTS-1:0] mtip_rise = irq.mtip & ~mtip_prev;
        logic [NUM_HARTS-1:0] mtip_fall = ~irq.mtip & mtip_prev;
        logic [NUM_HARTS-1:0] msip_fall = ~irq.msip & msip_prev;

        for (int unsigned h = 0; h < NUM_HARTS; h++) begin
          if (mtip_rise[h]) begin mtip_rise_cycle[h] = cycle_now(); n_mtip_rise++; end
          if (msip_rise[h]) begin msip_rise_cycle[h] = cycle_now(); n_msip_rise++; end
          if (mtip_fall[h]) begin
            longint unsigned held = cycle_now() - mtip_rise_cycle[h];
            if (held > max_mtip_pending) max_mtip_pending = held;
          end
        end

        if ((msip_rise != '0) || (mtip_rise != '0) || (msip_fall != '0) || (mtip_fall != '0)) begin
          irq_txn t = irq_txn::type_id::create("irq");
          t.kind      = IRQ_DELIVERY;
          t.msip      = irq.msip;
          t.mtip      = irq.mtip;
          t.msip_rise = msip_rise;
          t.mtip_rise = mtip_rise;
          t.msip_fall = msip_fall;
          t.mtip_fall = mtip_fall;
          t.cycle     = cycle_now();
          t.order_known = 0;
          ap.write(t);
        end

        msip_prev = irq.msip;
        mtip_prev = irq.mtip;
      end
    end
  endtask

  task bus_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.arst_n !== 1'b1) continue;

      if (vif.awvalid && vif.awready) n_reg_access++;
      if (vif.arvalid && vif.arready) n_reg_access++;
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("CLINT_MON", $sformatf(
      "%0d timer rises, %0d software rises, %0d register accesses",
      n_mtip_rise, n_msip_rise, n_reg_access), UVM_LOW)

    if (max_mtip_pending != 0)
      `uvm_info("CLINT_MON", $sformatf(
        "longest mtip pending interval: %0d cycles", max_mtip_pending), UVM_LOW)

    if (n_mtip_rise == 0 && n_msip_rise == 0)
      `uvm_warning("CLINT_MON",
        {"NO interrupt was ever delivered in this run. Nothing here exercised ",
         "the DUT's interrupt path, and no result from this run supports any ",
         "claim about interrupt delivery. To change that, write mtimecmp -- ",
         "see clint_seqr."})
  endfunction

endclass
