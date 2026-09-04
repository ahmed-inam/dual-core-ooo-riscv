// The CLINT itself, now that it lives in the testbench.
class clint_driver extends uvm_driver #(irq_txn);
  `uvm_component_utils(clint_driver)

  virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)) vif;   // s0_if
  virtual irq_if                             irq;   // msip/mtip pins
  cpu_cfg cfg;

  uvm_analysis_port #(irq_txn) acc_ap;

  protected logic [63:0]        mtime;
  protected logic [63:0]        mtimecmp [NUM_HARTS];
  protected logic [NUM_HARTS-1:0] msip;

  protected logic [NUM_HARTS-1:0] force_msip, force_mtip;
  protected bit                   forcing;

  protected logic [axi4_pkg::M_ID_W-1:0]     aw_id_q[$], b_id_q[$], ar_id_q[$];
  protected logic [axi4_pkg::ADDR_WIDTH-1:0] aw_ad_q[$], ar_ad_q[$];

  int unsigned n_reg_wr, n_reg_rd, n_ticks;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    acc_ap = new("acc_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual axi4_if #(.ID_W(axi4_pkg::M_ID_W)))::get(
          this, "", "vif", vif))
      `uvm_fatal("CLINT_DRV", "no s0_if virtual interface")
    if (!uvm_config_db #(virtual irq_if)::get(this, "", "irq_vif", irq))
      `uvm_fatal("CLINT_DRV", "no irq_if virtual interface")
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CLINT_DRV", "no cpu_cfg")
  endfunction

  protected function void reset_regs();
    mtime      = '0;
    msip       = '0;
    forcing    = 0;
    force_msip = '0;
    force_mtip = '0;
    foreach (mtimecmp[h]) mtimecmp[h] = '1;
  endfunction

  protected function logic [NUM_HARTS-1:0] mtip_now();
    logic [NUM_HARTS-1:0] m = '0;
    for (int unsigned h = 0; h < NUM_HARTS; h++) m[h] = (mtime >= mtimecmp[h]);
    return m;
  endfunction

  protected function void reg_write(word_t addr, word_t data,
                                    logic [axi4_pkg::STRB_WIDTH-1:0] strb);
    logic [15:0] off = 16'(addr - cfg.clint_base);
    irq_txn t;

    if (off < 16'(NUM_HARTS*4)) begin
      int unsigned h = off[15:2];
      if (strb[0] && h < NUM_HARTS) msip[h] = data[0];   // bit 0 only
    end
    else if (off >= 16'h4000 && off < (16'h4000 + 16'(NUM_HARTS*8))) begin
      int unsigned h  = (off - 16'h4000) >> 3;   // /8, one 64-bit reg per hart
      bit          hi = off[2];
      if (h < NUM_HARTS) begin
        if (hi) mtimecmp[h][63:32] = merge_w(mtimecmp[h][63:32], data, strb);
        else    mtimecmp[h][31:0]  = merge_w(mtimecmp[h][31:0],  data, strb);
      end
    end
    else if (off == 16'hBFF8) mtime[31:0]  = merge_w(mtime[31:0],  data, strb);
    else if (off == 16'hBFFC) mtime[63:32] = merge_w(mtime[63:32], data, strb);

    n_reg_wr++;
    t = irq_txn::type_id::create("wr");
    t.kind = IRQ_REG_WRITE; t.addr = addr; t.data = data;
    t.mtime = mtime;
    foreach (t.mtimecmp[i]) t.mtimecmp[i] = mtimecmp[i];
    acc_ap.write(t);
  endfunction

  protected function word_t reg_read(word_t addr);
    logic [15:0] off = 16'(addr - cfg.clint_base);
    word_t d = '0;
    irq_txn t;

    if (off < 16'(NUM_HARTS*4)) begin
      int unsigned h = off[15:2];
      d = (h < NUM_HARTS) ? {31'b0, msip[h]} : '0;
    end
    else if (off >= 16'h4000 && off < (16'h4000 + 16'(NUM_HARTS*8))) begin
      int unsigned h  = (off - 16'h4000) >> 3;
      bit          hi = off[2];
      if (h < NUM_HARTS) d = hi ? mtimecmp[h][63:32] : mtimecmp[h][31:0];
    end
    else if (off == 16'hBFF8) d = mtime[31:0];
    else if (off == 16'hBFFC) d = mtime[63:32];

    n_reg_rd++;
    t = irq_txn::type_id::create("rd");
    t.kind = IRQ_REG_READ; t.addr = addr; t.data = d;
    t.mtime = mtime;
    acc_ap.write(t);
    return d;
  endfunction

  protected function word_t merge_w(word_t old_w, word_t new_w,
                                    logic [axi4_pkg::STRB_WIDTH-1:0] strb);
    word_t r;
    for (int b = 0; b < axi4_pkg::STRB_WIDTH; b++)
      r[8*b +: 8] = strb[b] ? new_w[8*b +: 8] : old_w[8*b +: 8];
    return r;
  endfunction

  task run_phase(uvm_phase phase);
    reset_regs();
    idle();
    forever begin
      wait (vif.arst_n === 1'b1);
      fork
        begin
          fork
            tick_thread(); pin_thread(); stimulus_thread();
            aw_thread(); w_thread(); b_thread(); ar_thread(); r_thread();
          join
        end
        @(negedge vif.arst_n);
      join_any
      disable fork;

      reset_regs();
      idle();
      aw_id_q.delete(); b_id_q.delete(); ar_id_q.delete();
      aw_ad_q.delete(); ar_ad_q.delete();
    end
  endtask

  task idle();
    vif.awready = 1'b0; vif.wready = 1'b0;
    vif.bvalid  = 1'b0; vif.bid = '0; vif.bresp = 2'b00;
    vif.arready = 1'b0;
    vif.rvalid  = 1'b0; vif.rid = '0; vif.rdata = '0;
    vif.rresp   = 2'b00; vif.rlast = 1'b0;
    irq.msip    = '0;   irq.mtip = '0;
  endtask

  task tick_thread();
    forever begin
      repeat (cfg.rtc_period) @(posedge vif.aclk);
      mtime = mtime + 64'd1;
      n_ticks++;
    end
  endtask

  task pin_thread();
    forever begin
      @(negedge vif.aclk);
      if (forcing) begin
        irq.msip = force_msip;
        irq.mtip = force_mtip;
      end
      else begin
        irq.msip = msip;
        irq.mtip = mtip_now();
      end
    end
  endtask

  task stimulus_thread();
    irq_txn item;
    forever begin
      @(posedge vif.aclk);
      seq_item_port.try_next_item(item);
      if (item == null) continue;

      case (item.kind)
        IRQ_REG_WRITE: reg_write(item.addr, item.data, '1);

        IRQ_DELIVERY: begin
          forcing    = 1;
          force_msip = item.msip;
          force_mtip = item.mtip;
        end
        default: ;
      endcase
      seq_item_port.item_done();
    end
  endtask

  task aw_thread();
    bit pend = 0;
    forever begin
      @(posedge vif.aclk);
      if (vif.awvalid && vif.awready) begin
        aw_id_q.push_back(vif.awid); aw_ad_q.push_back(vif.awaddr);
        pend = 0;
      end
      else pend = vif.awvalid && !vif.awready;
      @(negedge vif.aclk);
      vif.awready = pend;
    end
  endtask

  task w_thread();
    forever begin
      @(negedge vif.aclk);
      vif.wready = (aw_id_q.size() > 0);
      @(posedge vif.aclk);
      if (vif.wvalid && vif.wready && aw_ad_q.size() > 0) begin
        reg_write(aw_ad_q[0], vif.wdata, vif.wstrb);
        if (vif.wlast) begin
          b_id_q.push_back(aw_id_q.pop_front());
          void'(aw_ad_q.pop_front());
        end
      end
    end
  endtask

  task b_thread();
    forever begin
      @(negedge vif.aclk);
      if (b_id_q.size() > 0 && !vif.bvalid) begin
        vif.bid = b_id_q.pop_front(); vif.bresp = 2'b00; vif.bvalid = 1'b1;
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
        ar_id_q.push_back(vif.arid); ar_ad_q.push_back(vif.araddr);
        pend = 0;
      end
      else pend = vif.arvalid && !vif.arready;
      @(negedge vif.aclk);
      vif.arready = pend;
    end
  endtask

  task r_thread();
    forever begin
      @(negedge vif.aclk);
      if (ar_id_q.size() > 0 && !vif.rvalid) begin
        logic [axi4_pkg::M_ID_W-1:0] id = ar_id_q.pop_front();
        word_t                       ad = ar_ad_q.pop_front();
        @(negedge vif.aclk);
        vif.rid    = id;
        vif.rdata  = reg_read(ad);
        vif.rresp  = 2'b00;
        vif.rlast  = 1'b1;
        vif.rvalid = 1'b1;
        @(posedge vif.aclk);
        while (!vif.rready) @(posedge vif.aclk);
        @(negedge vif.aclk);
        vif.rvalid = 1'b0; vif.rlast = 1'b0;
      end
      else @(posedge vif.aclk);
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("CLINT_DRV", $sformatf(
      "%0d register writes, %0d reads, %0d mtime ticks (mtime=%0d)",
      n_reg_wr, n_reg_rd, n_ticks, mtime), UVM_LOW)

    begin
      bit any_armed = 0;
      foreach (mtimecmp[h]) if (mtimecmp[h] !== '1) any_armed = 1;
      if (!any_armed)
        `uvm_warning("CLINT_DRV",
          {"mtimecmp was never written: no timer interrupt was possible in this ",
           "run. A green result says nothing about interrupt delivery."})
    end
  endfunction

endclass
