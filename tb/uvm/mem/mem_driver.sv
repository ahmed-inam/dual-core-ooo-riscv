// The reactive AXI4 slave on s1_if.
class mem_driver extends uvm_driver #(mem_txn);
  `uvm_component_utils(mem_driver)

  virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)) vif;
  cpu_cfg cfg;

  uvm_analysis_port #(mem_txn) req_ap;

  protected logic [7:0] mem [logic [axi4_pkg::ADDR_WIDTH-1:0]];

  protected int unsigned aw_hold_pct = 0;
  protected int unsigned w_stall_pct = 25;
  protected int unsigned b_hold_pct  = 20;
  protected int unsigned ar_hold_pct = 0;
  protected int unsigned r_hold_pct  = 20;
  protected int unsigned r_gap_pct   = 30;

  protected logic [axi4_pkg::M_ID_W-1:0]      aw_id_q[$], b_id_q[$], ar_id_q[$];
  protected logic [axi4_pkg::ADDR_WIDTH-1:0]  aw_ad_q[$], ar_ad_q[$];
  protected logic [2:0]                       aw_sz_q[$], ar_sz_q[$];
  protected logic [7:0]                       aw_ln_q[$], ar_ln_q[$];
  protected logic [1:0]                       aw_bt_q[$], ar_bt_q[$];

  protected logic [axi4_pkg::ADDR_WIDTH-1:0]  w_addr;
  protected logic [2:0]                       w_size;
  protected logic [1:0]                       w_bt;
  protected logic [7:0]                       w_len, w_beat;
  protected bit                               w_active;

  int unsigned n_rd, n_wr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    req_ap = new("req_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::get(
          this, "", "vif", vif))
      `uvm_fatal("MEM_DRV", "no s1_if virtual interface")
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MEM_DRV", "no cpu_cfg")

    w_stall_pct = cfg.w_stall_percent;

    if (!cfg.randomize_latency) begin
      w_stall_pct = 0; b_hold_pct = 0; r_hold_pct = 0; r_gap_pct = 0;
      aw_hold_pct = 0; ar_hold_pct = 0;
    end
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    localparam int unsigned MEM_WORDS = 65536;   // 256 KB, as sim_mem's default
    word_t img [0:MEM_WORDS-1];
    int unsigned n_nonzero = 0;

    super.start_of_simulation_phase(phase);

    if (cfg.hex_path == "")
      `uvm_fatal("MEM_DRV", "no program image: pass +HEX=<file>")

    foreach (img[i]) img[i] = '0;
    $readmemh(cfg.hex_path, img);

    foreach (img[i]) begin
      logic [axi4_pkg::ADDR_WIDTH-1:0] a = mem_pkg::RAM_BASE + (i * 4);
      if (img[i] !== '0) n_nonzero++;
      for (int b = 0; b < 4; b++) mem[a + b] = img[i][8*b +: 8];
    end

    if (n_nonzero == 0)
      `uvm_fatal("MEM_DRV", $sformatf(
        "'%s' loaded ZERO non-zero words -- file missing, empty, or wrong format",
        cfg.hex_path))

    `uvm_info("MEM_DRV", $sformatf("loaded %s: %0d non-zero words at %08h",
              cfg.hex_path, n_nonzero, mem_pkg::RAM_BASE), UVM_LOW)
  endfunction

  protected function logic [axi4_pkg::ADDR_WIDTH-1:0] next_addr(
      logic [axi4_pkg::ADDR_WIDTH-1:0] a, logic [2:0] sz,
      logic [1:0] bt, logic [7:0] len);
    logic [axi4_pkg::ADDR_WIDTH-1:0] inc, wm;
    inc = (a + (32'd1 << sz)) & ~((32'd1 << sz) - 1);
    case (bt)
      2'b00:   next_addr = a;                                   // FIXED
      2'b10:   begin                                            // WRAP
                 wm = ((32'(len) + 1) << sz) - 1;
                 next_addr = (a & ~wm) | (inc & wm);
               end
      default: next_addr = inc;                                 // INCR
    endcase
  endfunction

  protected function logic [axi4_pkg::ADDR_WIDTH-1:0] word_of(
      logic [axi4_pkg::ADDR_WIDTH-1:0] a);
    return a & ~(axi4_pkg::ADDR_WIDTH'(axi4_pkg::STRB_WIDTH - 1));
  endfunction

  protected function logic [axi4_pkg::DATA_WIDTH-1:0] rd_word(
      logic [axi4_pkg::ADDR_WIDTH-1:0] a);
    logic [axi4_pkg::ADDR_WIDTH-1:0] w = word_of(a);
    rd_word = '0;
    for (int b = 0; b < axi4_pkg::STRB_WIDTH; b++)
      rd_word[8*b +: 8] = mem.exists(w + b) ? mem[w + b] : 8'hDE;
  endfunction

  protected function void wr_word(logic [axi4_pkg::ADDR_WIDTH-1:0] a,
                                  logic [axi4_pkg::DATA_WIDTH-1:0] d,
                                  logic [axi4_pkg::STRB_WIDTH-1:0] strb);
    logic [axi4_pkg::ADDR_WIDTH-1:0] w = word_of(a);
    for (int b = 0; b < axi4_pkg::STRB_WIDTH; b++)
      if (strb[b]) mem[w + b] = d[8*b +: 8];
  endfunction

  // addr_known=0 (the B channel has no address here): inject only when no floor is set
  protected task get_response_policy(output int unsigned lat,
                                              output int unsigned gap,
                                              output logic [1:0] resp,
                                              input  bit addr_known = 0,
                                              input  logic [axi4_pkg::ADDR_WIDTH-1:0] addr = '0);
    mem_txn rsp;
    bit in_range = addr_known ? (addr >= cfg.slverr_lo) : (cfg.slverr_lo == 0);

    seq_item_port.try_next_item(rsp);
    if (rsp != null) begin
      lat = rsp.latency; gap = rsp.beat_gap; resp = rsp.resp;
      seq_item_port.item_done();
      return;
    end

    if (cfg.randomize_latency) begin
      lat  = $urandom_range(cfg.lat_min, cfg.lat_max);
      gap  = $urandom_range(cfg.gap_min, cfg.gap_max);
      resp = (cfg.slverr_percent != 0 && in_range &&
              $urandom_range(1, 100) <= cfg.slverr_percent) ? 2'b10 : 2'b00;
    end
    else begin
      lat  = cfg.fixed_delay;
      gap  = cfg.fixed_beat_delay;
      resp = 2'b00;
    end
  endtask

  task run_phase(uvm_phase phase);
    idle();
    forever begin
      wait (vif.arst_n === 1'b1);
      @(posedge vif.aclk);
      fork
        begin
          fork
            aw_thread(); w_thread(); b_thread(); ar_thread(); r_thread();
          join
        end
        @(negedge vif.arst_n);
      join_any
      disable fork;

      idle();
      aw_id_q.delete(); b_id_q.delete(); ar_id_q.delete();
      aw_ad_q.delete(); ar_ad_q.delete();
      aw_sz_q.delete(); ar_sz_q.delete();
      aw_ln_q.delete(); ar_ln_q.delete();
      aw_bt_q.delete(); ar_bt_q.delete();
      w_active = 0;
    end
  endtask

  task idle();
    vif.awready = 1'b0;
    vif.wready  = 1'b0;
    vif.bvalid  = 1'b0; vif.bid = '0; vif.bresp = 2'b00;
    vif.arready = 1'b0;
    vif.rvalid  = 1'b0; vif.rid = '0; vif.rdata = '0;
    vif.rresp   = 2'b00; vif.rlast = 1'b0;
  endtask

  task aw_thread();
    bit pend = 0;
    forever begin
      @(posedge vif.aclk);
      if (vif.awvalid && vif.awready) begin
        mem_txn t = mem_txn::type_id::create("aw");
        t.dir = MEM_WRITE; t.id = vif.awid; t.addr = vif.awaddr;
        t.len = vif.awlen; t.size = vif.awsize; t.burst = vif.awburst;
        t.t_req = longint'($time);
        req_ap.write(t);

        aw_id_q.push_back(vif.awid);   aw_ad_q.push_back(vif.awaddr);
        aw_sz_q.push_back(vif.awsize); aw_bt_q.push_back(vif.awburst);
        aw_ln_q.push_back(vif.awlen);
        pend = 0;
      end
      else pend = vif.awvalid && !vif.awready;

      @(negedge vif.aclk);
      vif.awready = pend && ($urandom_range(1, 100) > aw_hold_pct);
    end
  endtask

  task w_thread();
    forever begin
      @(negedge vif.aclk);
      vif.wready = (aw_id_q.size() > 0 || w_active)
                   && ($urandom_range(1, 100) > w_stall_pct);
      @(posedge vif.aclk);
      if (vif.wvalid && vif.wready) begin
        if (!w_active) begin
          w_addr = aw_ad_q[0]; w_size = aw_sz_q[0];
          w_bt   = aw_bt_q[0]; w_len  = aw_ln_q[0];
          w_beat = 0; w_active = 1;
        end
        wr_word(w_addr, vif.wdata, vif.wstrb);
        w_addr = next_addr(w_addr, w_size, w_bt, w_len);
        w_beat++;

        if (vif.wlast) begin
          b_id_q.push_back(aw_id_q.pop_front());
          void'(aw_ad_q.pop_front()); void'(aw_sz_q.pop_front());
          void'(aw_bt_q.pop_front()); void'(aw_ln_q.pop_front());
          w_active = 0;
          n_wr++;
        end
      end
    end
  endtask

  task b_thread();
    forever begin
      @(negedge vif.aclk);
      if (b_id_q.size() > 0 && !vif.bvalid &&
          ($urandom_range(1, 100) > b_hold_pct)) begin
        int unsigned lat, gap; logic [1:0] rsp;
        get_response_policy(lat, gap, rsp);
        repeat (lat) @(negedge vif.aclk);
        vif.bid    = b_id_q.pop_front();
        vif.bresp  = rsp;
        vif.bvalid = 1'b1;
      end
      @(posedge vif.aclk);
      if (vif.bvalid && vif.bready) begin
        @(negedge vif.aclk);
        vif.bvalid = 1'b0;
      end
    end
  endtask

  task ar_thread();
    bit pend = 0;
    forever begin
      @(posedge vif.aclk);
      if (vif.arvalid && vif.arready) begin
        mem_txn t = mem_txn::type_id::create("ar");
        t.dir = MEM_READ; t.id = vif.arid; t.addr = vif.araddr;
        t.len = vif.arlen; t.size = vif.arsize; t.burst = vif.arburst;
        t.t_req = longint'($time);
        req_ap.write(t);

        ar_id_q.push_back(vif.arid);   ar_ad_q.push_back(vif.araddr);
        ar_sz_q.push_back(vif.arsize); ar_bt_q.push_back(vif.arburst);
        ar_ln_q.push_back(vif.arlen);
        pend = 0;
      end
      else pend = vif.arvalid && !vif.arready;

      @(negedge vif.aclk);
      vif.arready = pend && ($urandom_range(1, 100) > ar_hold_pct);
    end
  endtask

  task r_thread();
    forever begin
      @(negedge vif.aclk);
      if (ar_id_q.size() > 0 && !vif.rvalid &&
          ($urandom_range(1, 100) > r_hold_pct)) begin
        logic [axi4_pkg::M_ID_W-1:0]     id  = ar_id_q.pop_front();
        logic [axi4_pkg::ADDR_WIDTH-1:0] ad  = ar_ad_q.pop_front();
        logic [2:0]                      sz  = ar_sz_q.pop_front();
        logic [1:0]                      bt  = ar_bt_q.pop_front();
        logic [7:0]                      ln  = ar_ln_q.pop_front();
        int unsigned lat, gap; logic [1:0] rsp;

        get_response_policy(lat, gap, rsp, 1, ad);
        repeat (lat) @(negedge vif.aclk);

        for (int unsigned beat = 0; beat <= int'(ln); beat++) begin
          vif.rid    = id;
          vif.rdata  = rd_word(ad);
          vif.rresp  = rsp;
          vif.rlast  = (beat == int'(ln));
          vif.rvalid = 1'b1;

          @(posedge vif.aclk);
          while (!vif.rready) @(posedge vif.aclk);

          @(negedge vif.aclk);
          vif.rvalid = 1'b0;
          vif.rlast  = 1'b0;
          ad = next_addr(ad, sz, bt, ln);

          if (beat != int'(ln))
            repeat (gap + ($urandom_range(1,100) <= r_gap_pct ? 1 : 0))
              @(negedge vif.aclk);
        end
        n_rd++;
      end
      else begin
        @(posedge vif.aclk);
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("MEM_DRV", $sformatf("served %0d reads, %0d writes", n_rd, n_wr), UVM_LOW)

    if (n_rd == 0)
      `uvm_error("MEM_DRV", "served ZERO reads: the DUT never fetched an instruction")
  endfunction

endclass
