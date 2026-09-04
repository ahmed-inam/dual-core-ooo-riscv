// SWMR and protocol legality, checked against a shadow model.
`uvm_analysis_imp_decl(_snoop)
`uvm_analysis_imp_decl(_mem)

class sb_coherence extends uvm_scoreboard;
  `uvm_component_utils(sb_coherence)

  uvm_analysis_imp_snoop #(snoop_txn, sb_coherence) snoop_imp;
  uvm_analysis_imp_mem   #(mem_txn,   sb_coherence) mem_imp;

  cpu_cfg cfg;
  virtual cache_probe_if probe [];

  protected line_state_t [NUM_HARTS-1:0] shadow [logic [31:0]];

  uvm_analysis_port #(snoop_txn) state_ap;

  int unsigned n_txn;
  int unsigned n_quiescent_samples;
  int unsigned n_completed_not_quiescent;
  int unsigned n_swmr_viol;
  int unsigned n_backdoor_checks;
  int unsigned n_backdoor_mismatch;
  int unsigned n_evictions_inferred;
  int unsigned n_wb_seen;
  int unsigned n_wb_unowned;
  int unsigned n_wb_after_downgrade;
  int unsigned n_putm_seen;
  int unsigned n_dut_said_violation;
  int unsigned n_model_said_violation;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    snoop_imp = new("snoop_imp", this);
    mem_imp   = new("mem_imp",   this);
    state_ap  = new("state_ap",  this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SB_COH", "no cpu_cfg")

    probe = new[cfg.num_harts];
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      string key = $sformatf("cache_probe_vif_%0d", h);
      if (!uvm_config_db #(virtual cache_probe_if)::get(this, "", key, probe[h]))
        `uvm_fatal("SB_COH", $sformatf(
          {"no '%s'. The cache backdoor is BOUND into dcache and published from ",
           "a generate in tb_top (a runtime loop indexing g_hart[h] is an ",
           "illegal hierarchical reference). Without it the shadow model has no ",
           "ground truth and this scoreboard degrades to checking itself."}, key))
    end
  endfunction

  protected function logic [31:0] line_of(word_t a);
    return a & ~((1 << mem_pkg::OFF_W) - 1);
  endfunction

  protected function logic [31:0] mem_line_of(word_t a);
    return line_of({14'b0, a[17:0]});
  endfunction

  protected function line_state_t shadow_get(int unsigned h, logic [31:0] line);
    if (!shadow.exists(line)) return LINE_I;
    return shadow[line][h];
  endfunction

  protected function void shadow_set(int unsigned h, logic [31:0] line, line_state_t s);
    if (!shadow.exists(line))
      for (int unsigned i = 0; i < NUM_HARTS; i++) shadow[line][i] = LINE_I;
    shadow[line][h] = s;
    if (s == LINE_M || s == LINE_E) ever_writable[line] = 1'b1;
  endfunction

  virtual function void write_snoop(snoop_txn t);
    logic [31:0] line = mem_line_of(t.req_addr);

    n_txn++;

    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      if (!t.snp_targets[h] || !t.snp_acked[h]) continue;
      case (t.snp_rsp[h])
        RSP_TtoB: shadow_set(h, line, LINE_S);   // was E/M, now S
        RSP_TtoN: shadow_set(h, line, LINE_I);   // was E/M, now I
        RSP_BtoN: shadow_set(h, line, LINE_I);   // was S,   now I
        RSP_TtoT: ;                              // held E/M, unchanged
        RSP_BtoB: ;                              // held S,   unchanged
        RSP_NtoN: ;                              // did not have it
        default:  `uvm_error("SB_COH", $sformatf("unknown snoop response %0d", t.snp_rsp[h]))
      endcase
    end

    if (t.completed) begin
      case (t.req_type)
        REQ_GETS:    shadow_set(t.req_hart, line, t.cmp_shared ? LINE_S : LINE_E);
        REQ_GETM,
        REQ_UPGRADE: shadow_set(t.req_hart, line, LINE_M);
        REQ_PUTM:    begin
                       n_putm_seen++;
                       shadow_set(t.req_hart, line, LINE_I);
                     end
        default:     `uvm_error("SB_COH", $sformatf("unknown request %0d", t.req_type))
      endcase

      if (t.is_quiescent()) begin
        check_backdoor(line, t);
        check_swmr(line, t);
        n_quiescent_samples++;
      end
      else begin
        n_completed_not_quiescent++;
      end
    end

    check_dut_selfreport(t, line);
    state_ap.write(t);
  endfunction

  protected function void check_swmr(logic [31:0] line, snoop_txn t);
    int unsigned n_writers = 0, n_readers = 0;   // ground truth: the tag arrays
    int unsigned m_writers = 0, m_readers = 0;   // shadow model: the bus stream
    string who = "";

    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      line_state_t s  = probe[h].state_of(line);
      line_state_t ms = shadow_get(h, line);
      if (s == LINE_M || s == LINE_E) begin n_writers++; who = {who, $sformatf(" h%0d=%s", h, s.name())}; end
      else if (s == LINE_S)           begin n_readers++; who = {who, $sformatf(" h%0d=S", h)}; end
      if (ms == LINE_M || ms == LINE_E) m_writers++;
      else if (ms == LINE_S)            m_readers++;
    end

    if ((m_writers > 1) || (m_writers == 1 && m_readers > 0))
      n_model_said_violation++;

    if ((n_writers > 1) || (n_writers == 1 && n_readers > 0)) begin
      n_swmr_viol++;
      `uvm_error("SB_COH", $sformatf(
        "SWMR violated on line %08h after %s:%s", line, t.convert2string(),
        {who, " [read from the cache tag arrays, not the shadow model]"}))
    end
  endfunction

  protected function void check_backdoor(logic [31:0] line, snoop_txn t);
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      line_state_t model  = shadow_get(h, line);
      line_state_t actual = probe[h].state_of(line);
      n_backdoor_checks++;

      if (model === actual) continue;

      if (actual == LINE_I) begin
        n_evictions_inferred++;
        shadow_set(h, line, LINE_I);
        `uvm_info("SB_COH", $sformatf(
          "line %08h hart %0d: model had %s, cache holds I -- eviction inferred, model resynced",
          line, h, model.name()), UVM_HIGH)
      end

      else begin
        n_backdoor_mismatch++;
        `uvm_error("SB_COH", $sformatf(
          {"line %08h hart %0d: cache tag_q holds %s but the shadow model has %s.\n",
           "  A line cannot be acquired silently -- every fill follows a GetS/GetM/\n",
           "  Upgrade. Either the coherence protocol granted permission it should\n",
           "  not have (design defect), or snoop_monitor dropped a transaction\n",
           "  (testbench defect).\n  after: %s"},
          line, h, actual.name(), model.name(), t.convert2string()))
      end
    end
  endfunction

  protected function void check_dut_selfreport(snoop_txn t, logic [31:0] line);
    if (t.ord_violation) begin
      n_dut_said_violation++;
      `uvm_warning("SB_COH", $sformatf(
        "ordering point self-reported a violation: %s", t.convert2string()))
    end
  endfunction

  virtual function void write_mem(mem_txn t);
    logic [31:0] line;
    if (t.dir != MEM_WRITE) return;
    line = mem_line_of(t.addr);
    n_wb_seen++;

    if (!ever_writable.exists(line)) begin
      n_wb_unowned++;
      `uvm_error("SB_COH", $sformatf(
        {"WRITEBACK of line %08h, which NO hart was ever granted E or M. A ",
         "cache cannot produce dirty data for a line it never held write ",
         "permission to -- either a GetS/GetM/Upgrade completion was missed by ",
         "this model, or the cache wrote back a line it did not own. E counts ",
         "because mesi_ctrl.sv:157 turns E into M SILENTLY, with no bus ",
         "request. %0d writeback(s) seen."},
        line, n_wb_seen))
    end else if (shadow.exists(line) && !any_hart_m(line)) begin
      n_wb_after_downgrade++;
    end
  endfunction

  protected bit ever_writable [logic [31:0]];

  protected function bit any_hart_m(logic [31:0] line);
    for (int unsigned h = 0; h < NUM_HARTS; h++)
      if (shadow_get(h, line) == LINE_M) return 1'b1;
    return 1'b0;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB_COH", $sformatf(
      {"writebacks: %0d observed, %0d of lines no hart was ever granted in M ",
       "(must be 0), %0d after the model had already lost write permission ",
       "(legal here -- ",
       "clean evictions raise no bus traffic, dcache.sv:120)."},
      n_wb_seen, n_wb_unowned, n_wb_after_downgrade), UVM_LOW)

    if (n_txn > 20 && n_wb_seen == 0)
      `uvm_warning("SB_COH",
        {"ZERO writebacks observed on a run with coherence traffic -- the ",
         "memory analysis port is not delivering, so the writeback check ",
         "reported clean without examining anything."})

    `uvm_info("SB_COH", $sformatf(
      "%0d coherence transactions, %0d quiescent samples, %0d SWMR violations",
      n_txn, n_quiescent_samples, n_swmr_viol), UVM_LOW)
    `uvm_info("SB_COH", $sformatf(
      "backdoor: %0d checks, %0d evictions inferred, %0d unexplained mismatches",
      n_backdoor_checks, n_evictions_inferred, n_backdoor_mismatch), UVM_LOW)

    if (n_quiescent_samples < cfg.min_quiescence_samples)
      `uvm_error("SB_COH", $sformatf(
        {"only %0d quiescent samples (< %0d). This scoreboard reported %0d ",
         "violations, but it barely sampled -- that is not a pass, it is a ",
         "checker that did not run."},
        n_quiescent_samples, cfg.min_quiescence_samples, n_swmr_viol))

    if (n_completed_not_quiescent != 0)
      `uvm_warning("SB_COH", $sformatf(
        {"%0d transaction(s) completed WITHOUT reaching quiescence and were not ",
         "sampled. snoop_txn::is_quiescent() requires every snooped hart to have ",
         "acked; if this is non-zero the ordering point no longer guarantees that ",
         "at cmp_valid, and the quiescence definition needs revisiting."},
        n_completed_not_quiescent))

    if (n_backdoor_checks == 0)
      `uvm_error("SB_COH",
        "the cache backdoor was never read: the shadow model has no ground truth")

    if (n_dut_said_violation != n_model_said_violation)
      `uvm_error("SB_COH", $sformatf(
        {"DISAGREEMENT: ordering point reported %0d violation(s), shadow model ",
         "found %0d. Neither is authoritative -- reconcile before trusting ",
         "either."}, n_dut_said_violation, n_model_said_violation))
  endfunction

endclass
