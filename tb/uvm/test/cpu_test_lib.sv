// Base test and the test library.

class cpu_test_base extends uvm_test;
  `uvm_component_utils(cpu_test_base)

  cpu_cfg cfg;
  cpu_env env;

  virtual sys_if sys_vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = cpu_cfg::type_id::create("cfg");

    // from $urandom: the 5.050 build takes +verilator+seed+<n>.
    if (!cfg.randomize())
      `uvm_warning(get_type_name(),
        {"cpu_cfg randomize() FAILED -- continuing on cpu_cfg's default window. ",
         "On Verilator 5.050 randomize() requires an external SAT solver; if the ",
         "image has no `z3` on PATH every constrained randomize() in this ",
         "environment fails the same way (cpu_timer_irq_vseq included). Install ",
         "z3 or set VERILATOR_SOLVER. Constrained randomisation is NOT in effect ",
         "until this warning stops appearing."})

    cfg.apply_plusargs();     // command line first
    configure(cfg);           // then this test's policy, which may override it
    cfg.check_valid();        // then fail loudly rather than run a hollow test

    uvm_config_db #(cpu_cfg)::set(this, "env", "cfg", cfg);
    env = cpu_env::type_id::create("env", this);

    if (!uvm_config_db #(virtual sys_if)::get(this, "", "sys_vif", sys_vif))
      `uvm_fatal(get_type_name(), "no sys_vif: cannot time the run")
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "program running");

    fork
      begin
        @(env.sys_ag.mon.tohost_seen);
        `uvm_info(get_type_name(), "tohost observed; draining", UVM_LOW)
      end
      begin
        repeat (cfg.timeout_cycles) @(posedge sys_vif.clk);
        `uvm_error(get_type_name(), $sformatf(
          "no tohost after %0d cycles: ending so the report phase can run",
          cfg.timeout_cycles))
      end
    join_any
    disable fork;

    repeat (200) @(posedge sys_vif.clk);
    phase.drop_objection(this, "done");
  endtask

  protected function string verdict_trust_block();
    string s;
    int unsigned deferred = (env.sb_ret != null) ? env.sb_ret.n_load_deferred : 0;
    s = "\n WHAT THIS RUN TOOK ON TRUST, AND WHAT STILL COVERS IT\n";
    s = {s, "  order       Spike executed the order the DUT retired in. That cannot\n",
            "              detect an ILLEGAL order, only a wrong result. Ordering\n",
            "              legality is the litmus gates and sb_coherence, not here.\n"};
    if (env.sb_ret != null && env.sb_ret.n_sc_failed_injected != 0)
      s = {s, $sformatf(
            "  SC failures %0d store-conditional failures were copied into the\n",
            env.sb_ret.n_sc_failed_injected),
            "              reference. A spurious failure is legal and unpredictable.\n",
            "              A wrong SC SUCCESS is NOT copied and would still be\n",
            "              reported, and the program's own count would not add up.\n"};
    if (env.sb_coh != null && env.sb_coh.n_evictions_inferred != 0)
      s = {s, $sformatf(
            "  evictions   %0d cache evictions inferred. Evictions produce no bus\n",
            env.sb_coh.n_evictions_inferred),
            "              traffic in this design, so they cannot be observed. The\n",
            "              reverse -- a cache holding a line it was never granted --\n",
            "              is a hard error.\n"};
    if (n_past_cut() != 0)
      s = {s, $sformatf(
            "  after cut   %0d instructions past the cut point were not compared.\n",
            n_past_cut()),
            "              The program had already written its result before them.\n"};
    if (deferred != 0)
      s = {s, $sformatf(
            " !load data  %0d load value(s) were taken from the DUT and are NOT\n", deferred),
            "              VERIFIED. They are legal on unsynchronised sharing --\n",
            "              the reference is sequentially consistent and this core\n",
            "              is not -- but if the design were wrong at these exact\n",
            "              points, this run would not have told you.\n",
            $sformatf(
            "              [12] Their ADDRESS and WIDTH were checked and agree,\n"),
            $sformatf(
            "              and %0d of them also disagreed in mem_rdata -- the same\n",
            env.sb_ret.n_load_deferred_mem),
            "              event seen twice (the word read, the register written),\n",
            "              excused as ONE deferral, not two. Still one-way: a load\n",
            "              whose register value AGREED and whose source word did\n",
            "              not is a hard error, not a deferral.\n",
            env.sb_ret.deferred_detail};

    if (env.sb_ret != null && cfg.use_ref_model)
      s = {s, $sformatf(
            "  memory      %0d store(s) and %0d load(s) were checked against the\n",
            env.sb_ret.n_mem_writes_checked, env.sb_ret.n_mem_reads_checked),
            "              reference: address, width, and data. Load values are\n",
            "              compared against reference memory CONTENTS, read\n",
            "              through a backdoor -- Spike records that a load\n",
            "              happened without recording what it returned.\n",
            "              This does NOT cover the deferred loads above; it covers\n",
            "              stores and every load that did not diverge.\n"};
    if (env.sb_ret != null && env.sb_ret.n_mem_rdata_unknown != 0)
      s = {s, $sformatf(
            "  memory ?    %0d load(s) read an address the reference does not back\n",
            env.sb_ret.n_mem_rdata_unknown),
            "              with memory (MMIO or unmapped). Address and width were\n",
            "              checked; the VALUE was not compared and was not\n",
            "              deferred -- there was nothing to defer to.\n"};
    return s;
  endfunction

  protected function int unsigned n_past_cut();
    int unsigned t = 0;
    if (env.sb_ret == null) return 0;
    foreach (env.sb_ret.n_after_trunc[h]) t += env.sb_ret.n_after_trunc[h];
    return t;
  endfunction

  function void print_verdict();
    string  hdr, body, full, unexercised;
    int unsigned compared = 0, mism = 0;
    int unsigned n_err, n_unexercised_err;
    bit pass, incomplete;
    int fd;

    if (env.sb_ret != null)
      foreach (env.sb_ret.n_matched[h]) begin
        compared += env.sb_ret.n_matched[h];
        mism     += env.sb_ret.n_mismatched[h];
      end

    unexercised = "";
    if (env.cov_l != null && cfg.cov_enable && env.cov_l.n_lr == 0)
      unexercised = {unexercised,
        "   COV_LRSC   no LR executed -- this program has no atomics\n"};
    if (env.sb_coh != null && env.sb_coh.n_quiescent_samples < cfg.min_quiescence_samples)
      unexercised = {unexercised, $sformatf(
        "   SB_COH     only %0d quiescent samples (floor %0d) -- barely sampled\n",
        env.sb_coh.n_quiescent_samples, cfg.min_quiescence_samples)};
    if (env.sb_ret != null && env.sb_ret.n_irq_delivered == 0)
      unexercised = {unexercised,
        "   CLINT      no interrupt delivered -- nothing armed mtimecmp\n"};

    n_unexercised_err = 0;
    if (env.cov_l != null && cfg.cov_enable && env.cov_l.n_lr == 0) n_unexercised_err++;
    if (env.sb_coh != null && env.sb_coh.n_quiescent_samples < cfg.min_quiescence_samples)
      n_unexercised_err++;

    n_err = uvm_report_server::get_server().get_severity_count(UVM_ERROR);

    pass = (mism == 0) && (n_err == 0)
        && (uvm_report_server::get_server().get_severity_count(UVM_FATAL) == 0)
        && env.sys_ag.terminated();

    incomplete = !pass && (mism == 0) && env.sys_ag.terminated()
              && (uvm_report_server::get_server().get_severity_count(UVM_FATAL) == 0)
              && (n_err <= n_unexercised_err) && (unexercised != "");

    hdr = $sformatf("\n============ %s : %s ============\n", get_type_name(),
                    pass ? "PASS" : (incomplete ? "INCOMPLETE" : "FAIL"));

    body = $sformatf(
      {" program      %s%s\n",
       cfg.use_ref_model
         ? " CHECKED      %0d instructions against the reference\n"
         : " NOT CHECKED  %0d instructions retired -- NO REFERENCE MODEL, nothing was\n              compared. This run observes and covers; it does not check.\n",
       " NOT CHECKED  %0d retired past the cut point\n",
       "              %0d load values deferred to the DUT\n",
       " mismatches   %0d\n"},
      cfg.hex_path,
      env.sys_ag.terminated()
        ? $sformatf(" -- terminated, reported %08h", env.sys_ag.exit_payload())
        : " -- DID NOT TERMINATE",
      compared, n_past_cut(),
      (env.sb_ret != null) ? env.sb_ret.n_load_deferred : 0, mism);

    if (env.sb_coh != null)
      body = {body, $sformatf(" coherence    %0d transactions, %0d sampled, %0d SWMR violations\n",
              env.sb_coh.n_txn, env.sb_coh.n_quiescent_samples, env.sb_coh.n_swmr_viol)};
    if (env.cov_c != null && cfg.cov_enable)
      body = {body, $sformatf(" coverage     instrument self-test %0.2f%% (must be 100.00)\n",
              env.cov_c.cov_self_pct)};

    if (unexercised != "")
      body = {body,
        "\n NOT EXERCISED -- these checkers did not get a chance to fail:\n",
        unexercised,
        " INCOMPLETE is not a pass. It means nothing was found wrong as far as\n",
        " this run went, and the lines above are how far that was.\n"};

    full = {hdr, body, verdict_trust_block(),
            "============================================================\n"};

    fd = $fopen("obj_uvm/verdict.txt", "w");
    if (fd) begin $fwrite(fd, "%s", full); $fclose(fd); end

    if (!pass || $test$plusargs("VERDICT"))
      `uvm_info("VERDICT", full, UVM_NONE)
    else
      `uvm_info("VERDICT", {hdr, body,
        "\n NOT A PROOF. This run took things on trust -- at minimum the\n",
        " retirement ORDER, which comes from the DUT and whose LEGALITY this\n",
        " scoreboard cannot judge. Re-run with +VERDICT for the full list, or\n",
        " read obj_uvm/verdict.txt (written every run) and\n",
        " tb/uvm/VERIFICATION_STATUS.md.\n",
        "============================================================\n"}, UVM_NONE)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    print_verdict();
    `uvm_info(get_type_name(), $sformatf(
      {"\n=== what this run supports ===\n",
       "  comparison mode : %s%s\n",
       "  reference model : %s\n",
       "  coverage        : %s\n",
       "  Read the SB_RETIRE, SB_COH, COV_* and CLINT_MON lines above before\n",
       "  concluding anything: several of them report that a checker did not\n",
       "  run, which is not the same as a checker that found nothing."},
      cfg.cmp_mode.name(),
      (cfg.cmp_mode == cpu_cfg::CMP_FREERUN && cfg.trunc_enabled())
        ? $sformatf(" (truncated at %08h%s)", cfg.trunc_pc,
                    (cfg.trunc_pc_alt != 0)
                      ? $sformatf(" or %08h", cfg.trunc_pc_alt) : "") : "",
      cfg.ref_model.name(),
      cfg.cov_enable ? "enabled" : "DISABLED"), UVM_LOW)

    if (env.sys_ag.terminated())
      `uvm_info(get_type_name(), $sformatf(
        "program terminated with tohost=%08h", env.sys_ag.exit_payload()), UVM_LOW)
    else
      `uvm_warning(get_type_name(),
        "program did NOT terminate: results below describe a partial run")
  endfunction

endclass


class cpu_smoke_test extends cpu_test_base;
  `uvm_component_utils(cpu_smoke_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable    = 0;
    c.use_ref_model = 0;   // the question here is 'does it boot', not 'is it correct'

    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;
    c.min_quiescence_samples = 0;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
      {"SMOKE ONLY. Coverage was off and the scoreboard floors were relaxed to ",
       "zero. A pass here means the DUT ran and the agents are wired -- it is ",
       "NOT evidence that anything was verified. Run cpu_base_test next."},
      UVM_LOW)
  endfunction

endclass


class cpu_base_test extends cpu_test_base;
  `uvm_component_utils(cpu_base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable = 1;
    c.cmp_mode   = cpu_cfg::CMP_FREERUN;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    if (!cfg.trunc_enabled())
      `uvm_warning(get_type_name(),
        {"no +TRUNC_PC given, so nothing was truncated. Both harts end in ",
         "crt0_multihart.S's park_forever loop (wfi ; j -4), which the DUT ",
         "retires as NOPs forever and Spike does not retire at all -- so every ",
         "error past that point is the program having FINISHED, not a defect."})
  endfunction

endclass


class cpu_ral_test extends cpu_test_base;
  `uvm_component_utils(cpu_ral_test)

  csr_reg_block        ral [];
  virtual csr_probe_if csr_vif [];
  int unsigned         n_reset_checked, n_reset_bad;
  int unsigned         n_policy_checked, n_policy_bad;
  int unsigned         n_mirror_checked, n_mirror_bad;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable             = 1;
    c.use_ref_model          = 0;
    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;
    c.min_quiescence_samples = 0;
    c.expected_tohost        = 32'h1;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ral     = new[cfg.num_harts];
    csr_vif = new[cfg.num_harts];
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      string key = $sformatf("csr_probe_vif_%0d", h);
      if (!uvm_config_db #(virtual csr_probe_if)::get(this, "", key, csr_vif[h]))
        `uvm_fatal("RAL", $sformatf(
          {"no '%s'. csr_probe_if is BOUND into core and published from tb_top's ",
           "generate. Without it the register model has no back door and every ",
           "check below would read zero and PASS -- which is why this is fatal ",
           "rather than a skip."}, key))
      ral[h] = csr_reg_block::type_id::create($sformatf("csr_ral_h%0d", h));
      ral[h].build_with(csr_vif[h]);
    end
  endfunction

  protected task check_reset(int unsigned h);
    uvm_reg        regs [$];
    uvm_status_e   st;
    uvm_reg_data_t got;
    ral[h].get_registers(regs);
    foreach (regs[i]) begin
      uvm_reg_field flds [$];
      bit           any_reset = 0;
      flds.delete();                     // get_fields APPENDS -- see csr_ral.sv
      regs[i].get_fields(flds);
      foreach (flds[j]) if (flds[j].has_reset()) any_reset = 1;
      if (!any_reset) continue;
      regs[i].read(st, got, UVM_BACKDOOR);
      n_reset_checked++;
      if (st != UVM_IS_OK) begin
        n_reset_bad++;
        `uvm_error("RAL", $sformatf("hart %0d: back-door read of %s failed",
                                    h, regs[i].get_name()))
      end
      else if (got !== regs[i].get_reset()) begin
        n_reset_bad++;
        `uvm_error("RAL", $sformatf(
          "hart %0d: %s (csr 'h%03h) reads 'h%08h at reset, model says 'h%08h",
          h, regs[i].get_name(), regs[i].get_address(ral[h].default_map),
          got, regs[i].get_reset()))
      end
      else void'(regs[i].predict(got));
    end
  endtask

  protected task check_policy(int unsigned h);
    uvm_reg regs [$];
    ral[h].get_registers(regs);
    foreach (regs[i]) begin
      uvm_reg_field flds [$];
      uvm_status_e  st;
      uvm_reg_data_t got;
      flds.delete();
      regs[i].get_fields(flds);
      regs[i].read(st, got, UVM_BACKDOOR);
      if (st != UVM_IS_OK) continue;
      foreach (flds[j]) begin
        uvm_reg_data_t fv;
        if (flds[j].get_access() != "RO") continue;
        if (!flds[j].has_reset())         continue;   // mip: volatile, no rule
        fv = (got >> flds[j].get_lsb_pos()) & ((1 << flds[j].get_n_bits()) - 1);
        n_policy_checked++;
        if (fv !== flds[j].get_reset()) begin
          n_policy_bad++;
          `uvm_error("RAL", $sformatf(
            {"hart %0d: %s.%s is declared RO with reset 'h%0h and reads 'h%0h ",
             "after the program ran. A read-only field CHANGED. For ",
             "mstatus.mpp this is csr_regfile.sv:183's WARL-zero rule broken -- ",
             "the defect mutation m13 injects."},
            h, regs[i].get_name(), flds[j].get_name(), flds[j].get_reset(), fv))
        end
      end
    end
  endtask

  protected task check_mirror(int unsigned h);
    uvm_reg regs [$];
    ral[h].get_registers(regs);
    foreach (regs[i]) begin
      uvm_status_e   st;
      uvm_reg_data_t got;
      uvm_reg_field  flds [$];
      bit            any_reset = 0;
      flds.delete();
      regs[i].get_fields(flds);
      foreach (flds[j]) if (flds[j].has_reset()) any_reset = 1;
      if (!any_reset) continue;           // mip changes under the CLINT
      regs[i].read(st, got, UVM_BACKDOOR);
      if (st != UVM_IS_OK) continue;
      if (!env.sb_csr_m.modeled(regs[i].get_address(ral[h].default_map))) continue;
      n_mirror_checked++;
      // The mirror is what the retirement stream predicts, never what was just read.
      void'(regs[i].predict(env.sb_csr_m.predicted(h, regs[i].get_address(ral[h].default_map))));
      if (regs[i].get_mirrored_value() !== got) begin
        n_mirror_bad++;
        `uvm_error("RAL", $sformatf(
          "hart %0d: %s mirror 'h%08h (predicted from the retirement stream) != hardware 'h%08h",
          h, regs[i].get_name(), regs[i].get_mirrored_value(), got))
      end
    end
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "register model");

    repeat (20) @(posedge sys_vif.clk);
    for (int unsigned h = 0; h < cfg.num_harts; h++) check_reset(h);
    `uvm_info("RAL", $sformatf("reset check: %0d register(s), %0d bad",
                               n_reset_checked, n_reset_bad), UVM_LOW)

    super.run_phase(phase);

    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      check_policy(h);
      check_mirror(h);
    end
    phase.drop_objection(this, "register model done");
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("RAL", $sformatf(
      {"REGISTER MODEL: %0d reset check(s) (%0d bad), %0d RO-policy check(s) ",
       "(%0d bad), %0d mirror check(s) (%0d bad), over %0d hart(s)."},
      n_reset_checked, n_reset_bad, n_policy_checked, n_policy_bad,
      n_mirror_checked, n_mirror_bad, cfg.num_harts), UVM_LOW)

    if (n_reset_checked == 0 || n_mirror_checked == 0)
      `uvm_error("RAL",
        {"the register model performed ZERO back-door reads. It reported no ",
         "failures because it did not look -- the probe is unwired or the block ",
         "has no registers."})
    if (n_policy_checked == 0)
      `uvm_error("RAL",
        {"ZERO read-only fields were checked. mstatus.mpp is declared RO in ",
         "csr_ral.sv; if this fires, the field lost its policy and the m13 net ",
         "went with it."})
  endfunction
endclass


class cpu_stress_test extends cpu_test_base;
  `uvm_component_utils(cpu_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable = 1;
    c.cmp_mode   = cpu_cfg::CMP_FREERUN;

    c.ref_isa    = "rv32ima_zicsr";

    c.expected_tohost = 32'h0000_0101;

    c.min_rvfi_matches_hart0 = 1;
    c.min_rvfi_matches_hart1 = 1;
    // a contention loop: each LR may read a peer SC that has not retired yet
    c.max_load_deferrals = 4000;
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (uvm_re_match(".*stress.*", cfg.hex_path))
      `uvm_error(get_type_name(), $sformatf(
        {"this test expects the atomics program but +HEX is '%s'. Run it as ",
         "HEX=asm/stress.hex ELF=asm/stress.elf ./scripts/run_uvm.sh %s"},
        cfg.hex_path, get_type_name()))
  endfunction

endclass


class cpu_share_test extends cpu_test_base;
  `uvm_component_utils(cpu_share_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable = 1;
    c.cmp_mode   = cpu_cfg::CMP_FREERUN;

    c.min_rvfi_matches_hart0 = 1;
    c.min_rvfi_matches_hart1 = 1;

  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (uvm_re_match(".*share.*", cfg.hex_path))
      `uvm_error(get_type_name(), $sformatf(
        {"this test expects the sharing program but +HEX is '%s'. Run it as ",
         "HEX=asm/share.hex ELF=asm/share.elf ./scripts/run_uvm.sh %s"},
        cfg.hex_path, get_type_name()))
  endfunction

endclass


class cpu_contend_test extends cpu_test_base;
  `uvm_component_utils(cpu_contend_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable = 1;
    c.cmp_mode   = cpu_cfg::CMP_FREERUN;
    c.min_rvfi_matches_hart0 = 1;
    c.min_rvfi_matches_hart1 = 1;
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (uvm_re_match(".*contend.*", cfg.hex_path))
      `uvm_error(get_type_name(), $sformatf(
        {"this test expects the contention program but +HEX is '%s'. Run it as ",
         "HEX=asm/contend.hex ELF=asm/contend.elf ./scripts/run_uvm.sh %s"},
        cfg.hex_path, get_type_name()))
  endfunction

endclass


class cpu_saturate_test extends cpu_test_base;
  `uvm_component_utils(cpu_saturate_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable = 1;
    c.cmp_mode   = cpu_cfg::CMP_FREERUN;
    c.min_rvfi_matches_hart0 = 1;
    c.min_rvfi_matches_hart1 = 1;
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (uvm_re_match(".*saturate.*", cfg.hex_path))
      `uvm_error(get_type_name(), $sformatf(
        {"this test expects the machine-fill program but +HEX is '%s'. Run it as ",
         "HEX=asm/saturate.hex ELF=asm/saturate.elf ./scripts/run_uvm.sh %s"},
        cfg.hex_path, get_type_name()))
  endfunction

endclass


class cpu_memconv_test extends cpu_test_base;
  `uvm_component_utils(cpu_memconv_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable = 1;
    c.cmp_mode   = cpu_cfg::CMP_FREERUN;
    c.ref_isa    = "rv32ima_zicsr";

    c.expected_tohost = 32'h0000_0001;

    c.min_rvfi_matches_hart0 = 1;
    c.min_rvfi_matches_hart1 = 1;

    c.max_load_deferrals = 0;
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (uvm_re_match(".*memconv.*", cfg.hex_path))
      `uvm_error(get_type_name(), $sformatf(
        {"this test expects the byte-lane program but +HEX is '%s'. Run it as ",
         "HEX=asm/memconv.hex ELF=asm/memconv.elf ./scripts/run_uvm.sh %s"},
        cfg.hex_path, get_type_name()))
  endfunction

endclass

class cpu_lrsc_trap_test extends cpu_test_base;
  `uvm_component_utils(cpu_lrsc_trap_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable = 1;
    c.cmp_mode   = cpu_cfg::CMP_FREERUN;
    c.ref_isa    = "rv32ima_zicsr";

    c.expected_tohost = 32'h0000_0001;

    c.min_rvfi_matches_hart0 = 1;
    c.min_rvfi_matches_hart1 = 1;
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (uvm_re_match(".*lrsc_trap.*", cfg.hex_path))
      `uvm_error(get_type_name(), $sformatf(
        {"this test expects the trap-in-LR/SC program but +HEX is '%s'. Run it ",
         "as HEX=asm/lrsc_trap.hex ELF=asm/lrsc_trap.elf ./scripts/run_uvm.sh %s"},
        cfg.hex_path, get_type_name()))
  endfunction

endclass


class cpu_axierr_test extends cpu_base_test;
  `uvm_component_utils(cpu_axierr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    super.configure(c);
    // A faulted load traps and is retried by buserr.S's handler; a faulted store
    // fill is retried by the cache. The reference cannot see either, so it is off.
    // Only the data buffer at 0x8000_4000 (buserr.S) is faulted: code stays clean.
    c.slverr_percent         = 25;
    c.slverr_lo              = 32'h8000_4000;
    c.use_ref_model          = 0;
    c.expected_tohost        = 32'h1;
    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;
    c.min_quiescence_samples = 0;
    c.expected_tohost        = 32'h1;
  endfunction
endclass

class cpu_irq_ctx_test extends cpu_base_test;
  `uvm_component_utils(cpu_irq_ctx_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    super.configure(c);
    c.use_ref_model          = 0;
    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;
    c.min_quiescence_samples = 0;
    c.expected_tohost        = 32'h1;
  endfunction

  task run_phase(uvm_phase phase);
    cpu_irq_ctx_vseq vseq;

    phase.raise_objection(this, "scheduling interrupts");
    vseq = cpu_irq_ctx_vseq::type_id::create("vseq");
    vseq.start(env.vseqr);
    phase.drop_objection(this, "scheduled");

    super.run_phase(phase);
  endtask

endclass

class cpu_wstall_test extends cpu_base_test;
  `uvm_component_utils(cpu_wstall_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    super.configure(c);
    c.w_stall_percent        = 92;
    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;
    c.min_quiescence_samples = 0;
  endfunction
endclass

class cpu_atomic_prog_test extends cpu_base_test;
  `uvm_component_utils(cpu_atomic_prog_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    super.configure(c);
    c.ref_isa                = "rv32ima_zicsr";
    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;
    c.min_quiescence_samples = 0;
    c.expected_tohost        = 32'h1;
  endfunction
endclass

class cpu_csrprobe_test extends cpu_test_base;
  `uvm_component_utils(cpu_csrprobe_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable    = 1;
    c.use_ref_model = 0;   // see the header: free-running counters, not ordering

    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;
    c.min_quiescence_samples = 0;
    c.expected_tohost = 32'h1;
  endfunction
endclass

class cpu_misalign_test extends cpu_test_base;
  `uvm_component_utils(cpu_misalign_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable    = 1;
    c.use_ref_model = 1;
    c.min_rvfi_matches_hart0 = 100;
    c.min_rvfi_matches_hart1 =  60;
    c.min_quiescence_samples = 0;
    c.expected_tohost = 32'h1;
  endfunction
endclass

class cpu_litmus_test extends cpu_test_base;
  `uvm_component_utils(cpu_litmus_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    c.cov_enable    = 1;
    c.use_ref_model = 0;    // see the header -- herd owns the ordering verdict

    c.min_rvfi_matches_hart0 = 0;
    c.min_rvfi_matches_hart1 = 0;

    c.min_quiescence_samples = 0;

    c.expected_tohost = 32'h0;
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (uvm_re_match(".*litmus.*", cfg.hex_path))
      `uvm_error(get_type_name(), $sformatf(
        {"this test expects a litmus program but +HEX is '%s'. Run it as ",
         "HEX=asm/litmus_mp.hex ELF=asm/litmus_mp.elf ./scripts/run_uvm.sh %s"},
        cfg.hex_path, get_type_name()))
  endfunction

endclass


class cpu_timer_irq_test extends cpu_base_test;
  `uvm_component_utils(cpu_timer_irq_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure(cpu_cfg c);
    super.configure(c);
    c.min_rvfi_matches_hart0 = 100;   // measured 530, spin count is timing-dependent
    c.min_rvfi_matches_hart1 = 20;    // measured 27, and that is its entire path
  endfunction

  task run_phase(uvm_phase phase);
    cpu_timer_irq_vseq vseq;

    phase.raise_objection(this, "arming timer");
    vseq = cpu_timer_irq_vseq::type_id::create("vseq");
    if (!vseq.randomize())
      `uvm_error(get_type_name(), "could not randomize cpu_timer_irq_vseq")
    vseq.start(env.vseqr);
    phase.drop_objection(this, "armed");

    super.run_phase(phase);
  endtask

endclass
