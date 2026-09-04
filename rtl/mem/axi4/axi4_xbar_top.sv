// 2x2 AXI4 crossbar assembly.

module axi4_xbar_top
  import axi4_pkg::*;
(
  input logic aclk,
  input logic arst_n,

  axi4_if.slv m0,      // master-facing, ID_W = ID_WIDTH  (crossbar is a slave here)
  axi4_if.slv m1,
  axi4_if.mst s0,      // slave-facing,  ID_W = M_ID_W    (crossbar is a master here)
  axi4_if.mst s1
);

  if (!CHK_TWO_MASTERS) begin : g_chk_2x2
    $error("axi4_pkg: this fabric is fixed 2x2 -- see resp_return_mux and the port arrays");
  end
  if (!CHK_ID_WIDTH) begin : g_chk_id
    $error("axi4_pkg: M_ID_W too narrow to carry the master tag");
  end
  if (!CHK_THREADS) begin : g_chk_thr
    $error("axi4_pkg: NUM_THREADS must be < MAX_OUTSTANDING or tracker-full is unreachable");
  end
  if (!CHK_TENURE) begin : g_chk_ten
    $error("axi4_pkg: TENURE_QUANTUM must be <= MAX_OUTSTANDING");
  end
  if (!CHK_CNT_W || !CHK_TENURE_W) begin : g_chk_cnt
    $error("axi4_pkg: counter width too small");
  end
  if (!CHK_DECODE) begin : g_chk_dec
    $error("axi4_pkg: S0 and S1 decode to the same prefix");
  end

  localparam int AW_PAY_W = $bits(axpay_t);
  localparam int W_PAY_W  = $bits(wpay_t);
  localparam int B_PAY_W  = $bits(bpay_t);
  localparam int R_PAY_W  = $bits(rpay_t);
  localparam int R_MUX_W  = $bits(rmux_t);

  logic srst_n;

  logic [1:0]                  mi_awvalid, mi_awready, mi_wvalid, mi_wready;
  logic [1:0]                  mi_arvalid, mi_arready;
  axpay_t [1:0]                mi_awpay, mi_arpay;
  wpay_t  [1:0]                mi_wpay;
  logic [1:0]                  mo_bvalid, mo_bready, mo_rvalid, mo_rready;
  logic [1:0][ID_WIDTH-1:0]    mo_bid, mo_rid;
  logic [1:0][1:0]             mo_bresp;
  rmux_t  [1:0]                mo_rpay;
  logic [1:0]                  mo_rlast;
  logic [1:0]                  unused_b_last;

  logic [1:0]                  aw_v, aw_r, w_v, w_r, ar_v, ar_r;
  axpay_t [1:0]                aw_p, ar_p;
  wpay_t  [1:0]                w_p;
  dest_e [1:0]                 aw_dest, ar_dest;

  logic [1:0]                  wr_thr_ok, wr_thr_alloc, rd_thr_ok, rd_thr_alloc;
  logic [1:0]                  mw_grant;
  dest_e [1:0]                 mw_dest;
  logic [1:0]                  dw_busy, dw_aw_acc, dw_w_beat, dw_w_last;
  logic [1:0]                  dr_busy, dr_ar_acc;
  logic [1:0]                  b_cpl_v, r_cpl_v;
  logic [1:0][ID_WIDTH-1:0]    b_cpl_id, r_cpl_id;

  logic [1:0]                  dw_bvalid, dw_bready;
  logic [1:0][ID_WIDTH-1:0]    dw_bid;
  logic [1:0][1:0]             dw_bresp;
  logic [1:0]                  dr_rvalid, dr_rready, dr_rlast;
  logic [1:0][ID_WIDTH-1:0]    dr_rid;
  rmux_t  [1:0]                dr_rpay;

  logic [1:0][1:0]             p_awvalid, p_awready, p_wvalid, p_wready;
  logic [1:0][1:0]             p_arvalid, p_arready;
  logic [1:0][1:0]             p_arb_req, p_arb_gnt, p_arb_ack;
  logic [1:0][1:0]             p_rarb_req, p_rarb_ack;   // reads never consume a grant
  logic [1:0][M_ID_W-1:0]      p_awid, p_arid;

  logic [1:0][1:0]             q_awvalid, q_awready, q_wvalid, q_wready;
  logic [1:0][1:0]             q_arvalid, q_arready;
  logic [1:0][1:0]             q_arb_req, q_arb_gnt, q_arb_ack;
  logic [1:0][1:0]             q_rarb_req, q_rarb_gnt, q_rarb_ack;

  logic [1:0]                  sb_valid, sb_ready_or;
  logic [1:0][M_ID_W-1:0]      sb_id;
  logic [1:0][1:0]             sb_resp;
  logic [1:0][1:0]             sb_ready;        // [N][M]
  logic [1:0]                  sr_valid, sr_last_w, sr_ready_or;
  logic [1:0][M_ID_W-1:0]      sr_id;
  rmux_t  [1:0]                sr_pay;
  logic [1:0][1:0]             sr_ready;

  logic [1:0]                  s_awvalid, s_awready, s_wvalid, s_wready;
  logic [1:0]                  s_arvalid, s_arready;
  logic [1:0][M_ID_W-1:0]      s_awid, s_arid;
  logic [1:0][ADDR_WIDTH-1:0]  s_awaddr, s_araddr;
  logic [1:0][7:0]             s_awlen, s_arlen;
  logic [1:0][2:0]             s_awsize, s_arsize;
  logic [1:0][1:0]             s_awburst, s_arburst;
  logic [1:0][DATA_WIDTH-1:0]  s_wdata;
  logic [1:0][STRB_WIDTH-1:0]  s_wstrb;
  logic [1:0]                  s_wlast;
  logic [1:0]                  s_bvalid, s_bready, s_rvalid, s_rready, s_rlast;
  logic [1:0][M_ID_W-1:0]      s_bid, s_rid;
  logic [1:0][1:0]             s_bresp, s_rresp;
  logic [1:0][DATA_WIDTH-1:0]  s_rdata;

  logic [1:0][1:0][ADDR_WIDTH-1:0] x_awaddr, x_araddr;
  logic [1:0][1:0][7:0]            x_awlen,  x_arlen;
  logic [1:0][1:0][2:0]            x_awsize, x_arsize;
  logic [1:0][1:0][1:0]            x_awburst, x_arburst;
  logic [1:0][1:0][M_ID_W-1:0]     x_awid,   x_arid;
  logic [1:0][1:0][DATA_WIDTH-1:0] x_wdata;
  logic [1:0][1:0][STRB_WIDTH-1:0] x_wstrb;
  logic [1:0][1:0]                 x_wlast;

  rst_sync u_rst (.aclk(aclk), .arst_n(arst_n), .srst_n(srst_n));

  assign mi_awvalid = {m1.awvalid, m0.awvalid};
  assign mi_awpay[0] = '{id:m0.awid, addr:m0.awaddr, len:m0.awlen, size:m0.awsize, burst:m0.awburst};
  assign mi_awpay[1] = '{id:m1.awid, addr:m1.awaddr, len:m1.awlen, size:m1.awsize, burst:m1.awburst};
  assign m0.awready = mi_awready[0];
  assign m1.awready = mi_awready[1];

  assign mi_wvalid  = {m1.wvalid, m0.wvalid};
  assign mi_wpay[0] = '{data:m0.wdata, strb:m0.wstrb, last:m0.wlast};
  assign mi_wpay[1] = '{data:m1.wdata, strb:m1.wstrb, last:m1.wlast};
  assign m0.wready  = mi_wready[0];
  assign m1.wready  = mi_wready[1];

  assign mi_arvalid = {m1.arvalid, m0.arvalid};
  assign mi_arpay[0] = '{id:m0.arid, addr:m0.araddr, len:m0.arlen, size:m0.arsize, burst:m0.arburst};
  assign mi_arpay[1] = '{id:m1.arid, addr:m1.araddr, len:m1.arlen, size:m1.arsize, burst:m1.arburst};
  assign m0.arready = mi_arready[0];
  assign m1.arready = mi_arready[1];

  assign m0.bvalid = mo_bvalid[0];  assign m0.bid = mo_bid[0];  assign m0.bresp = mo_bresp[0];
  assign m1.bvalid = mo_bvalid[1];  assign m1.bid = mo_bid[1];  assign m1.bresp = mo_bresp[1];
  assign mo_bready = {m1.bready, m0.bready};

  assign m0.rvalid = mo_rvalid[0];  assign m0.rid = mo_rid[0];
  assign m0.rdata  = mo_rpay[0].data;
  assign m0.rresp  = mo_rpay[0].resp;
  assign m0.rlast  = mo_rlast[0];
  assign m1.rvalid = mo_rvalid[1];  assign m1.rid = mo_rid[1];
  assign m1.rdata  = mo_rpay[1].data;
  assign m1.rresp  = mo_rpay[1].resp;
  assign m1.rlast  = mo_rlast[1];
  assign mo_rready = {m1.rready, m0.rready};

  assign s0.awvalid = s_awvalid[0];  assign s1.awvalid = s_awvalid[1];
  assign s0.awid    = s_awid[0];     assign s1.awid    = s_awid[1];
  assign s0.awaddr  = s_awaddr[0];   assign s1.awaddr  = s_awaddr[1];
  assign s0.awlen   = s_awlen[0];    assign s1.awlen   = s_awlen[1];
  assign s0.awsize  = s_awsize[0];   assign s1.awsize  = s_awsize[1];
  assign s0.awburst = s_awburst[0];  assign s1.awburst = s_awburst[1];
  assign s_awready  = {s1.awready, s0.awready};

  assign s0.wvalid = s_wvalid[0];  assign s1.wvalid = s_wvalid[1];
  assign s0.wdata  = s_wdata[0];   assign s1.wdata  = s_wdata[1];
  assign s0.wstrb  = s_wstrb[0];   assign s1.wstrb  = s_wstrb[1];
  assign s0.wlast  = s_wlast[0];   assign s1.wlast  = s_wlast[1];
  assign s_wready  = {s1.wready, s0.wready};

  assign s0.arvalid = s_arvalid[0];  assign s1.arvalid = s_arvalid[1];
  assign s0.arid    = s_arid[0];     assign s1.arid    = s_arid[1];
  assign s0.araddr  = s_araddr[0];   assign s1.araddr  = s_araddr[1];
  assign s0.arlen   = s_arlen[0];    assign s1.arlen   = s_arlen[1];
  assign s0.arsize  = s_arsize[0];   assign s1.arsize  = s_arsize[1];
  assign s0.arburst = s_arburst[0];  assign s1.arburst = s_arburst[1];
  assign s_arready  = {s1.arready, s0.arready};

  assign s_bvalid = {s1.bvalid, s0.bvalid};
  assign s_bid    = {s1.bid,    s0.bid};
  assign s_bresp  = {s1.bresp,  s0.bresp};
  assign s0.bready = s_bready[0];  assign s1.bready = s_bready[1];

  assign s_rvalid = {s1.rvalid, s0.rvalid};
  assign s_rid    = {s1.rid,    s0.rid};
  assign s_rdata  = {s1.rdata,  s0.rdata};
  assign s_rresp  = {s1.rresp,  s0.rresp};
  assign s_rlast  = {s1.rlast,  s0.rlast};
  assign s0.rready = s_rready[0];  assign s1.rready = s_rready[1];

  for (genvar N = 0; N < 2; N++) begin : g_mport

    skid_buffer #(.W(AW_PAY_W)) u_aw_skid (
      .aclk(aclk), .arst_n(srst_n),
      .s_valid(mi_awvalid[N]), .s_ready(mi_awready[N]), .s_data(mi_awpay[N]),
      .m_valid(aw_v[N]),       .m_ready(aw_r[N]),       .m_data(aw_p[N]));

    skid_buffer #(.W(W_PAY_W)) u_w_skid (
      .aclk(aclk), .arst_n(srst_n),
      .s_valid(mi_wvalid[N]), .s_ready(mi_wready[N]), .s_data(mi_wpay[N]),
      .m_valid(w_v[N]),       .m_ready(w_r[N]),       .m_data(w_p[N]));

    skid_buffer #(.W(AW_PAY_W)) u_ar_skid (
      .aclk(aclk), .arst_n(srst_n),
      .s_valid(mi_arvalid[N]), .s_ready(mi_arready[N]), .s_data(mi_arpay[N]),
      .m_valid(ar_v[N]),       .m_ready(ar_r[N]),       .m_data(ar_p[N]));

    addr_decoder u_aw_dec (.addr(aw_p[N].addr), .dest(aw_dest[N]));
    addr_decoder u_ar_dec (.addr(ar_p[N].addr), .dest(ar_dest[N]));

    thread_tracker u_wr_thr (
      .aclk(aclk), .arst_n(srst_n),
      .q_id(aw_p[N].id), .q_dest(aw_dest[N]),
      .q_ok(wr_thr_ok[N]), .alloc(wr_thr_alloc[N]),
      .cpl_valid(b_cpl_v[N]), .cpl_id(b_cpl_id[N]));

    thread_tracker u_rd_thr (
      .aclk(aclk), .arst_n(srst_n),
      .q_id(ar_p[N].id), .q_dest(ar_dest[N]),
      .q_ok(rd_thr_ok[N]), .alloc(rd_thr_alloc[N]),
      .cpl_valid(r_cpl_v[N]), .cpl_id(r_cpl_id[N]));

    wr_port_ctrl #(.MASTER_IDX(N)) u_wr_ctrl (
      .aclk(aclk), .arst_n(srst_n),
      .aw_valid(aw_v[N]), .aw_ready(aw_r[N]),
      .aw_id(aw_p[N].id), .aw_dest(aw_dest[N]),
      .thr_ok(wr_thr_ok[N]), .thr_alloc(wr_thr_alloc[N]),
      .w_valid(w_v[N]), .w_ready(w_r[N]), .w_last(w_p[N].last),
      .s_awvalid(p_awvalid[N]), .s_awready(p_awready[N]), .s_awid(p_awid[N]),
      .s_wvalid(p_wvalid[N]),   .s_wready(p_wready[N]),
      .arb_req(p_arb_req[N]), .arb_gnt(p_arb_gnt[N]), .arb_ack(p_arb_ack[N]),
      .decerr_busy(dw_busy[N]), .decerr_aw_accept(dw_aw_acc[N]),
      .decerr_w_beat(dw_w_beat[N]), .decerr_w_last(dw_w_last[N]),
      .other_aw_valid(aw_v[1-N]), .other_aw_dest(aw_dest[1-N]),
      .cpl_valid(b_cpl_v[N]),
      .mw_grant(mw_grant[N]), .mw_dest(mw_dest[N]));

    rd_port_ctrl #(.MASTER_IDX(N)) u_rd_ctrl (
      .aclk(aclk), .arst_n(srst_n),
      .ar_valid(ar_v[N]), .ar_ready(ar_r[N]),
      .ar_id(ar_p[N].id), .ar_dest(ar_dest[N]),
      .thr_ok(rd_thr_ok[N]), .thr_alloc(rd_thr_alloc[N]),
      .s_arvalid(p_arvalid[N]), .s_arready(p_arready[N]), .s_arid(p_arid[N]),
      .arb_req(p_rarb_req[N]), .arb_ack(p_rarb_ack[N]),
      .decerr_busy(dr_busy[N]), .decerr_ar_accept(dr_ar_acc[N]),
      .cpl_valid(r_cpl_v[N]));

    decerr_wr_resp u_dw (
      .aclk(aclk), .arst_n(srst_n),
      .aw_accept(dw_aw_acc[N]), .aw_id(aw_p[N].id),
      .w_beat(dw_w_beat[N]), .w_last(dw_w_last[N]), .busy(dw_busy[N]),
      .b_valid(dw_bvalid[N]), .b_id(dw_bid[N]), .b_resp(dw_bresp[N]),
      .b_ready(dw_bready[N]));

    decerr_rd_resp u_dr (
      .aclk(aclk), .arst_n(srst_n),
      .ar_accept(dr_ar_acc[N]), .ar_id(ar_p[N].id), .ar_len(ar_p[N].len),
      .busy(dr_busy[N]),
      .r_valid(dr_rvalid[N]), .r_id(dr_rid[N]),
      .r_data(dr_rpay[N].data), .r_resp(dr_rpay[N].resp),
      .r_last(dr_rlast[N]), .r_ready(dr_rready[N]));

    resp_return_mux #(.PAYLOAD_W(2), .BURST_ATOMIC(1'b0), .MY_TAG(N[0])) u_b_mux (
      .aclk(aclk), .arst_n(srst_n),
      .s_valid(sb_valid), .s_id(sb_id), .s_payload(sb_resp), .s_last(2'b11),
      .s_ready(sb_ready[N]),
      .d_valid(dw_bvalid[N]), .d_id(dw_bid[N]), .d_payload(dw_bresp[N]), .d_last(1'b1),
      .d_ready(dw_bready[N]),
      .m_valid(mo_bvalid[N]), .m_id(mo_bid[N]), .m_payload(mo_bresp[N]),
      .m_last(unused_b_last[N]), .m_ready(mo_bready[N]),   // B has no LAST
      .cpl_valid(b_cpl_v[N]), .cpl_id(b_cpl_id[N]));

    resp_return_mux #(.PAYLOAD_W(R_MUX_W), .BURST_ATOMIC(1'b1), .MY_TAG(N[0])) u_r_mux (
      .aclk(aclk), .arst_n(srst_n),
      .s_valid(sr_valid), .s_id(sr_id),
      .s_payload({R_MUX_W'(sr_pay[1]), R_MUX_W'(sr_pay[0])}), .s_last(sr_last_w),
      .s_ready(sr_ready[N]),
      .d_valid(dr_rvalid[N]), .d_id(dr_rid[N]), .d_payload(dr_rpay[N]),
      .d_last(dr_rlast[N]), .d_ready(dr_rready[N]),
      .m_valid(mo_rvalid[N]), .m_id(mo_rid[N]), .m_payload(mo_rpay[N]),
      .m_last(mo_rlast[N]), .m_ready(mo_rready[N]),
      .cpl_valid(r_cpl_v[N]), .cpl_id(r_cpl_id[N]));
  end

  for (genvar M = 0; M < 2; M++) begin : g_xpose
    for (genvar N = 0; N < 2; N++) begin : g_n
      assign q_awvalid [M][N] = p_awvalid [N][M];
      assign p_awready [N][M] = q_awready [M][N];
      assign q_wvalid  [M][N] = p_wvalid  [N][M];
      assign p_wready  [N][M] = q_wready  [M][N];
      assign q_arvalid [M][N] = p_arvalid [N][M];
      assign p_arready [N][M] = q_arready [M][N];

      assign q_arb_req [M][N] = p_arb_req [N][M];
      assign q_arb_ack [M][N] = p_arb_ack [N][M];
      assign p_arb_gnt [N][M] = q_arb_gnt [M][N];
      assign q_rarb_req[M][N] = p_rarb_req[N][M];
      assign q_rarb_ack[M][N] = p_rarb_ack[N][M];

      assign x_awid   [M][N] = p_awid[N];
      assign x_awaddr [M][N] = aw_p[N].addr;
      assign x_awlen  [M][N] = aw_p[N].len;
      assign x_awsize [M][N] = aw_p[N].size;
      assign x_awburst[M][N] = aw_p[N].burst;
      assign x_arid   [M][N] = p_arid[N];
      assign x_araddr [M][N] = ar_p[N].addr;
      assign x_arlen  [M][N] = ar_p[N].len;
      assign x_arsize [M][N] = ar_p[N].size;
      assign x_arburst[M][N] = ar_p[N].burst;
      assign x_wdata  [M][N] = w_p[N].data;
      assign x_wstrb  [M][N] = w_p[N].strb;
      assign x_wlast  [M][N] = w_p[N].last;
    end
  end

  for (genvar M = 0; M < 2; M++) begin : g_sport

    slave_wr_port u_swr (
      .aclk(aclk), .arst_n(srst_n),
      .m_awvalid(q_awvalid[M]), .m_awready(q_awready[M]),
      .m_awid(x_awid[M]), .m_awaddr(x_awaddr[M]), .m_awlen(x_awlen[M]),
      .m_awsize(x_awsize[M]), .m_awburst(x_awburst[M]),
      .m_wvalid(q_wvalid[M]), .m_wready(q_wready[M]),
      .m_wdata(x_wdata[M]), .m_wstrb(x_wstrb[M]), .m_wlast(x_wlast[M]),
      .arb_req(q_arb_req[M]), .arb_ack(q_arb_ack[M]), .arb_gnt(q_arb_gnt[M]),
      .s_awvalid(s_awvalid[M]), .s_awready(s_awready[M]), .s_awid(s_awid[M]),
      .s_awaddr(s_awaddr[M]), .s_awlen(s_awlen[M]), .s_awsize(s_awsize[M]),
      .s_awburst(s_awburst[M]),
      .s_wvalid(s_wvalid[M]), .s_wready(s_wready[M]),
      .s_wdata(s_wdata[M]), .s_wstrb(s_wstrb[M]), .s_wlast(s_wlast[M]));

    slave_rd_port u_srd (
      .aclk(aclk), .arst_n(srst_n),
      .m_arvalid(q_arvalid[M]), .m_arready(q_arready[M]),
      .m_arid(x_arid[M]), .m_araddr(x_araddr[M]), .m_arlen(x_arlen[M]),
      .m_arsize(x_arsize[M]), .m_arburst(x_arburst[M]),
      .arb_req(q_rarb_req[M]), .arb_ack(q_rarb_ack[M]), .arb_gnt(q_rarb_gnt[M]),
      .s_arvalid(s_arvalid[M]), .s_arready(s_arready[M]), .s_arid(s_arid[M]),
      .s_araddr(s_araddr[M]), .s_arlen(s_arlen[M]), .s_arsize(s_arsize[M]),
      .s_arburst(s_arburst[M]));

    bpay_t sb_in, sb_out;
    assign sb_in = '{id:s_bid[M], resp:s_bresp[M]};
    skid_buffer #(.W(B_PAY_W)) u_b_skid (
      .aclk(aclk), .arst_n(srst_n),
      .s_valid(s_bvalid[M]), .s_ready(s_bready[M]), .s_data(sb_in),
      .m_valid(sb_valid[M]), .m_ready(sb_ready_or[M]), .m_data(sb_out));
    assign sb_id[M]   = sb_out.id;
    assign sb_resp[M] = sb_out.resp;

    rpay_t sr_in, sr_out;
    assign sr_in = '{id:s_rid[M], data:s_rdata[M], resp:s_rresp[M], last:s_rlast[M]};
    skid_buffer #(.W(R_PAY_W)) u_r_skid (
      .aclk(aclk), .arst_n(srst_n),
      .s_valid(s_rvalid[M]), .s_ready(s_rready[M]), .s_data(sr_in),
      .m_valid(sr_valid[M]), .m_ready(sr_ready_or[M]), .m_data(sr_out));
    assign sr_id[M]     = sr_out.id;
    assign sr_pay[M]    = '{data:sr_out.data, resp:sr_out.resp};
    assign sr_last_w[M] = sr_out.last;

    assign sb_ready_or[M] = sb_ready[0][M] | sb_ready[1][M];
    assign sr_ready_or[M] = sr_ready[0][M] | sr_ready[1][M];
  end

endmodule : axi4_xbar_top
