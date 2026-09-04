// Observes the coherence bus through the bound snoop_if.
class snoop_monitor extends uvm_monitor;
  `uvm_component_utils(snoop_monitor)

  virtual snoop_if vif;
  cpu_cfg cfg;
  int     clk_period_ns = 10;

  uvm_analysis_port #(snoop_txn) ap;

  protected snoop_txn cur;                      // in its snoop or completion phase
  protected snoop_txn pend_install [NUM_HARTS]; // completed, waiting for that hart's install
  protected int unsigned install_wait_h [NUM_HARTS];

  int unsigned n_txn;
  int unsigned n_by_type [4];      // indexed by coh_req_e
  int unsigned n_snoop_in_rsv;     // snoops landing inside a reservation window
  int unsigned n_overlap_grants;   // grants while a transaction was open
  int unsigned n_ord_violation;    // the DUT's own report

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual snoop_if)::get(this, "", "vif", vif))
      `uvm_fatal("SNOOP_MON",
        {"no snoop virtual interface. It is BOUND into cluster, not a port -- ",
         "check tb_top's `bind cluster snoop_if` and the config_db set of ",
         "u_dut.u_snoop_vif, which is the one line Verilator 5.020 could not ",
         "elaborate."})
    void'(uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg));
    void'(uvm_config_db #(int)::get(this, "", "clk_period_ns", clk_period_ns));

    if (cfg != null)
      install_timeout_cyc = 8 * (cfg.lat_max + 4 * cfg.gap_max) + 64;
  endfunction

  int unsigned           n_install_timeout;

  protected int unsigned install_timeout_cyc = 448;

  protected function longint unsigned cycle_now();
    return longint'($time / clk_period_ns);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);

      if (vif.rst_n !== 1'b1) begin
        cur = null;
        foreach (pend_install[h]) pend_install[h] = null;
        continue;
      end

      sample_installs();
      if (cur != null) sample_open();
      sample_grant();
    end
  endtask

  protected function void sample_grant();
    for (int unsigned h = 0; h < NUM_HARTS; h++) begin
      if (vif.req_valid[h] && vif.req_gnt[h]) begin

        // The ordering point serialises the snoop phase; fills may overlap on
        // other lines, but a hart has one fill in flight and one line at a time.
        if (cur != null) begin
          n_overlap_grants++;
          `uvm_error("SNOOP_MON", $sformatf(
            {"hart %0d granted while a transaction was still open (%s): the ",
             "ordering point granted outside O_IDLE"},
            h, cur.convert2string()))
        end
        if (pend_install[h] != null) begin
          n_overlap_grants++;
          `uvm_error("SNOOP_MON", $sformatf(
            {"hart %0d granted while its previous transaction (%s) has not ",
             "installed: one MSHR cannot hold two fills"},
            h, pend_install[h].convert2string()))
        end
        foreach (pend_install[o])
          if ((pend_install[o] != null)
              && ((pend_install[o].req_addr >> OFF_W) == (vif.req_addr[h] >> OFF_W))) begin
            n_overlap_grants++;
            `uvm_error("SNOOP_MON", $sformatf(
              {"hart %0d granted line %08h while hart %0d is still installing it (%s): ",
               "overlapping grants on ONE line"},
              h, vif.req_addr[h], o, pend_install[o].convert2string()))
          end

        cur = snoop_txn::type_id::create("snp");
        cur.req_hart   = h;
        cur.req_type   = vif.req_type[h];
        cur.req_addr   = vif.req_addr[h];
        cur.req_atomic = vif.req_atomic[h];
        cur.granted    = 1;
        cur.t_req      = cycle_now();
        snapshot_lrsc(cur);

        n_by_type[int'(cur.req_type)]++;

        if (cur.req_type == REQ_PUTM) cur.snp_sent = 0;
      end
    end
  endfunction

  protected function void sample_installs();
    foreach (pend_install[h]) begin
      if (pend_install[h] == null) continue;
      if (vif.installed[h]) begin
        pend_install[h].installed = 1;
        publish(pend_install[h]);
        pend_install[h] = null;
      end
      else if (install_wait_h[h] >= install_timeout_cyc) begin
        n_install_timeout++;
        `uvm_error("SNOOP_MON", $sformatf(
          {"no req_installed within %0d cycles of completion for %s. Publishing ",
           "with installed=0, so is_quiescent() is false and sb_coherence will ",
           "SKIP the backdoor sample rather than take it mid-transient. The ",
           "bound scales with cfg.lat_max/gap_max; if this fires, the install ",
           "is genuinely not arriving rather than merely being slow."},
          install_timeout_cyc, pend_install[h].convert2string()))
        publish(pend_install[h]);
        pend_install[h] = null;
      end
      else install_wait_h[h]++;
    end
  endfunction

  protected function void sample_open();
    if (vif.snp_valid != '0) begin
      cur.snp_sent    = 1;
      cur.snp_type    = vif.snp_type;
      cur.snp_targets = cur.snp_targets | vif.snp_valid;
      if (cur.t_snp == 0) cur.t_snp = cycle_now();

      if ((vif.rsv_valid & vif.snp_valid) != '0) n_snoop_in_rsv++;
    end

    for (int unsigned h = 0; h < NUM_HARTS; h++)
      if (vif.snp_ack[h]) begin
        cur.snp_acked[h] = 1'b1;
        cur.snp_rsp[h]   = vif.snp_rsp[h];
      end

    if (vif.ord_violation) begin
      cur.ord_violation = 1;
      n_ord_violation++;
    end
    if (vif.prot_deferred) cur.prot_deferred = 1;

    if (vif.cmp_valid != '0) begin
      cur.completed  = 1;
      cur.cmp_shared = vif.cmp_shared;
      cur.cmp_dirty  = vif.cmp_dirty;
      cur.t_cmp      = cycle_now();
      snapshot_lrsc(cur);

      if (vif.installed[cur.req_hart]) begin
        cur.installed = 1;
        publish(cur);
      end
      else begin
        pend_install[cur.req_hart]   = cur;
        install_wait_h[cur.req_hart] = 0;
      end
      cur = null;
    end
  endfunction

  protected function void snapshot_lrsc(snoop_txn t);
    t.lr_valid    = vif.lr_valid;
    t.sc_valid    = vif.sc_valid;
    t.sc_success  = vif.sc_success;
    t.rsv_valid   = vif.rsv_valid;
    t.backing_off = vif.backing_off;
    t.snoop_clear = vif.snoop_clear;
    t.trap_clear  = vif.trap_clear;
    foreach (t.acc_addr[i]) t.acc_addr[i] = vif.acc_addr[i];
    foreach (t.prot_addr[i]) t.prot_addr[i] = vif.prot_addr[i];
  endfunction

  protected function void publish(snoop_txn t);
    n_txn++;
    ap.write(t);
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SNOOP_MON", $sformatf(
      "%0d transactions: GetS=%0d GetM=%0d Upgrade=%0d PutM=%0d",
      n_txn, n_by_type[int'(REQ_GETS)], n_by_type[int'(REQ_GETM)],
      n_by_type[int'(REQ_UPGRADE)], n_by_type[int'(REQ_PUTM)]), UVM_LOW)
    `uvm_info("SNOOP_MON", $sformatf(
      "snoops landing inside a reservation window: %0d", n_snoop_in_rsv), UVM_LOW)

    if (n_txn == 0)
      `uvm_error("SNOOP_MON",
        "observed NO coherence transactions -- either the bind is wrong, or nothing was shared")

    if (n_ord_violation != 0)
      `uvm_warning("SNOOP_MON", $sformatf(
        "ordering point self-reported %0d violation(s) -- cross-check against sb_coherence",
        n_ord_violation))

    if (n_overlap_grants != 0)
      `uvm_error("SNOOP_MON", $sformatf(
        "%0d overlapping grants on one line or one hart: the ordering point lost its atomicity",
        n_overlap_grants))
  endfunction

endclass
