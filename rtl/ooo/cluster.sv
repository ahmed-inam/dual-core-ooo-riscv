// Two harts with private L1s, the coherence manager, and the crossbar.
module cluster
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;
  import coherence_pkg::*;      // coherence vocabulary
  import platform_cfg_pkg::*;
#(
  parameter word_t RESET_PC_P = 32'h8000_0000
) (
  input  logic clk,
  input  logic rst_n,

  axi4_if.mst s0_if,
  axi4_if.mst s1_if,

  input  logic [NUM_HARTS-1:0] msip_i,
  input  logic [NUM_HARTS-1:0] mtip_i,

  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_valid,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][63:0] rvfi_order,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_insn,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_pc_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rd_wdata,
  output regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rd_addr,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_trap,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_halt,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_intr,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][1:0]  rvfi_mode,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][1:0]  rvfi_ixl,
  output regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs1_addr,
  output regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs2_addr,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs1_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs2_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_pc_wdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_addr,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][3:0]  rvfi_mem_rmask,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][3:0]  rvfi_mem_wmask,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_wdata,

  output logic  [NUM_HARTS-1:0] dreq_o,
  output logic  [NUM_HARTS-1:0] dwe_o,
  output word_t [NUM_HARTS-1:0] daddr_o,
  output word_t [NUM_HARTS-1:0] dwdata_o,

  output logic [NUM_HARTS-1:0] ev_starve_i
);

  logic              a_req   [NUM_HARTS];
  logic              a_gnt   [NUM_HARTS];
  word_t             a_addr  [NUM_HARTS];
  logic              a_we    [NUM_HARTS];
  logic              a_word  [NUM_HARTS];
  logic [3:0]        a_wstrb [NUM_HARTS];
  logic [LINE_W-1:0] a_wdata [NUM_HARTS];
  logic              a_rvalid[NUM_HARTS];
  logic [LINE_W-1:0] a_rdata [NUM_HARTS];

  logic  [NUM_HARTS-1:0] m0_req, m0_gnt, m0_we, m0_word, m0_rvalid;
  word_t                 m0_addr  [NUM_HARTS];
  logic  [3:0]           m0_wstrb [NUM_HARTS];
  logic [LINE_W-1:0]     m0_wdata [NUM_HARTS];
  logic [LINE_W-1:0]     m0_rdata;               // shared: owner samples it
  logic                  m0_rerr;
  logic  [NUM_HARTS-1:0] ev_starve_m;
  logic  [NUM_HARTS-1:0] ev_starve_d;

  logic  [NUM_HARTS-1:0] i_req_a, i_gnt_a, i_rvalid_a;
  word_t                 i_addr_a [NUM_HARTS];
  logic [LINE_W-1:0]     i_rdata_s;
  logic                  i_rerr_s;

  logic     [NUM_HARTS-1:0] coh_req_valid;
  coh_req_e                 coh_req_type [NUM_HARTS];
  word_t                    coh_req_addr [NUM_HARTS];
  logic     [NUM_HARTS-1:0] coh_req_gnt;
  logic     [NUM_HARTS-1:0] coh_snp_valid;
  word_t                    coh_snp_addr;
  coh_snoop_e               coh_snp_type;
  logic     [NUM_HARTS-1:0] coh_snp_ack;
  coh_rsp_e                 coh_snp_rsp  [NUM_HARTS];
  logic     [NUM_HARTS-1:0] coh_cmp_valid;
  logic                     coh_cmp_shared, coh_cmp_dirty;
  logic     [NUM_HARTS-1:0] coh_installed;
  logic                     coh_prot_deferred, coh_ord_violation;
  logic [NUM_HARTS-1:0]     core_trap_taken;

  logic  [NUM_HARTS-1:0] lr_v, sc_v, acc_v, acc_hit, snp_clr, trp_clr;
  word_t                 lrsc_acc_addr [NUM_HARTS];
  logic  [NUM_HARTS-1:0] sc_ok, prot_valid, rsv_valid, backing_off;
  logic  [NUM_HARTS-1:0] coh_req_atomic;
  word_t                 prot_addr [NUM_HARTS];

  coherence_mgr u_coh (
    .clk, .rst_n,
    .req_valid(coh_req_valid), .req_addr(coh_req_addr), .req_type(coh_req_type),
    .req_atomic(coh_req_atomic),
    .req_gnt(coh_req_gnt),
    .snp_valid(coh_snp_valid), .snp_addr(coh_snp_addr), .snp_type(coh_snp_type),
    .snp_ack(coh_snp_ack), .snp_rsp(coh_snp_rsp),
    .req_installed(coh_installed),
    .cmp_valid(coh_cmp_valid), .cmp_shared(coh_cmp_shared), .cmp_dirty(coh_cmp_dirty),
    .prot_valid(prot_valid), .prot_addr(prot_addr),
    .prot_deferred(coh_prot_deferred), .ord_violation(coh_ord_violation)
  );

  lrsc_unit u_lrsc (
    .clk, .rst_n,
    .lr_valid(lr_v), .sc_valid(sc_v), .acc_valid(acc_v),
    .acc_addr(lrsc_acc_addr), .acc_hit(acc_hit),
    .snoop_clear(snp_clr), .trap_clear(trp_clr),
    .sc_success(sc_ok), .prot_valid(prot_valid), .prot_addr(prot_addr),
    .rsv_valid(rsv_valid), .backing_off(backing_off)
  );

  for (genvar h = 0; h < NUM_HARTS; h++) begin : g_hart
    logic              ireq, ignt, irvalid;
    word_t             iaddr, irdata;
    logic [3:0][31:0]  irdata_line;
    logic [3:0]        iwmask;
    logic              dreq, dgnt, dwe, drvalid;
    word_t             daddr, dwdata, drdata;
    logic [3:0]        dwstrb;
    logic              dis_lr;   // LR write-intent, core -> dcache
    logic              ic_flush, dc_flush, dc_flush_done;
    logic              ic_ev_miss, dc_ev_miss, dc_ev_wb;

    // The manager holds a snoop until the cache acks it; the load queue wants
    // the first cycle only, so an executed load is not re-flagged every cycle.
    logic snp_seen_q;
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) snp_seen_q <= 1'b0;
      else        snp_seen_q <= coh_snp_valid[h];
    end

    core #(.RESET_PC_P(RESET_PC_P)) u_core (
      .hart_id_i(word_t'(h)),
      .snoop_valid_i(coh_snp_valid[h] && !snp_seen_q),
      .snoop_addr_i(coh_snp_addr),
      .lrsc_lr_valid_o(lr_v[h]), .lrsc_sc_valid_o(sc_v[h]),
      .lrsc_addr_o(lrsc_acc_addr[h]), .lrsc_acc_valid_o(acc_v[h]),
      .lrsc_sc_success_i(sc_ok[h]),
      .clk, .rst_n,
      .ireq, .ignt, .iaddr(iaddr), .irvalid, .irdata, .irerr,
      .irdata_line, .iwmask,
      .dreq, .dgnt, .daddr(daddr), .dwe, .dis_lr, .dwstrb, .dwdata, .drvalid, .drdata, .drerr,
      .ev_ic_miss(ic_ev_miss), .ev_dc_miss(dc_ev_miss), .ev_dc_wb(dc_ev_wb),
      .ic_flush, .dc_flush, .dc_flush_done,
      .rvfi_valid(rvfi_valid[h]), .rvfi_order(rvfi_order[h]),
      .rvfi_insn(rvfi_insn[h]),   .rvfi_trap(rvfi_trap[h]),
      .rvfi_pc_rdata(rvfi_pc_rdata[h]), .rvfi_rd_addr(rvfi_rd_addr[h]),
      .rvfi_rd_wdata(rvfi_rd_wdata[h]),
      .rvfi_halt(rvfi_halt[h]), .rvfi_intr(rvfi_intr[h]),
      .rvfi_mode(rvfi_mode[h]), .rvfi_ixl(rvfi_ixl[h]),
      .rvfi_rs1_addr(rvfi_rs1_addr[h]), .rvfi_rs2_addr(rvfi_rs2_addr[h]),
      .rvfi_rs1_rdata(rvfi_rs1_rdata[h]), .rvfi_rs2_rdata(rvfi_rs2_rdata[h]),
      .rvfi_pc_wdata(rvfi_pc_wdata[h]),
      .rvfi_mem_addr(rvfi_mem_addr[h]), .rvfi_mem_rmask(rvfi_mem_rmask[h]),
      .rvfi_mem_wmask(rvfi_mem_wmask[h]), .rvfi_mem_rdata(rvfi_mem_rdata[h]),
      .rvfi_mem_wdata(rvfi_mem_wdata[h]),
      .trap_taken(core_trap_taken[h]),

      .irq_timer(mtip_i[h]),
      .irq_soft (msip_i[h]),
      .irq_ext  (1'b0)
    );

    assign dreq_o[h]   = dreq;
    assign dwe_o[h]    = dwe;
    assign daddr_o[h]  = daddr;
    assign dwdata_o[h] = dwdata;

    logic              irerr, drerr;
    logic              il_req, il_gnt, il_rvalid, il_rerr;
    word_t             il_addr;
    logic [LINE_W-1:0] il_rdata;

    icache u_ic (
      .clk, .rst_n,
      .line_ram_only_i(1'b1),   // the crossbar sends every non-RAM prefix to word-only or nowhere
      .req(ireq), .gnt(ignt), .addr(iaddr), .rvalid(irvalid), .rdata(irdata),
      .rerr(irerr),
      .rdata_line(irdata_line), .rdata_woff(), .rdata_wmask(iwmask),
      .flush(ic_flush),
      .line_req(il_req), .line_gnt(il_gnt), .line_addr(il_addr),
      .line_rvalid(il_rvalid), .line_rdata(il_rdata), .line_rerr(il_rerr),
      .ev_access(),
      .ev_miss(ic_ev_miss)
    );

    logic              dl_req, dl_gnt, dl_we, dl_rvalid, dl_rerr;
    word_t             dl_addr;
    logic [LINE_W-1:0] dl_wdata, dl_rdata;
    logic              dm_req, dm_gnt, dm_we, dm_rvalid, dm_rerr;
    word_t             dm_addr, dm_wdata, dm_rdata;
    logic [3:0]        dm_wstrb;
    logic              dc_rsv_clear;

    dcache u_dc (
      .clk, .rst_n,
      .line_ram_only_i(1'b1),
      .snp_valid(coh_snp_valid[h]), .snp_addr(coh_snp_addr), .snp_type(coh_snp_type),
      .snp_ack(coh_snp_ack[h]), .snp_rsp(coh_snp_rsp[h]),
      .rsv_clear_o(dc_rsv_clear),
      .coh_req_valid(coh_req_valid[h]), .coh_req_type(coh_req_type[h]),
      .coh_req_addr(coh_req_addr[h]), .coh_req_atomic(coh_req_atomic[h]),
      .coh_gnt(coh_req_gnt[h]), .coh_done(coh_cmp_valid[h]),
      .coh_shared(coh_cmp_shared), .coh_installed(coh_installed[h]),
      .req(dreq), .gnt(dgnt), .addr(daddr), .we(dwe), .is_lr(dis_lr), .wstrb(dwstrb),
      .wdata(dwdata), .rvalid(drvalid), .rdata(drdata), .rerr(drerr),
      .kill(1'b0), .flush(dc_flush), .flush_done(dc_flush_done),
      .line_req(dl_req), .line_gnt(dl_gnt), .line_addr(dl_addr),
      .line_we(dl_we), .line_wdata(dl_wdata),
      .line_rvalid(dl_rvalid), .line_rdata(dl_rdata), .line_rerr(dl_rerr),
      .mmio_req(dm_req), .mmio_gnt(dm_gnt), .mmio_addr(dm_addr),
      .mmio_we(dm_we), .mmio_wstrb(dm_wstrb), .mmio_wdata(dm_wdata),
      .mmio_rvalid(dm_rvalid), .mmio_rdata(dm_rdata), .mmio_rerr(dm_rerr),
      .ev_access(), .ev_miss(dc_ev_miss), .ev_wb(dc_ev_wb)
    );

    merge_d_mmio u_dm (
      .clk, .rst_n,
      .d_req(dl_req), .d_gnt(dl_gnt), .d_addr(dl_addr), .d_we(dl_we),
      .d_wdata(dl_wdata), .d_rvalid(dl_rvalid), .d_rdata(dl_rdata), .d_rerr(dl_rerr),
      .m_req(dm_req), .m_gnt(dm_gnt), .m_addr(dm_addr), .m_we(dm_we),
      .m_wstrb(dm_wstrb), .m_wdata(dm_wdata),
      .m_rvalid(dm_rvalid), .m_rdata(dm_rdata), .m_rerr(dm_rerr),
      .out_req(m0_req[h]), .out_gnt(m0_gnt[h]), .out_addr(m0_addr[h]),
      .out_we(m0_we[h]), .out_word(m0_word[h]), .out_wstrb(m0_wstrb[h]),
      .out_wdata(m0_wdata[h]),
      .out_rvalid(m0_rvalid[h]), .out_rdata(m0_rdata), .out_rerr(m0_rerr),
      .ev_starve_m(ev_starve_m[h])
    );

    assign i_req_a[h]  = il_req;
    assign il_gnt      = i_gnt_a[h];
    assign i_addr_a[h] = il_addr;
    assign il_rvalid   = i_rvalid_a[h];
    assign il_rdata    = i_rdata_s;
    assign il_rerr     = i_rerr_s;

    assign acc_hit[h] = !dc_ev_miss;

    assign snp_clr[h] = dc_rsv_clear;

    // Losing a reservation spuriously is legal; keeping one across a trap is not.
    assign trp_clr[h] = core_trap_taken[h];

  end : g_hart


  logic              md_req, md_gnt, md_we, md_word, md_rvalid, md_rerr;
  word_t             md_addr;
  logic [3:0]        md_wstrb;
  logic [LINE_W-1:0] md_wdata, md_rdata;

  merge_dcoh u_md (
    .clk, .rst_n,
    .h_req(m0_req), .h_gnt(m0_gnt), .h_addr(m0_addr), .h_we(m0_we),
    .h_word(m0_word), .h_wstrb(m0_wstrb), .h_wdata(m0_wdata),
    .h_rvalid(m0_rvalid), .h_rdata(m0_rdata), .h_rerr(m0_rerr),
    .out_req(md_req), .out_gnt(md_gnt), .out_addr(md_addr), .out_we(md_we),
    .out_word(md_word), .out_wstrb(md_wstrb), .out_wdata(md_wdata),
    .out_rvalid(md_rvalid), .out_rdata(md_rdata), .out_rerr(md_rerr),
    .ev_starve_d(ev_starve_d)
  );

  logic              mi_req, mi_gnt, mi_we, mi_word, mi_rvalid, mi_rerr;
  word_t             mi_addr;
  logic [3:0]        mi_wstrb;
  logic [LINE_W-1:0] mi_wdata, mi_rdata;

  merge_ifetch u_mi (
    .clk, .rst_n,
    .i_req(i_req_a), .i_gnt(i_gnt_a), .i_addr(i_addr_a),
    .i_rvalid(i_rvalid_a), .i_rdata(i_rdata_s), .i_rerr(i_rerr_s),
    .out_req(mi_req), .out_gnt(mi_gnt), .out_addr(mi_addr), .out_we(mi_we),
    .out_word(mi_word), .out_wstrb(mi_wstrb), .out_wdata(mi_wdata),
    .out_rvalid(mi_rvalid), .out_rdata(mi_rdata), .out_rerr(mi_rerr),
    .ev_starve_i(ev_starve_i)
  );

  axi_req_t  m0_areq, m1_areq;
  axi_resp_t m0_aresp, m1_aresp;

  axi_adapter u_adp0 (
    .clk, .rst_n,
    .req(md_req), .gnt(md_gnt), .addr(md_addr), .we(md_we),
    .word_mode(md_word), .wstrb(md_wstrb), .wdata(md_wdata),
    .rvalid(md_rvalid), .rdata(md_rdata), .rerr(md_rerr),
    .axi_req(m0_areq), .axi_resp(m0_aresp)
  );

  axi_adapter u_adp1 (
    .clk, .rst_n,
    .req(mi_req), .gnt(mi_gnt), .addr(mi_addr), .we(mi_we),
    .word_mode(mi_word), .wstrb(mi_wstrb), .wdata(mi_wdata),
    .rvalid(mi_rvalid), .rdata(mi_rdata), .rerr(mi_rerr),
    .axi_req(m1_areq), .axi_resp(m1_aresp)
  );

  axi4_if #(.ID_W(axi4_pkg::ID_WIDTH)) m0_if (.aclk(clk), .arst_n(rst_n));
  axi4_if #(.ID_W(axi4_pkg::ID_WIDTH)) m1_if (.aclk(clk), .arst_n(rst_n));

  coreaxi_axi4_bridge u_br0 (.core_req(m0_areq), .core_resp(m0_aresp), .xbar(m0_if.mst));
  coreaxi_axi4_bridge u_br1 (.core_req(m1_areq), .core_resp(m1_aresp), .xbar(m1_if.mst));

  axi4_xbar_top u_xbar (
    .aclk(clk), .arst_n(rst_n),
    .m0(m0_if.slv), .m1(m1_if.slv),
    .s0(s0_if), .s1(s1_if)
  );


`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (md_rvalid && !(|m0_rvalid))
      $fatal(1, "cluster: master0 response reached no hart -- transaction lost");
    if (mi_rvalid && !(|i_rvalid_a))
      $fatal(1, "cluster: master1 response reached no hart -- I-fetch lost");
    if ($countones(m0_gnt) > 1)
      $fatal(1, "cluster: two harts granted on master0 in one cycle");
    if ($countones(i_gnt_a) > 1)
      $fatal(1, "cluster: two harts granted on master1 in one cycle");
  end
`endif

endmodule
