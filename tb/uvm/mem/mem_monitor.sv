// Passive observer of the AXI4 slave interface. Never drives.
class mem_monitor extends uvm_monitor;
  `uvm_component_utils(mem_monitor)

  virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)) vif;
  cpu_cfg cfg;
  int     clk_period_ns = 10;

  uvm_analysis_port #(mem_txn) ap;

  protected mem_txn aw_q [$];
  protected mem_txn w_q  [$];
  protected mem_txn pend_wr [logic [axi4_pkg::M_ID_W-1:0]][$];
  protected mem_txn pend_rd [logic [axi4_pkg::M_ID_W-1:0]][$];

  int unsigned n_rd, n_wr;
  int unsigned n_orphan_b, n_orphan_r;
  int unsigned tag_count [2];
  longint unsigned lat_sum, lat_max;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::get(
          this, "", "vif", vif))
      `uvm_fatal("MEM_MON", "no s1_if virtual interface")
    void'(uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg));
    void'(uvm_config_db #(int)::get(this, "", "clk_period_ns", clk_period_ns));
  endfunction

  static function bit master_tag_of(logic [axi4_pkg::M_ID_W-1:0] id);
    return id[axi4_pkg::ID_WIDTH];
  endfunction

  protected function longint unsigned cycle_now();
    return longint'($time / clk_period_ns);
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      wait (vif.arst_n === 1'b1);
      fork
        begin
          fork
            aw_thread(); w_thread(); b_thread(); ar_thread(); r_thread();
          join
        end
        @(negedge vif.arst_n);
      join_any
      disable fork;

      aw_q.delete(); w_q.delete();
      pend_wr.delete(); pend_rd.delete();
    end
  endtask

  task aw_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.awvalid && vif.awready) begin
        mem_txn t = mem_txn::type_id::create("wr");
        t.dir   = MEM_WRITE;
        t.id    = vif.awid;
        t.addr  = vif.awaddr;
        t.len   = vif.awlen;
        t.size  = vif.awsize;
        t.burst = vif.awburst;
        t.t_req = cycle_now();
        aw_q.push_back(t);
        join_wr();
      end
    end
  endtask

  task w_thread();
    mem_txn cur = null;
    forever begin
      @(posedge vif.aclk);
      if (vif.wvalid && vif.wready) begin
        if (cur == null) begin
          cur = mem_txn::type_id::create("wdata");
          cur.t_first = cycle_now();
        end
        cur.beats = new[cur.beats.size() + 1](cur.beats);
        cur.strb  = new[cur.strb.size()  + 1](cur.strb);
        cur.beats[cur.beats.size()-1] = vif.wdata;
        cur.strb [cur.strb.size()-1]  = vif.wstrb;
        if (vif.wlast) begin
          cur.t_last = cycle_now();
          w_q.push_back(cur);
          cur = null;
          join_wr();
        end
      end
    end
  endtask

  protected function void join_wr();
    while (aw_q.size() > 0 && w_q.size() > 0) begin
      mem_txn a = aw_q.pop_front();
      mem_txn w = w_q.pop_front();
      a.beats   = w.beats;
      a.strb    = w.strb;
      a.t_first = w.t_first;
      a.t_last  = w.t_last;
      pend_wr[a.id].push_back(a);
    end
  endfunction

  task b_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.bvalid && vif.bready) begin
        if (pend_wr[vif.bid].size() == 0) begin
          n_orphan_b++;
          `uvm_error("MEM_MON", $sformatf(
            "B response for id=%0h with nothing outstanding", vif.bid))
        end
        else begin
          mem_txn t = pend_wr[vif.bid].pop_front();
          t.resp = vif.bresp;
          publish(t);
          n_wr++;
        end
      end
    end
  endtask

  task ar_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.arvalid && vif.arready) begin
        mem_txn t = mem_txn::type_id::create("rd");
        t.dir   = MEM_READ;
        t.id    = vif.arid;
        t.addr  = vif.araddr;
        t.len   = vif.arlen;
        t.size  = vif.arsize;
        t.burst = vif.arburst;
        t.t_req = cycle_now();
        pend_rd[vif.arid].push_back(t);
      end
    end
  endtask

  task r_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.rvalid && vif.rready) begin
        if (pend_rd[vif.rid].size() == 0) begin
          n_orphan_r++;
          `uvm_error("MEM_MON", $sformatf(
            "R beat for id=%0h with nothing outstanding", vif.rid))
        end
        else begin
          mem_txn t = pend_rd[vif.rid][0];
          if (t.beats.size() == 0) t.t_first = cycle_now();
          t.beats = new[t.beats.size() + 1](t.beats);
          t.beats[t.beats.size()-1] = vif.rdata;
          t.resp  = vif.rresp;

          if (vif.rlast) begin
            t.t_last = cycle_now();
            void'(pend_rd[vif.rid].pop_front());

            if (t.beats.size() != t.nbeats())
              `uvm_error("MEM_MON", $sformatf(
                "id=%0h RLAST after %0d beats, AWLEN/ARLEN promised %0d",
                t.id, t.beats.size(), t.nbeats()))

            publish(t);
            n_rd++;
          end
        end
      end
    end
  endtask

  protected function void publish(mem_txn t);
    longint unsigned lat = t.observed_latency();
    tag_count[master_tag_of(t.id)]++;
    lat_sum += lat;
    if (lat > lat_max) lat_max = lat;
    ap.write(t);
  endfunction

  function void report_phase(uvm_phase phase);
    longint unsigned n_total = n_rd + n_wr;
    `uvm_info("MEM_MON", $sformatf(
      "%0d reads, %0d writes; per-master {%0d, %0d}; latency avg %0d max %0d cycles",
      n_rd, n_wr, tag_count[0], tag_count[1],
      (n_total != 0) ? (lat_sum / n_total) : 0, lat_max), UVM_LOW)

    if (n_total == 0)
      `uvm_error("MEM_MON", "observed NO transactions -- the monitor is not connected")

    if (n_total != 0 && (tag_count[0] == 0 || tag_count[1] == 0))
      `uvm_warning("MEM_MON", $sformatf(
        "only one master reached memory {%0d, %0d} -- expected traffic from both harts",
        tag_count[0], tag_count[1]))

    if (n_orphan_b != 0 || n_orphan_r != 0)
      `uvm_error("MEM_MON", $sformatf(
        "%0d orphan B, %0d orphan R responses", n_orphan_b, n_orphan_r))
  endfunction

endclass
