// Compares the DUT's retirement stream against the reference.
`uvm_analysis_imp_decl(_rvfi)
`uvm_analysis_imp_decl(_irq)
`uvm_analysis_imp_decl(_sys)

class sb_retire extends uvm_scoreboard;
  `uvm_component_utils(sb_retire)

  uvm_analysis_imp_rvfi #(rvfi_txn, sb_retire) rvfi_imp;
  uvm_analysis_imp_irq  #(irq_txn,  sb_retire) irq_imp;
  uvm_analysis_imp_sys  #(sys_txn,  sb_retire) sys_imp;

  cpu_cfg        cfg;
  ref_model_base ref_m [];      // one per hart in FREERUN, one shared in MERGED

  int unsigned n_matched   [];
  int unsigned n_mismatched[];
  bit          truncated   [];  // hit trunc_pc; stop comparing this hart
  int unsigned n_after_trunc[]; // retirements seen past it -- reported, not compared

  bit pend_msip [];
  bit pend_mtip [];
  bit pend_valid[];

  int unsigned n_irq_delivered;
  int unsigned n_ref_trap_consumed;
  bit          seen_tohost;

  longint unsigned last_retire_cycle [];

  int unsigned n_load_deferred;
  int unsigned n_load_deferred_mem;

  int unsigned n_mem_reads_checked;
  int unsigned n_mem_writes_checked;
  int unsigned n_mem_rdata_unknown;
  string       deferred_detail;      // first few, verbatim, for the verdict

  int unsigned n_sc_seen;
  int unsigned n_sc_failed_injected;
  int unsigned n_sc_unobservable;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rvfi_imp = new("rvfi_imp", this);
    irq_imp  = new("irq_imp",  this);
    sys_imp  = new("sys_imp",  this);
  endfunction

  function void build_phase(uvm_phase phase);
    int unsigned n;
    super.build_phase(phase);

    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SB_RETIRE", "no cpu_cfg")

    n = cfg.num_harts;
    n_matched     = new[n];
    n_mismatched  = new[n];
    truncated     = new[n];
    n_after_trunc = new[n];
    pend_msip     = new[n];
    pend_mtip     = new[n];
    pend_valid    = new[n];
    last_retire_cycle = new[n];

    ref_m = new[cfg.use_ref_model ? 1 : 0];
    foreach (ref_m[i]) begin
      case (cfg.ref_model)
        cpu_cfg::REF_SPIKE: ref_m[i] = ref_spike::type_id::create($sformatf("ref%0d", i));
        default: `uvm_fatal("SB_RETIRE", $sformatf("unsupported ref_model %s",
                                                   cfg.ref_model.name()))
      endcase
    end
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    if (!cfg.use_ref_model) begin
      `uvm_info("SB_RETIRE", "no reference model: retirement is OBSERVED, not CHECKED", UVM_LOW)
      return;
    end
    foreach (ref_m[i]) begin
      ref_m[i].isa = cfg.ref_isa;
    end
    foreach (ref_m[i])
      if (!ref_m[i].open((cfg.elf_path != "") ? cfg.elf_path : cfg.hex_path, cfg.num_harts, 32'h8000_0000))
        `uvm_fatal("SB_RETIRE", $sformatf("reference %0d failed to open '%s'",
                                          i, (cfg.elf_path != "") ? cfg.elf_path : cfg.hex_path))
  endfunction

  // Lines each hart has stored to, so a deferral can demand a real peer writer.
  protected bit stored_line [longint unsigned];

  protected function longint unsigned line_key(int unsigned hart, word_t addr);
    return (longint'(hart) << 32) | longint'(addr >> mem_pkg::OFF_W);
  endfunction

  protected function bit peer_stored(int unsigned hart, word_t addr);
    for (int unsigned h = 0; h < cfg.num_harts; h++)
      if ((h != hart) && stored_line.exists(line_key(h, addr))) return 1;
    return 0;
  endfunction

  virtual function void write_rvfi(rvfi_txn t);
    if (t.is_mem_write()) stored_line[line_key(t.hart, t.mem_addr)] = 1;
    if (!cfg.use_ref_model) begin n_matched[t.hart]++; return; end
    if (t.cycle != 0) last_retire_cycle[t.hart] = t.cycle;

    if (cfg.cmp_mode == cpu_cfg::CMP_MERGED) compare_merged(t);
    else                                     compare_freerun(t);
  endfunction

  protected function void compare_freerun(rvfi_txn t);
    rvfi_txn r;

    if (cfg.is_trunc_pc(t.pc_rdata)) truncated[t.hart] = 1;
    if (truncated[t.hart]) begin
      n_after_trunc[t.hart]++;
      return;
    end

    apply_pending_irq(t.hart, 0);
    apply_sc_outcome(t);

    ref_m[0].set_hart(t.hart);
    if (!ref_step_aligned(t, r)) begin
      `uvm_error("SB_RETIRE", $sformatf(
        "hart %0d: reference could not step at DUT %s", t.hart, t.convert2string()))
      n_mismatched[t.hart]++;
      return;
    end
    check_one(t, r, 0);
  endfunction

  protected function void compare_merged(rvfi_txn t);
    rvfi_txn r;
    apply_pending_irq(t.hart, 0);
    apply_sc_outcome(t);
    ref_m[0].set_hart(t.hart);
    if (!ref_step_aligned(t, r)) begin
      `uvm_error("SB_RETIRE", $sformatf(
        "reference could not step hart %0d at DUT %s", t.hart, t.convert2string()))
      n_mismatched[t.hart]++;
      return;
    end
    check_one(t, r, 0);
  endfunction

  protected function bit is_sc_w(word_t insn);
    return (insn[6:0] == 7'b0101111) && (insn[31:27] == 5'b00011);
  endfunction

  protected function void apply_sc_outcome(rvfi_txn t);
    if (!is_sc_w(t.insn)) return;
    n_sc_seen++;

    if (t.rd_addr == 0) begin
      n_sc_unobservable++;
      return;
    end

    if (t.rd_wdata != 0) begin          // non-zero rd == the DUT's SC FAILED
      ref_m[0].break_reservation(t.hart);
      n_sc_failed_injected++;
    end
  endfunction

  protected function bit ref_step_aligned(rvfi_txn t, output rvfi_txn r);
    if (!ref_m[0].step(r)) return 0;

    if (r.trap && !t.trap) begin
      n_ref_trap_consumed++;
      `uvm_info("SB_RETIRE", $sformatf(
        {"reference took a trap at pc=%08h that the DUT reported no retirement ",
         "for -- an asynchronous interrupt. Consuming it and re-stepping so the ",
         "streams stay aligned."}, r.pc_rdata), UVM_HIGH)
      ref_m[0].unwind_order(t.hart);
      if (!ref_m[0].step(r)) return 0;
    end
    return 1;
  endfunction

  // Plain loads and LR.W: both read a word another hart may have written
  // between the DUT's read and the reference's replay.
  protected function bit is_load(word_t insn);
    return (insn[6:0] == 7'b0000011)
        || ((insn[6:0] == 7'b0101111) && (insn[31:27] == 5'b00010));
  endfunction

  protected function void check_one(rvfi_txn dut, rvfi_txn r, int unsigned ref_idx);
    if (!dut.compare(r) && is_load(dut.insn) && dut.differs_only_in_load_value(r)) begin
      bit mem_too = dut.load_value_differs(r);
      // A deferral is only for unsynchronised sharing: the word the DUT read
      // must itself differ, and some other hart must have stored to that line.
      // Anything else is the load datapath being wrong.
      if (!mem_too || !peer_stored(dut.hart, dut.mem_addr)) begin
        n_mismatched[dut.hart]++;
        `uvm_error("SB_RETIRE", $sformatf(
          {"LOAD VALUE MISMATCH with no sharing to excuse it: hart %0d #%0d pc=%08h ",
           "x%0d DUT=%08h REF=%08h, source word [%08h] DUT=%08h REF=%08h, %s"},
          dut.hart, dut.order, dut.pc_rdata, dut.rd_addr, dut.rd_wdata, r.rd_wdata,
          dut.mem_addr, dut.mem_rdata, r.mem_rdata,
          mem_too ? "no other hart ever stored to that line"
                  : "the word read AGREES so the extension or byte lane is wrong"))
        return;
      end
      n_load_deferred++;
      if (n_load_deferred <= 8)
        deferred_detail = {deferred_detail, $sformatf(
          "                #%0d pc=%08h  DUT %08h  REF %08h%s\n",
          dut.order, dut.pc_rdata, dut.rd_wdata, r.rd_wdata,
          mem_too ? $sformatf("   [%08h] DUT %08h REF %08h",
                              dut.mem_addr, dut.mem_rdata, r.mem_rdata) : "")};
      `uvm_info("SB_RETIRE", $sformatf(
        {"LOAD DEFERRED to the DUT (not verified): hart %0d #%0d pc=%08h ",
         "x%0d DUT=%08h REF=%08h%s. Legal on unsynchronised sharing -- the ",
         "reference is sequentially consistent and this core is not. Address ",
         "and width WERE checked and agree."},
        dut.hart, dut.order, dut.pc_rdata, dut.rd_addr, dut.rd_wdata, r.rd_wdata,
        mem_too ? $sformatf(", and its source word [%08h] DUT=%08h REF=%08h -- ",
                            dut.mem_addr, dut.mem_rdata, r.mem_rdata)
                : ""),
        UVM_LOW)
      if (mem_too) n_load_deferred_mem++;
      ref_m[ref_idx].set_reg(dut.hart, dut.rd_addr, dut.rd_wdata);
      n_matched[dut.hart]++;   // the instruction itself matched in every other field
      return;
    end

    if (dut.is_mem_read()) begin
      if (dut.mem_rdata_known && r.mem_rdata_known) n_mem_reads_checked++;
      else                                          n_mem_rdata_unknown++;
    end
    if (dut.is_mem_write()) n_mem_writes_checked++;

    if (dut.compare(r)) begin
      n_matched[dut.hart]++;
    end
    else begin
      string same_cycle = "";
      for (int unsigned h = 0; h < cfg.num_harts; h++)
        if ((h != dut.hart) && (last_retire_cycle[h] == dut.cycle) && (dut.cycle != 0))
          same_cycle = {same_cycle, $sformatf(
            "\n  SAME-CYCLE: hart %0d also retired at cycle %0d. This scoreboard ",
            h, dut.cycle)};
      if (same_cycle != "")
        same_cycle = {same_cycle,
          "has no snoop-derived tiebreak, so the replay order between them was ",
          "the analysis-port connect order, not the ordering point's. TIEBREAK ",
          "SUSPECT."};
      n_mismatched[dut.hart]++;
      `uvm_error("SB_RETIRE", {ref_m[ref_idx].describe_divergence(dut, r), same_cycle})
    end
  endfunction

  protected function void apply_pending_irq(int unsigned hart, int unsigned ref_idx);
    if (!pend_valid[hart]) return;
    ref_m[ref_idx].set_pending_interrupts(hart, pend_msip[hart], pend_mtip[hart]);
    pend_valid[hart] = 0;
    n_irq_delivered++;
  endfunction

  virtual function void write_irq(irq_txn t);
    if (!t.is_delivery()) return;
    for (int unsigned h = 0; h < cfg.num_harts; h++)
      if (t.msip_rise[h] || t.mtip_rise[h] || t.msip_fall[h] || t.mtip_fall[h]) begin
        pend_msip [h] = t.msip[h];
        pend_mtip [h] = t.mtip[h];
        pend_valid[h] = 1;
      end
  endfunction

  virtual function void write_sys(sys_txn t);
    if (t.kind == SYS_TOHOST && t.is_termination()) seen_tohost = 1;
  endfunction

  function void report_phase(uvm_phase phase);
    int unsigned total_matched = 0;

    foreach (n_matched[h]) begin
      total_matched += n_matched[h];
      `uvm_info("SB_RETIRE", $sformatf(
        "hart %0d: %0d matched, %0d mismatched%s",
        h, n_matched[h], n_mismatched[h],
        (n_after_trunc[h] != 0)
          ? $sformatf("  (+%0d retired past trunc_pc, NOT compared)", n_after_trunc[h])
          : ""), UVM_LOW)
    end

    `uvm_info("SB_RETIRE", $sformatf(
      "mode=%s  interrupts injected=%0d  reference traps consumed=%0d",
      cfg.cmp_mode.name(), n_irq_delivered, n_ref_trap_consumed), UVM_LOW)

    if (n_sc_seen != 0)
      `uvm_info("SB_RETIRE", $sformatf(
        {"SC: %0d observed, %0d failures injected into the reference, %0d ",
         "unobservable (rd=x0). Injection is ONE-WAY: a DUT SC that SUCCEEDED ",
         "is never helped, so an SC completed without a valid reservation ",
         "still reports as a divergence."},
        n_sc_seen, n_sc_failed_injected, n_sc_unobservable), UVM_LOW)

    if (cfg.num_harts > 0 && n_matched[0] < cfg.min_rvfi_matches_hart0)
      `uvm_error("SB_RETIRE", $sformatf(
        "hart0 matched only %0d (< %0d) -- comparison is vacuous, not passing",
        n_matched[0], cfg.min_rvfi_matches_hart0))
    if (cfg.num_harts > 1 && n_matched[1] < cfg.min_rvfi_matches_hart1)
      `uvm_error("SB_RETIRE", $sformatf(
        "hart1 matched only %0d (< %0d) -- comparison is vacuous, not passing",
        n_matched[1], cfg.min_rvfi_matches_hart1))

    if (cfg.use_ref_model)
      `uvm_info("SB_RETIRE", $sformatf(
        {"memory channel: %0d store(s) and %0d load(s) compared against the ",
         "reference (address, width, and data). Load values are checked against ",
         "reference memory CONTENTS via a backdoor read -- Spike logs that a load ",
         "happened without logging what it returned."},
        n_mem_writes_checked, n_mem_reads_checked), UVM_LOW)

    if ((n_mem_rdata_unknown != 0) && (n_mem_reads_checked == 0))
      `uvm_error("SB_RETIRE", $sformatf(
        {"ALL %0d load(s) had no reference value -- not one was checked. A ",
         "program whose every load is MMIO does not exist here, so this is the ",
         "reference's memory backdoor failing, not the workload. The address ",
         "and width comparisons still ran and still agreed, which is exactly ",
         "why this needs saying out loud."}, n_mem_rdata_unknown))

    if (n_mem_rdata_unknown != 0)
      `uvm_info("SB_RETIRE", $sformatf(
        {"%0d load(s) had NO reference value available (address not backed ",
         "memory -- MMIO or unmapped). Their address and width were checked; ",
         "their VALUE was not compared, and was not deferred either -- there ",
         "was nothing to defer to."}, n_mem_rdata_unknown), UVM_LOW)

    if (n_load_deferred != 0)
      `uvm_info("SB_RETIRE", $sformatf(
        {"%0d load value(s) DEFERRED to the DUT and not verified (ceiling %0d), ",
         "%0d of which also disagreed in mem_rdata -- the SAME event seen twice ",
         "(the word read, and the register it was written to), counted once. ",
         "The memory channel does NOT retire this deferral's missing net: it ",
         "checks stores and non-diverging loads, and narrows this deferral to ",
         "the VALUE by checking that the address and width agreed. See the ",
         "verdict block."},
        n_load_deferred, cfg.max_load_deferrals, n_load_deferred_mem), UVM_LOW)

    if (n_load_deferred > cfg.max_load_deferrals)
      `uvm_error("SB_RETIRE", $sformatf(
        {"%0d load deferrals exceeds the ceiling of %0d. This comparison spent ",
         "most of its time agreeing with the design it is supposed to be ",
         "checking, which is not a comparison. Either the program shares far ",
         "more than expected, or something is genuinely wrong with the loaded ",
         "data."}, n_load_deferred, cfg.max_load_deferrals))

    if (cfg.use_ref_model &&
        (total_matched > 100) && (n_mem_reads_checked == 0) && (n_mem_writes_checked == 0))
      `uvm_error("SB_RETIRE", $sformatf(
        {"compared %0d instructions and checked ZERO memory accesses. The ",
         "mem_* channels are plumbed but carrying nothing -- a memory ",
         "comparison that never runs is not a memory comparison."},
        total_matched))

    if (!seen_tohost)
      `uvm_warning("SB_RETIRE",
        "no tohost store observed -- the run ended by timeout or objection, not by the program")

    if (cfg.cmp_mode == cpu_cfg::CMP_MERGED)
      `uvm_info("SB_RETIRE",
        {"MERGED mode replays the DUT's observed order into the reference. ",
         "It checks instruction RESULTS, not whether that order was legal. ",
         "Ordering legality is litmus + sb_coherence."}, UVM_LOW)

    foreach (ref_m[i]) ref_m[i].close();
  endfunction

endclass
