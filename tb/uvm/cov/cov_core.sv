// Microarchitectural coverage: occupancy, issue width, traps,.
`uvm_analysis_imp_decl(_cc_rvfi)
`uvm_analysis_imp_decl(_cc_sys)

class cov_core extends uvm_component;
  `uvm_component_utils(cov_core)

  uvm_analysis_imp_cc_rvfi #(rvfi_txn, cov_core) rvfi_imp;
  uvm_analysis_imp_cc_sys  #(sys_txn,  cov_core) sys_imp;

  cpu_cfg cfg;
  virtual core_probe_if probe [];

  virtual snoop_if snp_vif;

  protected virtual core_probe_if p0;

  int unsigned n_samples;
  int unsigned retired_this_cycle [NUM_HARTS];
  longint unsigned last_cycle;

  covergroup cg_occupancy with function sample(int unsigned a_hart,
                                               int unsigned a_rob,
                                               int unsigned a_sq,
                                               int unsigned a_lq,
                                               bit          a_rec,
                                               int unsigned a_cause);
    option.per_instance = 1;

    cp_h : coverpoint a_hart { bins hart0 = {0}; bins hart1 = {1}; }

    cp_rob_b : coverpoint a_rob {
      bins empty = {0};
      bins light = {1};
      bins busy  = {2};
      bins full  = {3};
    }

    cp_sq_b : coverpoint a_sq {
      bins empty = {0};
      bins light = {1};
      bins busy  = {2};
      bins full  = {3};
    }

    cp_lq_b : coverpoint a_lq {
      bins empty = {0};
      bins light = {1};
      bins busy  = {2};
      bins full  = {3};
    }

    cp_rec : coverpoint a_rec {
      bins normal     = {0};
      bins recovering = {1};
    }

    cp_rcause : coverpoint a_cause {
      bins none        = {0};   // not recovering, or the unclassified trigger cycle
      bins mispredict  = {1};
      bins violation   = {2};
      bins trap        = {3};   // interrupt or exception
      bins actor_fence = {4};   // fence / fence.i -- the D_FLUSH_SCAN path
      bins actor_other = {5};   // mret, or an SC at the head
    }

    x_rob_cause : cross cp_rob_b, cp_rcause;

    x_sq_lq   : cross cp_sq_b, cp_lq_b;

    x_hart_rob : cross cp_h, cp_rob_b;
  endgroup

  int unsigned n_onset [2][4];   // [kind-1][rob bucket] -- the raw shape
  int unsigned n_snap_full, n_snap_full_bpr;

  covergroup cg_onset with function sample(int unsigned a_rob, int unsigned a_kind);
    option.per_instance = 1;

    cp_o_rob : coverpoint a_rob {
      bins empty = {0};
      bins light = {1};
      bins busy  = {2};
      bins full  = {3};
    }

    cp_o_kind : coverpoint a_kind {
      bins mispredict = {1};
      bins violation  = {2};
    }

    x_onset : cross cp_o_rob, cp_o_kind;
  endgroup

  covergroup cg_issue with function sample(int unsigned a_width, bit a_trap);
    option.per_instance = 1;

    cp_w : coverpoint a_width {
      bins none   = {0};
      bins single = {1};
      bins dual   = {2};
      option.at_least = 10;
    }

    cp_trap_b : coverpoint a_trap {
      bins no_trap = {0};
      bins trap    = {1};
    }

    cp_w_retired : coverpoint a_width iff (a_width != 0) {
      bins single = {1};
      bins dual   = {2};
    }

    x_w_trap : cross cp_w_retired, cp_trap_b;
  endgroup

  covergroup cg_occ_snoop with function sample(int unsigned a_rob_b,
                                               int unsigned a_hart,
                                               bit          a_snoop);
    option.per_instance = 1;
    cp_os_rob : coverpoint a_rob_b {
      bins empty = {0}; bins low = {1}; bins busy = {2}; bins full = {3};
    }
    cp_os_hart : coverpoint a_hart { bins hart0 = {0}; bins hart1 = {1}; }
    cp_os_snoop : coverpoint a_snoop iff (a_snoop) { bins arrived = {1}; }
    x_occ_snoop : cross cp_os_rob, cp_os_snoop, cp_os_hart;
  endgroup

  covergroup cg_snapshot with function sample(int unsigned a_occ, bit a_bpr);
    option.per_instance = 1;
    cp_snap_occ : coverpoint a_occ {
      bins empty = {0};
      bins one   = {1};
      bins two   = {2};
      bins three = {3};
      bins full  = {4};      // == SNAP_N: a cf op cannot dispatch, it STALLS
    }
    cp_snap_bpr : coverpoint a_bpr iff (a_bpr) { bins mispredict = {1}; }
    x_snap_bpr  : cross cp_snap_occ, cp_snap_bpr;
  endgroup

  covergroup cg_starve with function sample(int unsigned a_hart, bit a_starve);
    option.per_instance = 1;
    cp_s : coverpoint a_starve {
      bins none    = {0};
      bins starved = {1};
    }
    cp_sh : coverpoint a_hart { bins hart0 = {0}; bins hart1 = {1}; }
    x_starve_hart : cross cp_s, cp_sh;
  endgroup

  covergroup cg_selftest with function sample(int unsigned a_v);
    option.per_instance = 1;
    cp_v : coverpoint a_v {
      bins b0 = {0};
      bins b1 = {1};
      bins b2 = {2};
      bins b3 = {3};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rvfi_imp = new("rvfi_imp", this);
    sys_imp  = new("sys_imp",  this);
    cg_occupancy = new();
    cg_issue     = new();
    cg_starve    = new();
    cg_snapshot  = new();
    cg_selftest  = new();
    cg_occ_snoop = new();
    cg_onset     = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("COV_CORE", "no cpu_cfg")

    if ((NUM_HARTS != 2) || (COMMIT_W != 2))
      `uvm_fatal("COV_CORE", $sformatf(
        {"NUM_HARTS=%0d COMMIT_W=%0d, but the per-hart and per-slot coverpoints ",
         "in cov_core.sv, cov_lrsc.sv, cov_coherence.sv and cov_isa.sv are ",
         "hand-enumerated for 2 of each. Extend those bins (do NOT go back to ",
         "`bins n[] = {[0:N-1]}` -- it collapses under a cross on this tool; ",
         "see scripts/cov_bin_audit.sh)."}, NUM_HARTS, COMMIT_W))

    probe = new[cfg.num_harts];
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      string key = $sformatf("core_probe_vif_%0d", h);
      if (!uvm_config_db #(virtual core_probe_if)::get(this, "", key, probe[h]))
        `uvm_fatal("COV_CORE", $sformatf(
          {"no '%s'. Occupancy and recovery are bound into core, not ports -- ",
           "without the probe this model can only bin what RETIRED, which ",
           "measures the cycles where things went well."}, key))
    end
    p0 = probe[0];

    if (!uvm_config_db #(virtual snoop_if)::get(this, "", "snoop_vif", snp_vif))
      `uvm_warning("COV_CORE",
        {"no snoop_vif: x_occ_snoop cannot be sampled. Occupancy and recovery ",
         "are unaffected."})
  endfunction

  task run_phase(uvm_phase phase);
    if (!cfg.cov_enable) return;
    forever begin
      @(posedge p0.clk);
      if (p0.rst_n !== 1'b1) continue;

      for (int unsigned h = 0; h < cfg.num_harts; h++) begin
        virtual core_probe_if ph = probe[h];
        cg_occupancy.sample(h,
                            ph.bucket4(int'(ph.rob_count), ROB_N, ROB_N - RENAME_W),
                            ph.bucket4(int'(ph.sq_cnt),    SQ_N,  SQ_N - 1),
                            ph.bucket4(int'(ph.lq_cnt),    LQ_N,  LQ_N - 1),
                            ph.recovering(),
                            ph.rec_cause());

        cg_snapshot.sample(int'(ph.snap_cnt), ph.rec_cause() == 1);
        if (int'(ph.snap_cnt) == SNAP_N) begin
          n_snap_full++;
          if (ph.rec_cause() == 1) n_snap_full_bpr++;
        end

        if ((snp_vif != null) && snp_vif.snp_valid[h])
          cg_occ_snoop.sample(ph.bucket4(int'(ph.rob_count), ROB_N, ROB_N - RENAME_W),
                              h, 1'b1);

        if (ph.mispredict_ex) begin
          int unsigned b = ph.bucket4(int'(ph.rob_count), ROB_N, ROB_N - RENAME_W);
          cg_onset.sample(b, 1); n_onset[0][b]++;
        end
        if (ph.trig_viol) begin
          int unsigned b = ph.bucket4(int'(ph.rob_count), ROB_N, ROB_N - RENAME_W);
          cg_onset.sample(b, 2); n_onset[1][b]++;
        end
      end
      n_samples++;
    end
  endtask

  virtual function void write_cc_rvfi(rvfi_txn t);
    if (!cfg.cov_enable) return;

    if (t.cycle != last_cycle) begin
      for (int unsigned h = 0; h < cfg.num_harts; h++) begin
        cg_issue.sample(retired_this_cycle[h], 1'b0);
        retired_this_cycle[h] = 0;
      end
      last_cycle = t.cycle;
    end

    retired_this_cycle[t.hart]++;

    if (t.trap) cg_issue.sample(retired_this_cycle[t.hart], 1'b1);
  endfunction

  virtual function void write_cc_sys(sys_txn t);
    if (!cfg.cov_enable) return;
    if (t.kind != SYS_STARVE) return;
    for (int unsigned h = 0; h < cfg.num_harts; h++)
      cg_starve.sample(h, t.starve_mask[h]);
  endfunction

  real cov_self_pct = -1.0;

  function void report_phase(uvm_phase phase);
    real occ_i, iss_i, stv_i;
    real occ_t, iss_t;
    real self_i;

    if (!cfg.cov_enable) return;

    for (int unsigned v = 0; v < 4; v++) cg_selftest.sample(v);
    self_i = cg_selftest.get_inst_coverage();
    cov_self_pct = self_i;
    `uvm_info("COV_CORE", $sformatf(
      "instrument self-test: %0.2f%% (must be 100.00)", self_i), UVM_LOW)
    if (self_i != 100.0)
      `uvm_error("COV_CORE", $sformatf(
        {"coverage SELF-TEST reads %0.2f%%, not 100%%. Four bins were sampled ",
         "one value each with no dependence on the DUT, so this is the ",
         "INSTRUMENT failing, not an uncovered design. Every coverage number ",
         "in this run is meaningless until this reads 100."}, self_i))

    if (snp_vif != null)
      `uvm_info("COV_CORE", $sformatf(
        "occupancy x snoop arrival: %0.2f%%", cg_occ_snoop.get_inst_coverage()), UVM_LOW)

    `uvm_info("COV_CORE", $sformatf(
      "snapshot ring %0.2f%% -- %0d cycle(s) with all %0d slots taken, %0d of them in a mispredict recovery",
      cg_snapshot.get_inst_coverage(), n_snap_full, SNAP_N, n_snap_full_bpr), UVM_LOW)
    if ((n_samples > 1000) && (n_snap_full == 0))
      `uvm_info("COV_CORE", $sformatf(
        {"the branch-snapshot ring NEVER filled in %0d cycle(s). SNAP_N = %0d is ",
         "deliberately under-provisioned so the exhausted-dispatch stall is ",
         "exercised; on this stimulus it was not. Defect 4f-b lived there."},
        n_samples, SNAP_N), UVM_LOW)

    occ_i = cg_occupancy.get_inst_coverage();
    iss_i = cg_issue.get_inst_coverage();
    stv_i = cg_starve.get_inst_coverage();

    `uvm_info("COV_CORE", $sformatf(
      "occupancy %0.2f%%  issue %0.2f%%  starvation %0.2f%%  (%0d cycle samples)",
      occ_i, iss_i, stv_i, n_samples), UVM_LOW)

    `uvm_info("COV_CORE", $sformatf(
      {"onset ROB depth at DETECTION  mispredict: empty %0d light %0d busy %0d ",
       "full %0d | violation: empty %0d light %0d busy %0d full %0d"},
      n_onset[0][0], n_onset[0][1], n_onset[0][2], n_onset[0][3],
      n_onset[1][0], n_onset[1][1], n_onset[1][2], n_onset[1][3]), UVM_LOW)

    if (n_samples == 0)
      `uvm_error("COV_CORE",
        "sampled ZERO cycles: this model reported coverage without observing anything")

    if ((n_samples > 0) && (occ_i == 0.0) && (iss_i == 0.0) && (stv_i == 0.0))
      `uvm_error("COV_CORE", $sformatf(
        {"every covergroup read 0.00%% after %0d samples. Coverage is not being ",
         "SCORED -- this is an instrument failure, not an uncovered design. ",
         "Check that each covergroup is declared `with function sample(...)` ",
         "and takes its values as arguments rather than reading class members."},
        n_samples))

    if (cfg.cov_assert_type_inst_differ) begin
      occ_t = cg_occupancy.get_coverage();
      iss_t = cg_issue.get_coverage();
      if ((occ_t == occ_i) && (iss_t == iss_i) && (occ_i > 0.0))
        `uvm_warning("COV_CORE", $sformatf(
          {"get_coverage() now AGREES with get_inst_coverage() (%0.2f%%). The ",
           "tool behaviour this environment works around has changed -- ",
           "revisit the instance-coverage decision and this assertion."},
          occ_t))
    end
  endfunction

endclass
