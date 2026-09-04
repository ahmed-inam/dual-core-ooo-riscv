// Responds on one slave interface.

class axi4_slv_driver;

  virtual axi4_if #(.ID_W(M_ID_W)) vif;
  string name = "SLV_DRV";

  int unsigned aw_hold_pct  = 0;
  int unsigned ooo_pct      = 0;   // percent chance to serve a DIFFERENT-ID entry first
  int unsigned ar_hold_pct  = 0;
  int unsigned w_stall_pct  = 25;
  int unsigned b_hold_pct   = 20;
  int unsigned r_hold_pct   = 20;
  int unsigned r_gap_pct    = 30;

  bit          dam          = 0;

  logic [7:0] mem [logic [ADDR_WIDTH-1:0]];

  protected logic [M_ID_W-1:0]    aw_id_q[$], b_id_q[$], ar_id_q[$];
  protected bit                    aw_err_q[$], b_err_q[$], ar_err_q[$];
  protected logic [ADDR_WIDTH-1:0] aw_ad_q[$], ar_ad_q[$];
  protected logic [2:0]            aw_sz_q[$], ar_sz_q[$];
  protected logic [7:0]            ar_ln_q[$], aw_ln_q[$];
  protected logic [1:0]            aw_bt_q[$], ar_bt_q[$];

  protected logic [ADDR_WIDTH-1:0] w_addr;
  protected logic [2:0]            w_size;
  protected logic [1:0]            w_bt;
  protected logic [7:0]            w_len;
  protected bit                    w_active = 0;

  protected function logic [ADDR_WIDTH-1:0] next_addr(
      logic [ADDR_WIDTH-1:0] a, logic [2:0] sz,
      logic [1:0] bt, logic [7:0] len);
    logic [ADDR_WIDTH-1:0] inc, wm;
    inc = (a + (32'd1 << sz)) & ~((32'd1 << sz) - 1);
    case (bt)
      2'b00:   next_addr = a;                                  // FIXED
      2'b10:   begin                                            // WRAP
                 wm = ((32'(len) + 1) << sz) - 1;
                 next_addr = (a & ~wm) | (inc & wm);
               end
      default: next_addr = inc;                                 // INCR
    endcase
  endfunction

  protected function logic [ADDR_WIDTH-1:0] word_of(logic [ADDR_WIDTH-1:0] a);
    return a & ~(ADDR_WIDTH'(STRB_WIDTH - 1));
  endfunction

  protected function int unsigned lane_of(logic [ADDR_WIDTH-1:0] a);
    return a[$clog2(STRB_WIDTH)-1:0];
  endfunction

  protected function logic [DATA_WIDTH-1:0] rd_word(logic [ADDR_WIDTH-1:0] a);
    logic [ADDR_WIDTH-1:0] w = word_of(a);
    rd_word = '0;
    for (int b = 0; b < STRB_WIDTH; b++)
      rd_word[8*b +: 8] = mem.exists(w + b) ? mem[w + b] : 8'hDE;
  endfunction

  int unsigned n_wr = 0, n_rd = 0;

  function new(virtual axi4_if #(.ID_W(M_ID_W)) vif);
    this.vif = vif;
  endfunction

  task run();
    idle();
    forever begin
      wait (vif.arst_n === 1'b1);
      @(posedge vif.aclk);
      fork
        begin
          fork
            aw_thread();
            w_thread();
            b_thread();
            ar_thread();
            r_thread();
          join
        end
        @(negedge vif.arst_n);
      join_any
      disable fork;
      idle();
      aw_id_q.delete(); b_id_q.delete(); ar_id_q.delete();
      aw_ad_q.delete(); ar_ad_q.delete();
      aw_sz_q.delete(); ar_sz_q.delete(); ar_ln_q.delete();
      aw_ln_q.delete(); aw_bt_q.delete(); ar_bt_q.delete();
      aw_err_q.delete(); b_err_q.delete(); ar_err_q.delete();
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
        aw_id_q.push_back(vif.awid);
        aw_ad_q.push_back(vif.awaddr);
        aw_sz_q.push_back(vif.awsize);
        aw_bt_q.push_back(vif.awburst);
        aw_ln_q.push_back(vif.awlen);
        aw_err_q.push_back(slverr_window && vif.awaddr[26]);
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
          w_addr   = aw_ad_q[0];
          w_size   = aw_sz_q[0];
          w_bt     = aw_bt_q[0];
          w_len    = aw_ln_q[0];
          w_active = 1;
        end
        for (int b = 0; b < STRB_WIDTH; b++)
          if (vif.wstrb[b])
            mem[word_of(w_addr) + b] = vif.wdata[8*b +: 8];
        w_addr = next_addr(w_addr, w_size, w_bt, w_len);
        if (vif.wlast) begin
          b_id_q.push_back(aw_id_q.pop_front());
          b_err_q.push_back(aw_err_q.pop_front());
          void'(aw_ad_q.pop_front());
          void'(aw_sz_q.pop_front());
          void'(aw_bt_q.pop_front());
          void'(aw_ln_q.pop_front());
          w_active = 0;
          n_wr++;
        end
      end
    end
  endtask

  protected function int pick_ooo(ref logic [M_ID_W-1:0] q[$]);
    pick_ooo = 0;
    if (q.size() > 1 && ($urandom_range(1, 100) <= ooo_pct))
      for (int j = 1; j < q.size(); j++)
        if (q[j] != q[0]) return j;
  endfunction

  task b_thread();
    bit done = 0;
    int sel  = 0;
    forever begin
      @(posedge vif.aclk);
      if (vif.bvalid && vif.bready) begin
        void'(b_id_q.delete(sel));
        void'(b_err_q.delete(sel));
        done = 1;
      end
      @(negedge vif.aclk);
      if (done) begin vif.bvalid = 1'b0; done = 0; end
      if (!vif.bvalid && b_id_q.size() > 0 && !dam
          && ($urandom_range(1, 100) > b_hold_pct)) begin
        sel        = pick_ooo(b_id_q);
        vif.bvalid = 1'b1;
        vif.bid    = b_id_q[sel];
        vif.bresp  = b_err_q[sel] ? 2'b10 : 2'b00;
      end
    end
  endtask

  task ar_thread();
    bit pend = 0;
    forever begin
      @(posedge vif.aclk);
      if (vif.arvalid && vif.arready) begin
        ar_id_q.push_back(vif.arid);
        ar_ad_q.push_back(vif.araddr);
        ar_ln_q.push_back(vif.arlen);
        ar_sz_q.push_back(vif.arsize);
        ar_bt_q.push_back(vif.arburst);
        ar_err_q.push_back(slverr_window && vif.araddr[26]);
        pend = 0;
      end
      else pend = vif.arvalid && !vif.arready;
      @(negedge vif.aclk);
      vif.arready = pend && ($urandom_range(1, 100) > ar_hold_pct);
    end
  endtask

  task r_thread();
    logic [ADDR_WIDTH-1:0] a;
    logic [2:0]            sz;
    logic [1:0]            bt;
    logic [7:0]            left, ln;
    bit                    r_err;
    bit                    active = 0;
    bit                    beat   = 0;
    forever begin
      @(posedge vif.aclk);
      beat = vif.rvalid && vif.rready;
      @(negedge vif.aclk);
      if (beat) begin
        if (left != 0) begin
          left = left - 1;
          a    = next_addr(a, sz, bt, ln);
          vif.rdata = rd_word(a);
          vif.rlast = (left == 0);
          if ($urandom_range(1, 100) <= r_gap_pct) vif.rvalid = 1'b0;
        end
        else begin
          vif.rvalid = 1'b0;
          vif.rlast  = 1'b0;
          active     = 0;
          n_rd++;
        end
      end
      else if (!vif.rvalid && active) begin
        vif.rvalid = 1'b1;
      end
      else if (!vif.rvalid && !active && ar_id_q.size() > 0 && !dam
               && ($urandom_range(1, 100) > r_hold_pct)) begin
        int k      = pick_ooo(ar_id_q);
        vif.rid    = ar_id_q[k];
        a          = ar_ad_q[k];
        left       = ar_ln_q[k];
        sz         = ar_sz_q[k];
        bt         = ar_bt_q[k];
        r_err      = ar_err_q[k];
        void'(ar_id_q.delete(k)); void'(ar_ad_q.delete(k));
        void'(ar_ln_q.delete(k)); void'(ar_sz_q.delete(k));
        void'(ar_bt_q.delete(k)); void'(ar_err_q.delete(k));
        ln         = left;
        vif.rdata  = rd_word(a);
        vif.rresp  = r_err ? 2'b10 : 2'b00;
        vif.rlast  = (left == 0);
        vif.rvalid = 1'b1;
        active     = 1;
      end
    end
  endtask

  function int unsigned outstanding();
    return aw_id_q.size() + b_id_q.size() + ar_id_q.size();
  endfunction

endclass
