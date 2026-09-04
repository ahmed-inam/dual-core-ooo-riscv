// The reservation window: LR->SC distance, why reservations.
`uvm_analysis_imp_decl(_lr_snoop)

class cov_lrsc extends uvm_component;
  `uvm_component_utils(cov_lrsc)

  uvm_analysis_imp_lr_snoop #(snoop_txn, cov_lrsc) snoop_imp;

  cpu_cfg          cfg;
  virtual snoop_if vif;
  int              clk_period_ns = 10;

  protected longint unsigned lr_cycle    [NUM_HARTS];
  protected bit              window_open [NUM_HARTS];
  protected bit              snooped_in_window [NUM_HARTS];      // unqualified
  protected bit              snooped_line_in_window [NUM_HARTS]; // line-qualified
  protected bit              backed_off_in_window [NUM_HARTS];
  protected bit              trap_killed_in_window  [NUM_HARTS];
  protected bit              snoop_killed_in_window [NUM_HARTS];
  protected word_t           window_addr [NUM_HARTS];

  protected logic [NUM_HARTS-1:0] lr_prev, sc_prev, rsv_prev, back_prev;
  protected bit                   seen_first;

  int unsigned kill_reason;      // 0 none, 1 snoop, 2 trap, 3 both

  int unsigned n_sc_illegal;
  int unsigned n_dist_min = 32'hFFFF_FFFF;
  int unsigned n_dist_max;
  int unsigned dist_bkt;         // bucketed LR->SC distance

  localparam int RSV_NONE = 0;
  localparam int RSV_OPEN = 1;
  localparam int RSV_BACK = 2;

  int unsigned n_lr, n_sc, n_sc_ok, n_sc_fail;
  int unsigned n_snoop_in_window, n_backoff, n_atomic;
  int unsigned n_txn_snoop_qual;      // line-qualified: the architectural event
  int unsigned n_txn_snoop_unqual;    // any reservation touched: what the RTL acts on
  int unsigned n_snoop_line_in_window;   // the SNOOP_MON question


  covergroup cg_window with function sample(int unsigned a_hart,
                                            bit          a_ok,
                                            bit          a_rsv,
                                            int unsigned a_kill);
    option.per_instance = 1;

    cp_h : coverpoint a_hart { bins hart0 = {0}; bins hart1 = {1}; }

    cp_out : coverpoint a_ok {
      bins failed  = {0};
      bins success = {1};
    }

    cp_rsv : coverpoint a_rsv {
      bins gone  = {0};
      bins valid = {1};
    }

    cp_kill : coverpoint a_kill {
      bins none  = {0};
      bins snoop = {1};
      bins trap  = {2};
      bins both  = {3};
    }

    x_out_rsv : cross cp_out, cp_rsv {
      illegal_bins valid_but_failed = binsof(cp_out.failed) && binsof(cp_rsv.valid);
    }

    x_out_kill : cross cp_out, cp_kill {
      illegal_bins killed_yet_succeeded = binsof(cp_out.success) &&
                                          (binsof(cp_kill.snoop) || binsof(cp_kill.trap) ||
                                           binsof(cp_kill.both));
    }

    x_hart_out : cross cp_h, cp_out;
  endgroup

  covergroup cg_interaction with function sample(bit a_snoop_win,
                                                 bit a_ok,
                                                 bit a_backoff,
                                                 bit a_atomic);
    option.per_instance = 1;

    cp_snoop_win : coverpoint a_snoop_win {
      bins quiet_window  = {0};
      bins snooped_window = {1};
    }

    cp_o2 : coverpoint a_ok {
      bins failed  = {0};
      bins success = {1};
    }

    cp_back : coverpoint a_backoff {
      bins never    = {0};
      bins backed_off = {1};
    }

    cp_atomic : coverpoint a_atomic {
      bins normal = {0};
      bins write_intent = {1};
    }

    x_snoop_outcome : cross cp_snoop_win, cp_o2;

    x_backoff_outcome : cross cp_back, cp_o2;
    x_atomic_snoop    : cross cp_atomic, cp_snoop_win;
  endgroup

  covergroup cg_distance with function sample(int unsigned a_dist,
                                              int unsigned a_hart,
                                              bit          a_snoop_win);
    option.per_instance = 1;
    cp_d : coverpoint a_dist {
      bins immediate = {0};    // < 4 cycles
      bins near      = {1};    // 4..15
      bins mid       = {2};    // 16..63
      bins far       = {3};    // 64+
    }
    cp_dh : coverpoint a_hart { bins hart[] = {[0:NUM_HARTS-1]}; }
    x_dist_snoop : cross cp_d, cp_dsnoop;
    cp_dsnoop : coverpoint a_snoop_win {
      bins quiet = {0};
      bins snooped = {1};
    }
  endgroup

  covergroup cg_rsv_trans with function sample(int unsigned a_from,
                                               int unsigned a_to,
                                               int unsigned a_hart);
    option.per_instance = 1;
    cp_t : coverpoint {a_from, a_to} {
      bins opened          = {{RSV_NONE, RSV_OPEN}};
      bins closed          = {{RSV_OPEN, RSV_NONE}};
      bins opened_backoff  = {{RSV_OPEN, RSV_BACK}};
      bins backoff_closed  = {{RSV_BACK, RSV_NONE}};
    }
    cp_th : coverpoint a_hart { bins hart0 = {0}; bins hart1 = {1}; }
    x_trans_hart : cross cp_t, cp_th;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    snoop_imp     = new("snoop_imp", this);
    cg_window     = new();
    cg_interaction = new();
    cg_distance   = new();
    cg_rsv_trans  = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("COV_LRSC", "no cpu_cfg")
    if (!uvm_config_db #(virtual snoop_if)::get(this, "", "snoop_vif", vif))
      `uvm_fatal("COV_LRSC",
        {"no snoop_vif. This model samples the bus PER CYCLE, not only on ",
         "snoop_txn -- a failing SC generates no coherence transaction, so a ",
         "transaction-driven model would see almost none of them."})
    void'(uvm_config_db #(int)::get(this, "", "clk_period_ns", clk_period_ns));
  endfunction

  protected function longint unsigned cycle_now();
    return longint'($time / clk_period_ns);
  endfunction

  protected function int unsigned dist_bucket(longint unsigned d);
    if (d < 4)  return 0;
    if (d < 16) return 1;
    if (d < 64) return 2;
    return 3;
  endfunction

  task run_phase(uvm_phase phase);
    if (!cfg.cov_enable) return;

    forever begin
      @(posedge vif.clk);

      if (vif.rst_n !== 1'b1) begin
        seen_first = 0;
        foreach (window_open[h]) begin
          window_open[h]          = 0;
          snooped_in_window[h]    = 0;
          snooped_line_in_window[h] = 0;
          backed_off_in_window[h] = 0;
          trap_killed_in_window[h]  = 0;
          snoop_killed_in_window[h] = 0;
        end
        continue;
      end

      if (!seen_first) begin
        lr_prev   = vif.lr_valid;
        sc_prev   = vif.sc_valid;
        rsv_prev  = vif.rsv_valid;
        back_prev = vif.backing_off;
        seen_first = 1;
        continue;
      end

      sample_cycle();

      lr_prev   = vif.lr_valid;
      sc_prev   = vif.sc_valid;
      rsv_prev  = vif.rsv_valid;
      back_prev = vif.backing_off;
    end
  endtask

  protected function void sample_cycle();
    logic [NUM_HARTS-1:0] lr_rise   = vif.lr_valid    & ~lr_prev;
    logic [NUM_HARTS-1:0] sc_rise   = vif.sc_valid    & ~sc_prev;
    logic [NUM_HARTS-1:0] rsv_rise  = vif.rsv_valid   & ~rsv_prev;
    logic [NUM_HARTS-1:0] rsv_fall  = ~vif.rsv_valid  & rsv_prev;
    logic [NUM_HARTS-1:0] back_rise = vif.backing_off & ~back_prev;
    logic [NUM_HARTS-1:0] back_fall = ~vif.backing_off & back_prev;

    for (int unsigned h = 0; h < NUM_HARTS; h++) begin

      if (lr_rise[h]) begin
        n_lr++;
        lr_cycle[h]             = cycle_now();
        window_open[h]          = 1;
        snooped_in_window[h]    = 0;
        snooped_line_in_window[h] = 0;
        backed_off_in_window[h] = 0;
        trap_killed_in_window[h]  = 0;
        snoop_killed_in_window[h] = 0;
        window_addr[h]          = vif.acc_addr[h];
      end

      if (window_open[h] && vif.trap_clear[h])  trap_killed_in_window[h]  = 1;
      if (window_open[h] && vif.snoop_clear[h]) snoop_killed_in_window[h] = 1;

      if (window_open[h] && vif.snp_valid[h]) begin
        if (!snooped_in_window[h]) n_snoop_in_window++;
        snooped_in_window[h] = 1;
        if (vif.snp_addr >> OFF_W == window_addr[h] >> OFF_W) begin
          if (!snooped_line_in_window[h]) n_snoop_line_in_window++;
          snooped_line_in_window[h] = 1;
        end
      end

      if (back_rise[h]) begin
        n_backoff++;
        if (window_open[h]) backed_off_in_window[h] = 1;
      end

      if (rsv_rise[h]) begin
        cg_rsv_trans.sample(RSV_NONE, RSV_OPEN, h);
      end
      if (rsv_fall[h]) begin
        if (vif.backing_off[h]) cg_rsv_trans.sample(RSV_OPEN, RSV_BACK, h);
        else                    cg_rsv_trans.sample(RSV_OPEN, RSV_NONE, h);
      end
      if (back_fall[h]) begin
        cg_rsv_trans.sample(RSV_BACK, RSV_NONE, h);
      end

      if (sc_rise[h]) begin
        n_sc++;
        if (vif.sc_success[h]) n_sc_ok++; else n_sc_fail++;

        kill_reason = {trap_killed_in_window[h], snoop_killed_in_window[h]} == 2'b00 ? 0 :
                      ({trap_killed_in_window[h], snoop_killed_in_window[h]} == 2'b01 ? 1 :
                      ({trap_killed_in_window[h], snoop_killed_in_window[h]} == 2'b10 ? 2 : 3));

        dist_bkt = window_open[h] ? dist_bucket(cycle_now() - lr_cycle[h]) : 0;

        if (window_open[h]) begin
          int unsigned d = int'(cycle_now() - lr_cycle[h]);
          if (d < n_dist_min) n_dist_min = d;
          if (d > n_dist_max) n_dist_max = d;
        end

        check_sc_legality(h, vif.sc_success[h], vif.rsv_valid[h], kill_reason,
                          sc_targets_reserved_line(h));

        cg_window.sample(h, vif.sc_success[h], vif.rsv_valid[h], kill_reason);
        cg_interaction.sample(snooped_line_in_window[h], vif.sc_success[h],
                              backed_off_in_window[h], 1'b0);
        cg_distance.sample(dist_bkt, h, snooped_in_window[h]);

        window_open[h] = 0;
      end
    end
  endfunction

  protected function bit sc_targets_reserved_line(int unsigned h);
    return (vif.acc_addr[h] >> OFF_W) == (vif.prot_addr[h] >> OFF_W);
  endfunction

  protected function void check_sc_legality(int unsigned h, bit ok, bit rsv,
                                            int unsigned kill, bit same_line);
    if (!ok && rsv && same_line) begin
      n_sc_illegal++;
      `uvm_error("COV_LRSC", $sformatf(
        {"hart %0d: SC FAILED while its reservation read VALID at the verdict ",
         "instant. The reservation logic and the SC verdict disagree -- this is ",
         "the shape S6-6.8 fixed, not an uncovered case."}, h))
    end
    if (ok && (kill != 0)) begin
      n_sc_illegal++;
      `uvm_error("COV_LRSC", $sformatf(
        {"hart %0d: SC SUCCEEDED after its reservation was killed (cause %0d: ",
         "1=snoop 2=trap 3=both). An SC completing without a valid reservation ",
         "is an ATOMICITY VIOLATION."}, h, kill))
    end
  endfunction

  virtual function void write_lr_snoop(snoop_txn t);
    if (!cfg.cov_enable) return;
    if (!t.req_atomic)   return;

    n_atomic++;
    if (t.snoop_hit_reservation())         n_txn_snoop_qual++;
    if (t.snoop_touched_any_reservation()) n_txn_snoop_unqual++;
    cg_interaction.sample(t.snoop_hit_reservation(), t.sc_success[t.req_hart],
                          t.backing_off[t.req_hart], 1'b1);
  endfunction

  function void report_phase(uvm_phase phase);
    real w_i, i_i, d_i, t_i;

    if (!cfg.cov_enable) return;

    `uvm_info("COV_LRSC", $sformatf(
      {"snoop-in-window, TRANSACTION path: %0d line-qualified, %0d touching ",
       "any reservation. The difference is the design's precision limit, not ",
       "a discrepancy: the RTL clears a reservation without comparing an ",
       "address (lrsc_unit.sv:173, cluster.sv:491, mesi_ctrl.sv:131 row I)."},
      n_txn_snoop_qual, n_txn_snoop_unqual), UVM_LOW)

    w_i = cg_window.get_inst_coverage();
    i_i = cg_interaction.get_inst_coverage();
    d_i = cg_distance.get_inst_coverage();
    t_i = cg_rsv_trans.get_inst_coverage();

    if (n_dist_min != 32'hFFFF_FFFF)
      `uvm_info("COV_LRSC", $sformatf(
        {"LR->SC distance: min %0d cycles, max %0d. cp_d.immediate is the ",
         "under-4 bucket -- if min is never below 4 on a program with an sc.w ",
         "in the instruction after its lr.w, that bin is unreachable on this ",
         "LSQ and belongs in COVERAGE_PROOFS.md, not in a stimulus list."},
        n_dist_min, n_dist_max), UVM_LOW)


    `uvm_info("COV_LRSC", $sformatf(
      "window %0.2f%%  interaction %0.2f%%  distance %0.2f%%  transitions %0.2f%%",
      w_i, i_i, d_i, t_i), UVM_LOW)
    `uvm_info("COV_LRSC", $sformatf(
      "%0d LR, %0d SC (%0d ok, %0d failed); %0d snoops in window; %0d back-offs; %0d write-intent",
      n_lr, n_sc, n_sc_ok, n_sc_fail, n_snoop_in_window, n_backoff, n_atomic), UVM_LOW)

    `uvm_info("COV_LRSC", $sformatf(
      {"snoops in window: %0d unqualified (any address -- what the RTL clears ",
       "on), %0d line-qualified (the reserved line -- what SNOOP_MON counts). ",
       "The difference, %0d, is spurious reservation loss: architecturally ",
       "legal, and the reason cp_kill reads `both` on any program whose peer ",
       "stores anywhere during the window."},
      n_snoop_in_window, n_snoop_line_in_window,
      n_snoop_in_window - n_snoop_line_in_window), UVM_LOW)

    `uvm_info("COV_LRSC", $sformatf(
      {"SC legality: %0d violation(s) (reservation-valid-but-SC-failed, or ",
       "SC-succeeded-after-kill). These are checked PROCEDURALLY -- the ",
       "cross-level illegal_bins that declare them are dropped by this tool."},
      n_sc_illegal), UVM_LOW)

    if (n_lr == 0)
      `uvm_error("COV_LRSC",
        "NO LR executed: nothing in this run exercised the atomics path at all")

    if (n_lr != 0 && n_snoop_in_window == 0)
      `uvm_warning("COV_LRSC",
        {"LR/SC ran, but NO snoop ever landed inside an open reservation ",
         "window. That is the region 6.9, 6.10 and 6.11 lived in. Nothing in ",
         "this run supports any claim about LR/SC behaviour under contention."})

    if (n_sc != 0 && n_sc_fail == 0)
      `uvm_warning("COV_LRSC",
        "every SC succeeded: the reservation-loss path was never exercised")

    if (n_backoff == 0)
      `uvm_warning("COV_LRSC",
        "backing_off never asserted: the 6.9 livelock-avoidance path was not exercised")
  endfunction

endclass
