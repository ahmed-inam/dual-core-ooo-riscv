// Builds the five agents, two scoreboards, four coverage models.
class cpu_env extends uvm_env;
  `uvm_component_utils(cpu_env)

  cpu_cfg cfg;

  rvfi_agent  rvfi_ag [];      // one per hart
  mem_agent   mem_ag;
  snoop_agent snoop_ag;
  clint_agent clint_ag;
  sys_agent   sys_ag;

  sb_retire    sb_ret;
  sb_coherence sb_coh;
  sb_csr       sb_csr_m;

  cov_core      cov_c;
  cov_coherence cov_h;
  cov_lrsc      cov_l;
  cov_isa       cov_i;      // ISA-level: hazards first, per COVERAGE_PLAN.md

  cpu_vseqr vseqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CPU_ENV",
        {"no cpu_cfg. The TEST builds it and sets it -- tb_top publishes only ",
         "the wiring. If this fires, cpu_test_lib's build_phase did not run or ",
         "did not set the config before super.build_phase()."})

    uvm_config_db #(cpu_cfg)::set(this, "*", "cfg", cfg);

    rvfi_ag = new[cfg.num_harts];
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      rvfi_ag[h] = rvfi_agent::type_id::create($sformatf("rvfi_ag%0d", h), this);
      rvfi_ag[h].hart_id = h;
    end

    mem_ag   = mem_agent  ::type_id::create("mem_ag",   this);
    snoop_ag = snoop_agent::type_id::create("snoop_ag", this);
    clint_ag = clint_agent::type_id::create("clint_ag", this);
    sys_ag   = sys_agent  ::type_id::create("sys_ag",   this);

    sb_ret = sb_retire   ::type_id::create("sb_ret", this);
    sb_coh = sb_coherence::type_id::create("sb_coh", this);
    sb_csr_m = sb_csr    ::type_id::create("sb_csr", this);

    if (cfg.cov_enable) begin
      cov_c = cov_core     ::type_id::create("cov_c", this);
      cov_h = cov_coherence::type_id::create("cov_h", this);
      cov_l = cov_lrsc     ::type_id::create("cov_l", this);
      cov_i = cov_isa      ::type_id::create("cov_i", this);
    end

    vseqr = cpu_vseqr::type_id::create("vseqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    foreach (rvfi_ag[h])
      rvfi_ag[h].ap.connect(sb_ret.rvfi_imp);

    clint_ag.ap.connect(sb_ret.irq_imp);
    clint_ag.ap.connect(sb_csr_m.irq_imp);
    for (int unsigned h = 0; h < cfg.num_harts; h++)
      rvfi_ag[h].ap.connect(sb_csr_m.rvfi_imp);
    sys_ag.ap.connect(sb_ret.sys_imp);

    snoop_ag.ap.connect(sb_coh.snoop_imp);
    mem_ag.ap.connect(sb_coh.mem_imp);

    if (cfg.cov_enable) begin
      foreach (rvfi_ag[h]) begin
        rvfi_ag[h].ap.connect(cov_c.rvfi_imp);
        rvfi_ag[h].ap.connect(cov_i.rvfi_imp);
      end
      mem_ag.ap.connect(cov_i.mem_imp);
      sys_ag.ap.connect(cov_c.sys_imp);

      sb_coh.state_ap.connect(cov_h.state_imp);
      snoop_ag.ap.connect(cov_l.snoop_imp);
    end

    vseqr.mem_sq   = mem_ag.seqr;
    vseqr.clint_sq = clint_ag.seqr;
    vseqr.check_connected();
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    `uvm_info("CPU_ENV", $sformatf(
      {"built: %0d RVFI agents, memory, coherence, CLINT, system; ",
       "2 scoreboards; coverage %s"},
      cfg.num_harts, cfg.cov_enable ? "ENABLED" : "DISABLED"), UVM_LOW)
    `uvm_info("CPU_ENV", cfg.convert2string(), UVM_LOW)
  endfunction

endclass
