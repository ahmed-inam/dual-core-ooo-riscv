// RVFI versus Spike for one core through the real caches, arbiter, adapter and memory.
`timescale 1ns/1ps
module tb_rvfi_sys_ooo;
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic  ireq, ignt, irvalid;
  word_t iaddr, irdata;
  logic [3:0][31:0] irdata_line;
  logic [3:0]       iwmask;
  logic  dreq, dgnt, dwe, drvalid;
  logic [3:0] dwstrb;
  word_t daddr, dwdata, drdata;
  logic  ic_flush, dc_flush, dc_flush_done;
  logic  ic_ev_access, ic_ev_miss, dc_ev_access, dc_ev_miss, dc_ev_wb;

  logic     [COMMIT_W-1:0]        rvfi_valid;
  logic     [COMMIT_W-1:0][63:0]  rvfi_order;
  word_t    [COMMIT_W-1:0]        rvfi_insn, rvfi_pc_rdata, rvfi_rd_wdata;
  logic     [COMMIT_W-1:0]        rvfi_trap;
  regaddr_t [COMMIT_W-1:0]        rvfi_rd_addr;

  word_t hartid_arg;
  initial begin
    if (!$value$plusargs("HARTID=%d", hartid_arg)) hartid_arg = 32'd0;
  end

  logic  tb_lr_valid, tb_sc_valid, tb_acc_valid;
  word_t tb_lrsc_addr;
  logic  [platform_cfg_pkg::NUM_HARTS-1:0] tb_lr_v, tb_sc_v, tb_acc_v, tb_acc_hit;
  word_t tb_acc_addr  [platform_cfg_pkg::NUM_HARTS];
  logic  [platform_cfg_pkg::NUM_HARTS-1:0] tb_sc_success, tb_prot_valid,
                                           tb_rsv_valid, tb_backoff;
  word_t tb_prot_addr [platform_cfg_pkg::NUM_HARTS];
  always_comb begin
    tb_lr_v = '0; tb_sc_v = '0; tb_acc_v = '0; tb_acc_hit = '0;
    for (int i = 0; i < platform_cfg_pkg::NUM_HARTS; i++) tb_acc_addr[i] = '0;
    tb_lr_v[0]     = tb_lr_valid;
    tb_sc_v[0]     = tb_sc_valid;
    tb_acc_v[0]    = tb_acc_valid;
    tb_acc_hit[0]  = 1'b1;            // single hart, no coherence: always local
    tb_acc_addr[0] = tb_lrsc_addr;
  end
  lrsc_unit u_lrsc (
    .clk, .rst_n,
    .lr_valid(tb_lr_v), .sc_valid(tb_sc_v), .acc_valid(tb_acc_v),
    .acc_addr(tb_acc_addr), .acc_hit(tb_acc_hit),
    .snoop_clear('0), .trap_clear('0),
    .sc_success(tb_sc_success), .prot_valid(tb_prot_valid),
    .prot_addr(tb_prot_addr), .rsv_valid(tb_rsv_valid),
    .backing_off(tb_backoff)
  );

  core #(.RESET_PC_P(32'h8000_0000)) u_core (
    .hart_id_i(hartid_arg),
    .snoop_valid_i(1'b0), .snoop_addr_i('0),
    .lrsc_lr_valid_o(tb_lr_valid), .lrsc_sc_valid_o(tb_sc_valid),
    .lrsc_addr_o(tb_lrsc_addr),
    .lrsc_acc_valid_o(tb_acc_valid), .lrsc_sc_success_i(tb_sc_success[0]),
    .clk, .rst_n,
    .ireq, .ignt, .iaddr, .irvalid, .irdata,
    .irdata_line, .iwmask,
    .dreq, .dgnt, .daddr, .dwe, .dwstrb, .dwdata, .drvalid, .drdata,
    .ev_ic_miss(ic_ev_miss), .ev_dc_miss(dc_ev_miss), .ev_dc_wb(dc_ev_wb),
    .ic_flush, .dc_flush, .dc_flush_done,
    .irq_timer(1'b0), .irq_soft(1'b0), .irq_ext(1'b0),
    .rvfi_valid, .rvfi_order, .rvfi_insn, .rvfi_trap,
    .rvfi_pc_rdata, .rvfi_rd_addr, .rvfi_rd_wdata,
    .rvfi_halt(), .rvfi_intr(), .rvfi_mode(), .rvfi_ixl(),
    .rvfi_rs1_addr(), .rvfi_rs2_addr(), .rvfi_rs1_rdata(), .rvfi_rs2_rdata(),
    .rvfi_pc_wdata(),
    .rvfi_mem_addr(), .rvfi_mem_rmask(), .rvfi_mem_wmask(),
    .rvfi_mem_rdata(), .rvfi_mem_wdata(),
    .trap_taken()   // named-but-empty: this TB has no LR/SC path
  );

  word_t iaddr_m, daddr_m;
  assign iaddr_m = {14'b0, iaddr[17:0]};
  assign daddr_m = {14'b0, daddr[17:0]};

  logic              il_req, il_gnt, il_rvalid;
  word_t             il_addr;
  logic [LINE_W-1:0] il_rdata;

  icache u_ic (
    .clk, .rst_n,
    .req(ireq), .gnt(ignt), .addr(iaddr_m), .rvalid(irvalid), .rdata(irdata),
    .rdata_line(irdata_line), .rdata_woff(), .rdata_wmask(iwmask),
    .flush(ic_flush),
    .line_req(il_req), .line_gnt(il_gnt), .line_addr(il_addr),
    .line_rvalid(il_rvalid), .line_rdata(il_rdata),
    .ev_access(ic_ev_access), .ev_miss(ic_ev_miss)
  );

  logic              dl_req, dl_gnt, dl_we, dl_rvalid;
  word_t             dl_addr;
  logic [LINE_W-1:0] dl_wdata, dl_rdata;
  logic       dm_req, dm_gnt, dm_we, dm_rvalid;
  logic [3:0] dm_wstrb;
  word_t      dm_addr, dm_wdata, dm_rdata;

  dcache u_dc (
    .clk, .rst_n,
    .snp_valid(1'b0), .snp_addr('0), .snp_type(coherence_pkg::SNP_TO_S),
    .snp_ack(), .snp_rsp(),
    .coh_req_valid(), .coh_req_type(), .coh_req_addr(),
    .coh_gnt(1'b1), .coh_done(1'b1), .coh_shared(1'b0),
    .coh_installed(),
    .req(dreq), .gnt(dgnt), .addr(daddr_m), .we(dwe), .wstrb(dwstrb),
    .wdata(dwdata), .rvalid(drvalid), .rdata(drdata),
    .kill(1'b0), .flush(dc_flush), .flush_done(dc_flush_done),
    .line_req(dl_req), .line_gnt(dl_gnt), .line_addr(dl_addr),
    .line_we(dl_we), .line_wdata(dl_wdata),
    .line_rvalid(dl_rvalid), .line_rdata(dl_rdata),
    .mmio_req(dm_req), .mmio_gnt(dm_gnt), .mmio_addr(dm_addr),
    .mmio_we(dm_we), .mmio_wstrb(dm_wstrb), .mmio_wdata(dm_wdata),
    .mmio_rvalid(dm_rvalid), .mmio_rdata(dm_rdata),
    .ev_access(dc_ev_access), .ev_miss(dc_ev_miss), .ev_wb(dc_ev_wb)
  );

  logic              o_req, o_gnt, o_we, o_word, o_rvalid;
  logic [3:0]        o_wstrb;
  word_t             o_addr;
  logic [LINE_W-1:0] o_wdata, o_rdata;
  logic              ev_starve_i;

  mem_arbiter u_arb (
    .clk, .rst_n,
    .d_req(dl_req), .d_gnt(dl_gnt), .d_addr(dl_addr), .d_we(dl_we),
    .d_wdata(dl_wdata), .d_rvalid(dl_rvalid), .d_rdata(dl_rdata),
    .m_req(dm_req), .m_gnt(dm_gnt), .m_addr(dm_addr), .m_we(dm_we),
    .m_wstrb(dm_wstrb), .m_wdata(dm_wdata),
    .m_rvalid(dm_rvalid), .m_rdata(dm_rdata),
    .i_req(il_req), .i_gnt(il_gnt), .i_addr(il_addr),
    .i_rvalid(il_rvalid), .i_rdata(il_rdata),
    .out_req(o_req), .out_gnt(o_gnt), .out_addr(o_addr), .out_we(o_we),
    .out_word(o_word), .out_wstrb(o_wstrb), .out_wdata(o_wdata),
    .out_rvalid(o_rvalid), .out_rdata(o_rdata),
    .ev_starve_i(ev_starve_i)
  );

  axi_req_t  axi_req;
  axi_resp_t axi_resp;

  axi_adapter u_adp (
    .clk, .rst_n,
    .req(o_req), .gnt(o_gnt), .addr(o_addr), .we(o_we), .word_mode(o_word),
    .wstrb(o_wstrb), .wdata(o_wdata), .rvalid(o_rvalid), .rdata(o_rdata),
    .axi_req, .axi_resp
  );

  word_t dbg_addr, dbg_data;
  logic  err_overlap, err_range;
  int unsigned cfg_delay, cfg_beat_delay;

  sim_mem #(.WORDS(65536)) u_mem (
    .clk, .rst_n, .cfg_delay, .cfg_beat_delay,
    .axi_req, .axi_resp, .dbg_addr, .dbg_data, .err_overlap, .err_range
  );

  longint unsigned fault_order; logic fault_armed;
  always_ff @(posedge clk) begin
    for (int i = 0; i < COMMIT_W; i++)
      if (rvfi_valid[i]) begin
        automatic logic [31:0] wd = rvfi_rd_wdata[i];
        if (fault_armed && rvfi_order[i] == fault_order) wd = wd ^ 32'h1;
        $display("V %0d %h %h %0d %h",
                 rvfi_order[i], rvfi_pc_rdata[i], rvfi_insn[i], rvfi_rd_addr[i], wd);
      end
    for (int i = 0; i < COMMIT_W; i++)
      if (rvfi_trap[i]) $display("X trap pc=%h", rvfi_pc_rdata[i]);
  end

  longint unsigned cyc, ins;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin cyc <= 0; ins <= 0; end
    else begin
      cyc <= cyc + 1;
      ins <= ins + $countones(rvfi_valid);   // may be 2 in one cycle at width 2
    end
  end

  word_t tohost_addr;
  always @(posedge clk) begin
    if (rst_n && dreq && dwe && daddr == tohost_addr && dwdata != 0) begin
      if (dwdata == 32'd1) $display("RVFI DONE PASS");
      else                 $display("RVFI DONE FAIL: testnum %0d", dwdata >> 1);
      $display("RVFISYS DELAY=%0d BEAT_DELAY=%0d cycles=%0d instret=%0d",
               cfg_delay, cfg_beat_delay, cyc, ins);
      $display("RVFIPERF mispred=%0d imiss=%0d dmiss=%0d",
               u_core.u_perf.hpm4_q, u_core.u_perf.hpm7_q, u_core.u_perf.hpm8_q);
      $finish;
    end
  end

  int unsigned dly, bdly;
  string hexfile; longint unsigned fo;
  initial begin
    dbg_addr = '0;
    if (!$value$plusargs("DELAY=%d", dly))          dly  = 10;
    if (!$value$plusargs("BEAT_DELAY=%d", bdly))    bdly = 0;
    if (!$value$plusargs("HEX=%s", hexfile))        hexfile = "asm/ctest_rvfi.hex";
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) tohost_addr = 32'h8000_1000;
    fault_armed = $value$plusargs("FAULT=%d", fo); fault_order = fo;
    cfg_delay = dly; cfg_beat_delay = bdly;
    for (int i = 0; i < 65536; i++) u_mem.mem[i] = 32'h0;
    $readmemh(hexfile, u_mem.mem);
    rst_n = 0; #12 rst_n = 1;
    #400_000_000 $display("RVFISYS TIMEOUT"); $finish;
  end
endmodule
