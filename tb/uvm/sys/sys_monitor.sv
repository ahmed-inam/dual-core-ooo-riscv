// The D-request surface and starvation events.
class sys_monitor extends uvm_monitor;
  `uvm_component_utils(sys_monitor)

  virtual sys_if vif;
  cpu_cfg cfg;
  int     clk_period_ns = 10;

  uvm_analysis_port #(sys_txn) ap;

  event  tohost_seen;
  bit    terminated;
  word_t exit_payload;

  protected logic [NUM_HARTS-1:0] starve_prev;
  protected bit                   seen_first;

  int unsigned n_dreq, n_dwr, n_starve_rise;
  int unsigned n_illegal_tohost;
  longint unsigned starve_cycles [NUM_HARTS];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual sys_if)::get(this, "", "vif", vif))
      `uvm_fatal("SYS_MON", "no sys_if virtual interface")
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SYS_MON", "no cpu_cfg")
    void'(uvm_config_db #(int)::get(this, "", "clk_period_ns", clk_period_ns));
  endfunction

  protected function longint unsigned cycle_now();
    return longint'($time / clk_period_ns);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);

      if (vif.rst_n !== 1'b1) begin
        seen_first  = 0;
        starve_prev = '0;
        continue;
      end

      sample_dreq();
      sample_starve();
    end
  endtask

  protected function void sample_dreq();
    for (int unsigned h = 0; h < NUM_HARTS; h++) begin
      if (!vif.dreq[h]) continue;

      n_dreq++;
      if (vif.dwe[h]) n_dwr++;

      if (vif.dwe[h] && (vif.daddr[h] == cfg.tohost_addr)) begin
        sys_txn t = sys_txn::type_id::create("tohost");
        t.kind  = SYS_TOHOST;
        t.hart  = h;
        t.we    = 1;
        t.addr  = vif.daddr[h];
        t.wdata = vif.dwdata[h];
        t.cycle = cycle_now();

        if (t.is_illegal_tohost()) begin
          n_illegal_tohost++;
          `uvm_error("SYS_MON", $sformatf(
            {"hart %0d wrote tohost (%08h). Only hart 0 may report -- HTIF is a ",
             "single dword with one owner (crt0_multihart.S). This is a DUT ",
             "failure, not an end-of-test."}, h, t.wdata))
        end
        else if (t.is_termination() && !terminated) begin
          terminated   = 1;
          exit_payload = t.wdata;
          `uvm_info("SYS_MON", $sformatf(
            "tohost <= %08h (%s, exit code %0d) at cycle %0d",
            t.wdata, (t.wdata == 1) ? "PASS" : "FAIL", t.exit_code(), t.cycle), UVM_LOW)
          -> tohost_seen;
        end

        ap.write(t);
      end
      else begin
        sys_txn t = sys_txn::type_id::create("dreq");
        t.kind  = SYS_DREQ;
        t.hart  = h;
        t.we    = vif.dwe[h];
        t.addr  = vif.daddr[h];
        t.wdata = vif.dwdata[h];
        t.cycle = cycle_now();
        ap.write(t);
      end
    end
  endfunction

  protected function void sample_starve();
    logic [NUM_HARTS-1:0] rise;

    if (!seen_first) begin
      starve_prev = vif.ev_starve;
      seen_first  = 1;
      return;
    end

    rise = vif.ev_starve & ~starve_prev;

    for (int unsigned h = 0; h < NUM_HARTS; h++)
      if (vif.ev_starve[h]) starve_cycles[h]++;

    if (rise != '0) begin
      sys_txn t = sys_txn::type_id::create("starve");
      t.kind        = SYS_STARVE;
      t.starve_mask = vif.ev_starve;
      t.cycle       = cycle_now();
      n_starve_rise++;
      ap.write(t);
    end

    starve_prev = vif.ev_starve;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SYS_MON", $sformatf(
      "%0d D-requests (%0d writes); starvation onsets %0d, cycles {%0d, %0d}",
      n_dreq, n_dwr, n_starve_rise, starve_cycles[0],
      (NUM_HARTS > 1) ? starve_cycles[1] : 0), UVM_LOW)

    if (n_dreq == 0)
      `uvm_error("SYS_MON",
        "observed ZERO D-requests -- the tap is not connected, or no hart executed a load or store")

    if (!terminated)
      `uvm_warning("SYS_MON",
        {"no tohost store observed: the program never reported a result. Any ",
         "pass here describes an incomplete run."})
    else if (cfg.expected_tohost == 0)
      `uvm_info("SYS_MON", $sformatf(
        {"program reported %08h; this test does not judge the payload ",
         "(expected_tohost=0). Whether that outcome was PERMITTED is answered ",
         "by run_litmus.sh against herd, not here."}, exit_payload), UVM_LOW)
    else if (exit_payload != cfg.expected_tohost)
      `uvm_error("SYS_MON", $sformatf(
        "program reported %08h, expected %08h (test number %0d, expected %0d)",
        exit_payload, cfg.expected_tohost,
        exit_payload >> 1, cfg.expected_tohost >> 1))

    if (n_illegal_tohost != 0)
      `uvm_error("SYS_MON", $sformatf(
        "%0d tohost write(s) from a hart other than 0", n_illegal_tohost))
  endfunction

endclass
