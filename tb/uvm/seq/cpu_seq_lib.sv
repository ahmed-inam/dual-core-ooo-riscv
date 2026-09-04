// Directed and constrained-random sequences.

class cpu_base_vseq extends uvm_sequence;
  `uvm_object_utils(cpu_base_vseq)

  cpu_cfg    cfg;
  mem_seqr   mem_sq;
  clint_seqr clint_sq;

  function new(string name = "cpu_base_vseq");
    super.new(name);
  endfunction

  virtual task pre_start();
    cpu_vseqr vs;
    if (!$cast(vs, m_sequencer))
      `uvm_fatal("CPU_VSEQ", "not started on a cpu_vseqr")
    cfg      = vs.cfg;
    mem_sq   = vs.mem_sq;
    clint_sq = vs.clint_sq;
  endtask

endclass


class cpu_idle_vseq extends cpu_base_vseq;
  `uvm_object_utils(cpu_idle_vseq)

  function new(string name = "cpu_idle_vseq");
    super.new(name);
  endfunction

  virtual task body();
    `uvm_info("CPU_IDLE_VSEQ",
      {"no stimulus: the memory randomises responses from cpu_cfg and the CLINT ",
       "runs as a register model. Everything observed in this run is the ",
       "environment and the DUT, not the sequence."}, UVM_LOW)
  endtask

endclass


class cpu_irq_ctx_vseq extends cpu_base_vseq;
  `uvm_object_utils(cpu_irq_ctx_vseq)

  int unsigned n_irq = 600;

  function new(string name = "cpu_irq_ctx_vseq");
    super.new(name);
  endfunction

  protected task write_clint(string nm, word_t addr, word_t data);
    irq_txn t = irq_txn::type_id::create(nm);
    t.kind = IRQ_REG_WRITE;
    t.addr = addr;
    t.data = data;
    start_item(t, .sequencer(clint_sq)); finish_item(t);
  endtask

  localparam time TICK = 100 * 10ns;

  virtual task body();

    write_clint("cmp_hi", cfg.clint_base + 32'h4004, 32'h0);

    write_clint("cmp_lo", cfg.clint_base + 32'h4000, 32'd8);
    #(TICK * 12);                       // let the one timer interrupt land

    for (int unsigned i = 0; i < n_irq; i++) begin
      write_clint($sformatf("msip_set_%0d", i), cfg.clint_base + 32'h0000, 32'h1);
      #(TICK / 2);                      // wide enough for the handler to enter
      write_clint($sformatf("msip_clr_%0d", i), cfg.clint_base + 32'h0000, 32'h0);
      #(TICK + (TICK / 4) * (i % 5));
    end
  endtask

endclass


class cpu_timer_irq_vseq extends cpu_base_vseq;
  `uvm_object_utils(cpu_timer_irq_vseq)

  rand int unsigned arm_after;
  constraint c_arm { soft arm_after inside {[2:10]}; }

  function new(string name = "cpu_timer_irq_vseq");
    super.new(name);
  endfunction

  virtual task body();
    irq_txn t;

    `uvm_info("CPU_TIMER_IRQ_VSEQ", $sformatf(
      "arming mtimecmp[0] at mtime+%0d", arm_after), UVM_LOW)

    t = irq_txn::type_id::create("cmp_hi");
    t.kind = IRQ_REG_WRITE;
    t.addr = cfg.clint_base + 32'h4004;      // mtimecmp[0] high word
    t.data = 32'h0000_0000;
    start_item(t, .sequencer(clint_sq)); finish_item(t);

    t = irq_txn::type_id::create("cmp_lo");
    t.kind = IRQ_REG_WRITE;
    t.addr = cfg.clint_base + 32'h4000;      // mtimecmp[0] low word
    t.data = arm_after;
    start_item(t, .sequencer(clint_sq)); finish_item(t);
  endtask

endclass
