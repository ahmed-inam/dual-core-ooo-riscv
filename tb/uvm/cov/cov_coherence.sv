// The C1 protocol table, snoop x line state, and the.
`uvm_analysis_imp_decl(_ch_state)

class cov_coherence extends uvm_component;
  `uvm_component_utils(cov_coherence)

  uvm_analysis_imp_ch_state #(snoop_txn, cov_coherence) state_imp;

  cpu_cfg cfg;

  localparam int L_I = 0;
  localparam int L_S = 1;
  localparam int L_E = 2;
  localparam int L_O = 3;
  localparam int L_M = 4;

  localparam int R_GETS = 0;
  localparam int R_GETM = 1;
  localparam int R_UPG  = 2;
  localparam int R_PUTM = 3;

  int unsigned prev_state [logic [31:0]][NUM_HARTS];

  protected function logic [31:0] line_of(logic [31:0] a);
    return a & ~((1 << mem_pkg::OFF_W) - 1);
  endfunction

  protected function int unsigned pstate_get(logic [31:0] line, int unsigned h);
    if (!prev_state.exists(line)) return L_I;
    return prev_state[line][h];
  endfunction

  protected function void pstate_set(logic [31:0] line, int unsigned h,
                                     int unsigned v);
    if (!prev_state.exists(line))
      for (int unsigned i = 0; i < NUM_HARTS; i++) prev_state[line][i] = L_I;
    prev_state[line][h] = v;
  endfunction

  int unsigned n_resync_inband;   // shadow corrected by hardware evidence
  int unsigned n_silent_acquire;  // the DANGEROUS direction -- see check below
  int unsigned n_c1_illegal;      // declared-illegal C1 cells, counted for real

  int unsigned n_sampled, n_transitions;

  covergroup cg_c1 with function sample(int unsigned a_req,
                                        int unsigned a_sreq,
                                        int unsigned a_sother);
    option.per_instance = 1;

    cp_r : coverpoint a_req {
      bins gets    = {R_GETS};
      bins getm    = {R_GETM};
      bins upgrade = {R_UPG};
      ignore_bins putm_never_issued = {R_PUTM};
    }

    cp_sr : coverpoint a_sreq {
      bins i = {L_I};
      bins s = {L_S};
      bins e = {L_E};
      bins m = {L_M};
      illegal_bins reserved_o = {L_O};
    }

    cp_so : coverpoint a_sother {
      bins i = {L_I};
      bins s = {L_S};
      bins e = {L_E};
      bins m = {L_M};
      illegal_bins reserved_o = {L_O};
    }

    x_c1 : cross cp_r, cp_sr, cp_so {
      illegal_bins m_requests_read  = binsof(cp_sr.m) &&
                                      (binsof(cp_r.gets) || binsof(cp_r.getm) ||
                                       binsof(cp_r.upgrade));
      illegal_bins e_upgrades       = binsof(cp_sr.e) && binsof(cp_r.upgrade);
      illegal_bins i_upgrades       = binsof(cp_sr.i) && binsof(cp_r.upgrade);
      illegal_bins both_exclusive   = (binsof(cp_sr.m) || binsof(cp_sr.e)) &&
                                      (binsof(cp_so.m) || binsof(cp_so.e));
    }
  endgroup

  covergroup cg_snoop with function sample(int unsigned a_snoop,
                                           int unsigned a_sother,
                                           bit          a_shared,
                                           bit          a_dirty,
                                           bit          a_atomic,
                                           int unsigned a_req);
    option.per_instance = 1;

    cp_sn : coverpoint a_snoop {
      bins none = {0};
      bins to_s = {1};
      bins to_i = {2};
    }

    cp_target_state : coverpoint a_sother {
      bins i = {L_I};
      bins s = {L_S};
      bins e = {L_E};
      bins m = {L_M};
    }

    cp_result : coverpoint {a_shared, a_dirty} {
      bins clean_exclusive = {2'b00};
      bins dirty_exclusive = {2'b01};
      bins clean_shared    = {2'b10};
      bins dirty_shared    = {2'b11};
    }

    cp_sn_sent : coverpoint a_snoop iff (a_snoop != 0) {
      bins to_s = {1};
      bins to_i = {2};
    }

    x_snoop_state  : cross cp_sn_sent, cp_target_state;

    x_snoop_result : cross cp_sn_sent, cp_result;

    cp_atomic_b : coverpoint a_atomic {
      bins normal = {0};
      bins atomic = {1};
    }

    x_atomic_req : cross cp_atomic_b, cp_r_dup;
    cp_r_dup : coverpoint a_req {
      bins gets = {R_GETS};
      bins getm = {R_GETM};
      bins upgrade = {R_UPG};
      ignore_bins putm_never_issued = {R_PUTM};
    }
  endgroup

  covergroup cg_trans with function sample(int unsigned a_from,
                                           int unsigned a_to,
                                           int unsigned a_hart);
    option.per_instance = 1;

    cp_t : coverpoint {a_from, a_to} {
      bins i_to_s = {{L_I, L_S}};
      bins i_to_e = {{L_I, L_E}};
      bins i_to_m = {{L_I, L_M}};
      bins s_to_m = {{L_S, L_M}};
      bins s_to_i = {{L_S, L_I}};
      bins e_to_m = {{L_E, L_M}};
      bins e_to_s = {{L_E, L_S}};
      bins e_to_i = {{L_E, L_I}};
      bins m_to_s = {{L_M, L_S}};
      bins m_to_i = {{L_M, L_I}};
    }
    cp_th : coverpoint a_hart { bins hart0 = {0}; bins hart1 = {1}; }
    x_trans_hart : cross cp_t, cp_th;
  endgroup

  virtual snoop_if       vif;
  virtual cache_probe_if probe [];
  protected logic [NUM_HARTS-1:0] rq_prev;
  protected bit                   rq_seen_first;

  int unsigned n_c1eq_checked;      // (state, request) pairs examined
  int unsigned n_c1eq_raced;        // UPGRADE seen at I -- the legal race
  int unsigned n_c1eq_bad;          // pairs mesi_ctrl's table forbids
  int unsigned n_c1eq_intent;
  bit          first_bad_intent_wi;
  int          first_bad_intent_req;
  int unsigned first_bad_state, first_bad_req;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    state_imp = new("state_imp", this);
    cg_c1     = new();
    cg_snoop  = new();
    cg_trans  = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("COV_COH", "no cpu_cfg")
    prev_state.delete();

    if (!uvm_config_db #(virtual snoop_if)::get(this, "", "snoop_vif", vif))
      `uvm_fatal("COV_COH",
        {"no snoop_vif. The C1 equivalence check samples req_valid PER CYCLE, ",
         "because the requester's line state has to be read BEFORE the fill -- ",
         "a transaction arrives too late to answer the question."})
    probe = new[NUM_HARTS];
    foreach (probe[h]) begin
      string key = $sformatf("cache_probe_vif_%0d", h);
      if (!uvm_config_db #(virtual cache_probe_if)::get(this, "", key, probe[h]))
        `uvm_fatal("COV_COH", {"no ", key, " -- the C1 equivalence check reads ",
                               "the real tag array, not a shadow model"})
    end
  endfunction

  task run_phase(uvm_phase phase);
    if (!cfg.cov_enable) return;
    forever begin
      @(posedge vif.clk);
      if (vif.rst_n !== 1'b1) begin rq_seen_first = 0; continue; end
      if (!rq_seen_first) begin rq_prev = vif.req_valid; rq_seen_first = 1; continue; end
      check_c1_equivalence(vif.req_valid & ~rq_prev);
      rq_prev = vif.req_valid;
    end
  endtask

  protected function void check_c1_equivalence(logic [NUM_HARTS-1:0] rise);
    line_state_t st;
    coh_req_e    want_req;
    for (int unsigned h = 0; h < NUM_HARTS; h++) begin
      if (!rise[h]) continue;
      st = probe[h].state_of(vif.req_addr[h]);
      n_c1eq_checked++;
      if (vif.req_type[h] inside {REQ_GETS, REQ_GETM}) begin
        want_req = probe[h].wi ? REQ_GETM : REQ_GETS;
        if (vif.req_type[h] != want_req) begin
          if (n_c1eq_intent == 0) begin
            first_bad_intent_wi  = probe[h].wi;
            first_bad_intent_req = int'(vif.req_type[h]);
          end
          n_c1eq_intent++;
        end
      end
      case (vif.req_type[h])
        REQ_GETS, REQ_GETM:
          if (st != LINE_I) begin
            if (n_c1eq_bad == 0) begin
              first_bad_state = int'(st); first_bad_req = int'(vif.req_type[h]);
            end
            n_c1eq_bad++;
          end
        REQ_UPGRADE:
          if (st == LINE_I) n_c1eq_raced++;
          else if (st != LINE_S) begin
            if (n_c1eq_bad == 0) begin
              first_bad_state = int'(st); first_bad_req = int'(vif.req_type[h]);
            end
            n_c1eq_bad++;
          end
        default: ;   // REQ_PUTM is never issued; cp_r.putm_never_issued covers it
      endcase
    end
  endfunction

  protected function int unsigned req_prestate(snoop_txn t);
    case (t.req_type)
      REQ_GETS, REQ_GETM: return L_I;
      REQ_UPGRADE:        return L_S;
      default:            return L_I;   // PUTM is never issued by this design
    endcase
  endfunction

  protected function int unsigned other_prestate(snoop_txn t, int unsigned other);
    if (NUM_HARTS <= 1)                  return L_I;
    if (!t.snp_sent || !t.snp_targets[other]) return L_I;  // directory saw no sharer
    case (t.snp_rsp[other])
      RSP_TtoB, RSP_TtoN, RSP_TtoT: return t.cmp_dirty ? L_M : L_E;
      RSP_BtoN, RSP_BtoB:           return L_S;
      RSP_NtoN:                     return L_I;
      default:                      return L_I;
    endcase
  endfunction

  protected function void check_c1_legality(int unsigned req, int unsigned sr,
                                            int unsigned so, snoop_txn t);
    string why = "";
    if ((sr == L_M) && (req inside {R_GETS, R_GETM, R_UPG}))
      why = "m_requests_read: a hart in M already holds write permission";
    else if ((sr == L_E) && (req == R_UPG))
      why = "e_upgrades: E to M is a silent hit, never a bus request";
    else if ((sr == L_I) && (req == R_UPG))
      why = "i_upgrades: nothing to upgrade from I";
    else if ((sr inside {L_M, L_E}) && (so inside {L_M, L_E}))
      why = "both_exclusive: two harts holding write permission violates SWMR";
    if (why != "") begin
      n_c1_illegal++;
      `uvm_error("COV_COH", $sformatf(
        "ILLEGAL C1 cell on %s -- %s", t.convert2string(), why))
    end
  endfunction

  virtual function void write_ch_state(snoop_txn t);
    int unsigned other;

    if (!cfg.cov_enable) return;
    if (!t.completed)    return;   // an incomplete transaction has no result to bin

    other = (t.req_hart == 0) ? 1 : 0;

    begin
      logic [31:0] ln      = line_of(t.req_addr);
      int unsigned s_req   = req_prestate(t);
      int unsigned s_other = other_prestate(t, other);
      int unsigned snp     = !t.snp_sent ? 0 : ((t.snp_type == SNP_TO_S) ? 1 : 2);

      if (pstate_get(ln, t.req_hart) != s_req) begin
        if (s_req == L_I || pstate_get(ln, t.req_hart) != L_I) n_resync_inband++;
        else begin
          n_silent_acquire++;
          `uvm_error("COV_COH", $sformatf(
            {"hart %0d issued %s implying it held %0d on line %08h, but nothing ",
             "was ever observed granting it a copy -- a line cannot be acquired ",
             "silently"}, t.req_hart, t.convert2string(), s_req, ln))
        end
        pstate_set(ln, t.req_hart, s_req);
      end
      if (NUM_HARTS > 1 && pstate_get(ln, other) != s_other) begin
        n_resync_inband++;
        pstate_set(ln, other, s_other);
      end

      check_c1_legality(int'(t.req_type), s_req, s_other, t);

      cg_c1.sample(int'(t.req_type), s_req, s_other);
      cg_snoop.sample(snp, s_other, t.cmp_shared, t.cmp_dirty,
                      t.req_atomic, int'(t.req_type));
      if ((t.req_type == REQ_GETS) && t.cmp_dirty && !t.cmp_shared)
        `uvm_info("COV_COH", $sformatf("GetS completed dirty and exclusive: %s", t.convert2string()), UVM_LOW)
    end
    n_sampled++;

    update_transitions(t, other, line_of(t.req_addr));
  endfunction

  protected function void update_transitions(snoop_txn t, int unsigned other,
                                            logic [31:0] ln);
    int unsigned new_req;

    case (t.req_type)
      REQ_GETS:    new_req = t.cmp_shared ? L_S : L_E;
      REQ_GETM,
      REQ_UPGRADE: new_req = L_M;
      REQ_PUTM:    new_req = L_I;
      default:     new_req = pstate_get(ln, t.req_hart);
    endcase

    if (new_req != pstate_get(ln, t.req_hart)) begin
      cg_trans.sample(pstate_get(ln, t.req_hart), new_req, t.req_hart);
      n_transitions++;
    end
    pstate_set(ln, t.req_hart, new_req);

    if (NUM_HARTS > 1 && t.snp_targets[other] && t.snp_acked[other]) begin
      int unsigned new_other = pstate_get(ln, other);
      case (t.snp_rsp[other])
        RSP_TtoB: new_other = L_S;
        RSP_TtoN: new_other = L_I;
        RSP_BtoN: new_other = L_I;
        default:  ;   // TtoT / BtoB / NtoN: nothing changed
      endcase
      if (new_other != pstate_get(ln, other)) begin
        cg_trans.sample(pstate_get(ln, other), new_other, other);
        n_transitions++;
      end
      pstate_set(ln, other, new_other);
    end
  endfunction

  function void report_phase(uvm_phase phase);
    real c1_i, sn_i, tr_i;

    if (!cfg.cov_enable) return;

    c1_i = cg_c1.get_inst_coverage();
    sn_i = cg_snoop.get_inst_coverage();
    tr_i = cg_trans.get_inst_coverage();

    `uvm_info("COV_COH", $sformatf(
      "C1 table %0.2f%%  snoop %0.2f%%  transitions %0.2f%%  (%0d transactions, %0d transitions)",
      c1_i, sn_i, tr_i, n_sampled, n_transitions), UVM_LOW)

    `uvm_info("COV_COH", $sformatf(
      {"state axis: %0d shadow resyncs from hardware evidence, %0d silent ",
       "acquires (must be 0), %0d illegal C1 cells (must be 0)"},
      n_resync_inband, n_silent_acquire, n_c1_illegal), UVM_LOW)

    `uvm_info("COV_COH", $sformatf(
      {"C1 equivalence (mesi_ctrl's table vs dcache.sv:481): %0d request(s) ",
       "checked against the REAL tag state, %0d disagreement(s), %0d skipped ",
       "as the legal in-flight invalidation (UPGRADE raised from S, line taken ",
       "away before the sample). The two copies exist because dcache.sv:282 ",
       "wires the only mesi_ctrl instance to snoop events only."},
      n_c1eq_checked, n_c1eq_bad, n_c1eq_raced), UVM_LOW)

    if (n_sampled > 20 && n_c1eq_checked == 0)
      `uvm_error("COV_COH",
        {"C1 equivalence check sampled NOTHING while the bus carried ",
         "transactions. The check is not running, which is not the same as ",
         "finding nothing."})

    `uvm_info("COV_COH", $sformatf(
      {"C1 INTENT (mesi_ctrl's I row vs dcache.sv:483): %0d disagreement(s) ",
       "between the MSHR's write intent and the request type emitted. This is ",
       "the half m9 breaks and the state test above cannot see."},
      n_c1eq_intent), UVM_LOW)

    if (n_c1eq_intent != 0)
      `uvm_error("COV_COH", $sformatf(
        {"C1 EQUIVALENCE (INTENT): %0d request(s) whose type contradicts the ",
         "MSHR's write intent; first had wi=%0d asking %0d. mesi_ctrl's I row ",
         "answers EV_LOAD with GetS and EV_STORE with GetM (:119,:120), and ",
         "dcache.sv:483 re-derives that from mshr_wi_q. A hit is those two ",
         "copies having DRIFTED -- which is exactly mutation m9."},
        n_c1eq_intent, first_bad_intent_wi, first_bad_intent_req))

    if (n_c1eq_bad != 0)
      `uvm_error("COV_COH", $sformatf(
        {"C1 EQUIVALENCE: %0d request(s) that mesi_ctrl's table forbids from ",
         "the line state actually held, first was state %0d asking %0d. ",
         "mesi_ctrl issues GetS/GetM from LINE_I only (:119,:120) and Upgrade ",
         "from LINE_S only (:141); E and M issue nothing (:152-157,:169-171). ",
         "The direction is chosen so an in-flight downgrade cannot produce it, ",
         "so this is the two copies of the request rule having DRIFTED, not a ",
         "sampling artefact."},
        n_c1eq_bad, first_bad_state, first_bad_req))

    if (n_sampled == 0)
      `uvm_error("COV_COH",
        {"ZERO completed coherence transactions were binned. Either nothing was ",
         "shared, or sb_coherence is not connected to this model -- and both ",
         "produce a coverage report that looks like a clean 0%."})

    if (n_sampled != 0 && n_transitions == 0)
      `uvm_warning("COV_COH",
        "transactions occurred but NO line ever changed state -- the protocol was never exercised")
  endfunction

endclass
