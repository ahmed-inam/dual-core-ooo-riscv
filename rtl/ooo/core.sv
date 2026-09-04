// The two-wide out-of-order core: fetch through commit.
module core
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
#(
  parameter word_t RESET_PC_P  = RESET_PC,
  parameter bit    USE_HISTORY = 1'b1,   // gshare history on/off
  parameter bit    OVF_COUNT   = 1'b1    // RAS overflow policy, see ras.sv
) (
  input  logic  clk,
  input  logic  rst_n,

  input  word_t hart_id_i,

  input  logic  snoop_valid_i,
  input  word_t snoop_addr_i,

  output logic  lrsc_lr_valid_o,
  output logic  lrsc_sc_valid_o,
  output word_t lrsc_addr_o,
  output logic  lrsc_acc_valid_o,
  input  logic  lrsc_sc_success_i,

  output logic  ireq,
  input  logic  ignt,
  output word_t iaddr,
  input  logic  irvalid,
  input  word_t irdata,
  input  logic  irerr = 1'b0,   // with irvalid: instruction access fault
  input  logic [3:0][31:0] irdata_line,
  input  logic [3:0]       iwmask,

  output logic  dreq,
  input  logic  dgnt,
  output word_t daddr,
  output logic  dwe,
  output logic  dis_lr,   // LR write-intent to the dcache
  output logic [3:0] dwstrb,
  output word_t dwdata,
  input  logic  drvalid,
  input  word_t drdata,
  input  logic  drerr = 1'b0,   // with drvalid: load access fault

  input  logic  ev_ic_miss,
  input  logic  ev_dc_miss,
  input  logic  ev_dc_wb,
  output logic  ic_flush,
  output logic  dc_flush,
  input  logic  dc_flush_done,

  input  logic  irq_timer,
  input  logic  irq_soft,
  input  logic  irq_ext,

  output logic     [COMMIT_W-1:0]        rvfi_valid,
  output logic     [COMMIT_W-1:0][63:0]  rvfi_order,
  output word_t    [COMMIT_W-1:0]        rvfi_insn,
  output logic     [COMMIT_W-1:0]        rvfi_trap,
  output word_t    [COMMIT_W-1:0]        rvfi_pc_rdata,
  output regaddr_t [COMMIT_W-1:0]        rvfi_rd_addr,
  output word_t    [COMMIT_W-1:0]        rvfi_rd_wdata,
  output logic     [COMMIT_W-1:0]        rvfi_halt,
  output logic     [COMMIT_W-1:0]        rvfi_intr,
  output logic     [COMMIT_W-1:0][1:0]   rvfi_mode,
  output logic     [COMMIT_W-1:0][1:0]   rvfi_ixl,
  output regaddr_t [COMMIT_W-1:0]        rvfi_rs1_addr,
  output regaddr_t [COMMIT_W-1:0]        rvfi_rs2_addr,
  output word_t    [COMMIT_W-1:0]        rvfi_rs1_rdata,
  output word_t    [COMMIT_W-1:0]        rvfi_rs2_rdata,
  output word_t    [COMMIT_W-1:0]        rvfi_pc_wdata,
  output word_t    [COMMIT_W-1:0]        rvfi_mem_addr,
  output logic     [COMMIT_W-1:0][3:0]   rvfi_mem_rmask,
  output logic     [COMMIT_W-1:0][3:0]   rvfi_mem_wmask,
  output word_t    [COMMIT_W-1:0]        rvfi_mem_rdata,
  output word_t    [COMMIT_W-1:0]        rvfi_mem_wdata,

  output logic                          trap_taken
);


  logic rvfi_exc_emit;

`ifndef RVFI_NO_SIDEBAND
  typedef struct packed {
    word_t rs1_v;
    word_t rs2_v;
    word_t npc;        // resolved next pc, meaningful for control flow only
    word_t      m_addr;
    word_t      m_rdata;
    word_t      m_wdata;
    logic [3:0] m_rmask;
    logic [3:0] m_wmask;
  } rvfi_side_t;
  rvfi_side_t rvfi_side [ROB_N];

  logic             lsq_m_ld_valid, lsq_m_st_valid;
  rob_ptr_t         lsq_m_ld_id,    lsq_m_st_id;
  word_t            lsq_m_ld_addr,  lsq_m_ld_rdata;
  word_t            lsq_m_st_addr,  lsq_m_st_wdata;
  logic [3:0]       lsq_m_ld_rmask, lsq_m_st_wmask;

  logic [ROB_W-1:0] rvfi_alloc_id [RENAME_W];
  logic [RENAME_W-1:0] rvfi_alloc_fire;
`endif

  word_t rvfi_prev_pc_wdata;
  logic  rvfi_prev_valid;

  logic [ROB_W-1:0] rvfi_commit_id [COMMIT_W];
  word_t            rvfi_mtvec, rvfi_mepc;

  logic [63:0] rvfi_order_q;
  logic [COMMIT_W-1:0][63:0] rvfi_order_slot;
  always_comb begin
    automatic logic [63:0] acc = rvfi_order_q;
    for (int i = 0; i < COMMIT_W; i++) begin
      rvfi_order_slot[i] = acc;
      acc = acc + 64'((i == 0) ? (commit_o[i].valid || rvfi_exc_emit)
                               : commit_o[i].valid);
    end
  end
  logic [$clog2(COMMIT_W+1)-1:0] rvfi_n_commit;
  always_comb begin
    rvfi_n_commit = '0;
    for (int i = 0; i < COMMIT_W; i++)
      rvfi_n_commit = rvfi_n_commit + ($bits(rvfi_n_commit))'(
        (i == 0) ? (commit_o[i].valid || rvfi_exc_emit) : commit_o[i].valid);
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) rvfi_order_q <= '0;
    else        rvfi_order_q <= rvfi_order_q + 64'(rvfi_n_commit);
  end
  always_comb begin
    automatic word_t prev_pcw = rvfi_prev_pc_wdata;
    automatic logic  prev_ok  = rvfi_prev_valid;
    for (int i = 0; i < COMMIT_W; i++) begin
      rvfi_valid[i]    = commit_o[i].valid || ((i == 0) && rvfi_exc_emit);
      rvfi_order[i]    = rvfi_order_slot[i];
      rvfi_insn[i]     = commit_o[i].instr;
      rvfi_trap[i]     = (i == 0) && rvfi_exc_emit;
      rvfi_pc_rdata[i] = commit_o[i].pc;
      rvfi_rd_addr[i]  = (commit_o[i].rf_we && !((i == 0) && rvfi_exc_emit))
                           ? commit_o[i].lrd   : 5'd0;
      rvfi_rd_wdata[i] = (commit_o[i].rf_we && !((i == 0) && rvfi_exc_emit))
                           ? commit_o[i].wdata : 32'd0;

      rvfi_mode[i]      = 2'd3;
      rvfi_ixl[i]       = 2'd1;
      rvfi_halt[i]      = 1'b0;

      rvfi_rs1_addr[i]  = commit_o[i].lrs1;
      rvfi_rs2_addr[i]  = commit_o[i].lrs2;
`ifndef RVFI_NO_SIDEBAND
      rvfi_rs1_rdata[i] = rvfi_side[rvfi_commit_id[i]].rs1_v;
      rvfi_rs2_rdata[i] = rvfi_side[rvfi_commit_id[i]].rs2_v;
      rvfi_pc_wdata[i]  = ((i == 0) && rvfi_exc_emit) ? rvfi_mtvec
                        : commit_o[i].is_mret         ? rvfi_mepc
                        : commit_o[i].is_branch       ? rvfi_side[rvfi_commit_id[i]].npc
                        :                               (commit_o[i].pc + 32'd4);
`else
      rvfi_rs1_rdata[i] = 32'd0;
      rvfi_rs2_rdata[i] = 32'd0;
      rvfi_pc_wdata[i]  = ((i == 0) && rvfi_exc_emit) ? rvfi_mtvec
                        : commit_o[i].is_mret         ? rvfi_mepc
                        :                               (commit_o[i].pc + 32'd4);
`endif
`ifndef RVFI_NO_SIDEBAND
      rvfi_mem_addr[i]  = commit_o[i].is_mem ? rvfi_side[rvfi_commit_id[i]].m_addr  : 32'd0;
      rvfi_mem_rdata[i] = commit_o[i].is_mem ? rvfi_side[rvfi_commit_id[i]].m_rdata : 32'd0;
      rvfi_mem_wdata[i] = commit_o[i].is_mem ? rvfi_side[rvfi_commit_id[i]].m_wdata : 32'd0;
      rvfi_mem_rmask[i] = (commit_o[i].is_mem && !commit_o[i].is_store)
                            ? rvfi_side[rvfi_commit_id[i]].m_rmask : 4'd0;
      rvfi_mem_wmask[i] = (commit_o[i].is_mem &&  commit_o[i].is_store)
                            ? rvfi_side[rvfi_commit_id[i]].m_wmask : 4'd0;
`else
      rvfi_mem_addr[i]  = 32'd0;
      rvfi_mem_rdata[i] = 32'd0;
      rvfi_mem_wdata[i] = 32'd0;
      rvfi_mem_rmask[i] = 4'd0;
      rvfi_mem_wmask[i] = 4'd0;
`endif
      rvfi_intr[i]      = rvfi_valid[i] && prev_ok && (commit_o[i].pc != prev_pcw);
      if (rvfi_valid[i]) begin
        prev_pcw = rvfi_pc_wdata[i];
        prev_ok  = 1'b1;
      end
    end
  end

  logic     fq_out_valid, fq_out_ready, fetch_accept;
  word_t    fq_out_pc, fq_out_instr;
  bp_pred_t fq_out_bp;
  logic     redirect_valid, redirect_consumed;
  word_t    redirect_target;

  bp_pred_t   bp_pred;
  bp_update_t bp_update;
  localparam int unsigned FQ_WPL = 4;
  bp_pred_t [FQ_WPL-1:0] bp_pred_vec;
  logic     [FQ_WPL-1:0] bp_word_valid;
  bp_top #(.USE_HISTORY(USE_HISTORY), .OVF_COUNT(OVF_COUNT), .FETCH_WIDE(1'b1)) u_bp (
    .clk, .rst_n,
    .fetch_pc_en (fetch_accept),
    .fetch_pc    (iaddr),
    .fetch_valid (fetch_accept),
    .pred        (bp_pred),
    .pred_vec    (bp_pred_vec),
    .word_valid  (bp_word_valid),
    .update      (bp_update),
    .trap_flush  (recov_redir && !r_is_bpr_q),  // history repair on every
    .trap_snapshot (r_bsnap_q),
    .btb_flush   (ic_flush)
  );

  logic [1:0]     fq_out_valid_v;
  word_t [1:0]    fq_out_pc_v, fq_out_instr_v;
  bp_pred_t [1:0] fq_out_bp_v;
  logic [1:0]     fq_out_err_v;
  logic [1:0]     fq_out_pop_n;
  assign fq_out_valid = fq_out_valid_v[0];
  assign fq_out_pc    = fq_out_pc_v[0];
  assign fq_out_instr = fq_out_instr_v[0];
  assign fq_out_bp    = fq_out_bp_v[0];
  assign fq_out_pop_n = disp_fire1 ? 2'd2          // dual dispatch
                      : dispatch_fire ? 2'd1 : 2'd0; // slot-0-only, or none

  fetch_queue #(.DEPTH(8), .RESET_PC_P(RESET_PC_P), .FETCH_WIDE(1'b1)) u_fq (
    .clk, .rst_n,
    .ireq, .ignt, .iaddr, .irvalid, .irdata,
    .irerr                   (irerr),
    .irdata_line             (irdata_line),
    .iwmask                  (iwmask),
    .bp_pred                 (bp_pred),
    .bp_pred_vec             (bp_pred_vec),
    .word_valid              (bp_word_valid),
    .accept                  (fetch_accept),
    .redirect_resolve_valid  (redirect_valid),
    .redirect_resolve_target (redirect_target),
    .ex_mem_en               (redirect_consumed), // resolve event completes
    .redirect_trap_valid     (1'b0),             // traps: 4c-6
    .redirect_trap_target    ('0),
    .out_pop_n               (fq_out_pop_n),
    .out_valid               (fq_out_valid_v),
    .out_pc                  (fq_out_pc_v),
    .out_instr               (fq_out_instr_v),
    .out_bp                  (fq_out_bp_v),
    .out_err                 (fq_out_err_v),
    .out_empty               ()
  );

  ctrl_t [WIDTH-1:0] ctrl_dv, ctrl_dec;
  word_t [WIDTH-1:0] imm_dv;
  genvar gd;
  generate
    for (gd = 0; gd < WIDTH; gd++) begin : g_decode
      decoder u_dec (.instr(fq_out_instr_v[gd]), .ctrl(ctrl_dec[gd]));
      assign ctrl_dv[gd] = fq_out_err_v[gd] ? CTRL_ILLEGAL : ctrl_dec[gd];
      imm_gen u_imm (.instr(fq_out_instr_v[gd]), .imm_type(ctrl_dv[gd].imm_type),
                     .imm(imm_dv[gd]));
    end
  endgenerate
  ctrl_t ctrl_d;
  word_t imm_d;
  assign ctrl_d = ctrl_dv[0];
  assign imm_d  = imm_dv[0];

  logic [4:0] lrs1_d, lrs2_d, lrd_d;
  assign lrs1_d = fq_out_instr[19:15];
  assign lrs2_d = fq_out_instr[24:20];
  assign lrd_d  = walk_undo_ldst_sel ? walk_ldst : fq_out_instr[11:7];

  logic writes_d, is_mem_d, is_cf_d, no_exec_d;
  assign writes_d = ctrl_d.rf_we && (lrd_d != 5'd0);
  assign is_mem_d = ctrl_d.mem_re || ctrl_d.mem_we;
  assign is_cf_d  = (ctrl_d.cf_type != CF_NONE);
  assign no_exec_d = ctrl_d.is_fence || ctrl_d.is_fence_i || ctrl_d.illegal
                  || ctrl_d.is_ecall || ctrl_d.is_ebreak  || ctrl_d.is_mret;
  logic is_csr_d;
  assign is_csr_d = (ctrl_d.csr_op != CSR_OP_NONE);

  logic [4:0] lrs1_1, lrs2_1, lrd_1;
  assign lrs1_1 = fq_out_instr_v[1][19:15];
  assign lrs2_1 = fq_out_instr_v[1][24:20];
  assign lrd_1  = fq_out_instr_v[1][11:7];
  logic writes_1, is_mem_1, is_cf_1, no_exec_1, is_csr_1;
  assign writes_1  = ctrl_dv[1].rf_we && (lrd_1 != 5'd0);
  assign is_mem_1  = ctrl_dv[1].mem_re || ctrl_dv[1].mem_we;
  assign is_cf_1   = (ctrl_dv[1].cf_type != CF_NONE);
  assign no_exec_1 = ctrl_dv[1].is_fence || ctrl_dv[1].is_fence_i || ctrl_dv[1].illegal
                  || ctrl_dv[1].is_ecall || ctrl_dv[1].is_ebreak  || ctrl_dv[1].is_mret;
  assign is_csr_1  = (ctrl_dv[1].csr_op != CSR_OP_NONE);

  preg_t [WIDTH-1:0] r_prs1, r_prs2, r_stale, r_remap_pdst;
  logic  [WIDTH-1:0] r_remap_valid;
  preg_t [31:0]      map_dbg;
  logic  [WIDTH-1:0] fl_can_alloc, fl_alloc_fire, fl_free_fire;
  preg_t [WIDTH-1:0] fl_alloc_preg, fl_free_preg;
  logic [PREG_W:0]   fl_count;

  logic branch_pending_q;
  logic dispatch_fire;
  logic walk_undo_ldst_sel;
  logic [4:0] walk_ldst;

  logic [WIDTH-1:0][4:0] rmt_lrs1, rmt_lrs2, rmt_ldst;
  logic [WIDTH-1:0]      rmt_snap_take;
  snap_ptr_t [WIDTH-1:0] rmt_snap_id_i;
  always_comb begin
    rmt_lrs1 = '0; rmt_lrs2 = '0; rmt_ldst = '0;
    rmt_snap_take = '0; rmt_snap_id_i = '0;
    rmt_lrs1[0]      = lrs1_d;
    rmt_lrs2[0]      = lrs2_d;
    rmt_ldst[0]      = lrd_d;
    rmt_snap_take[0] = dispatch_fire && is_cf_d;
    rmt_snap_id_i[0] = SNAP_W'(snap_tail_q);
    if (WIDTH > 1) begin
      rmt_lrs1[1]      = lrs1_1;
      rmt_lrs2[1]      = lrs2_1;
      rmt_ldst[1]      = lrd_1;
      rmt_snap_take[1] = disp_fire1 && is_cf_1;
      rmt_snap_id_i[1] = SNAP_W'(snap_tail_q + snap_ptr_t'(rmt_snap_take[0]));
    end
  end

  rename u_rmt (
    .clk, .rst_n,
    .lrs1(rmt_lrs1), .lrs2(rmt_lrs2), .ldst(rmt_ldst),
    .prs1(r_prs1), .prs2(r_prs2), .stale_pdst(r_stale),
    .remap_valid(r_remap_valid), .remap_pdst(r_remap_pdst),
    .snap_take(rmt_snap_take), .snap_id_i(rmt_snap_id_i),
    .snap_restore(snap_restore_fire), .snap_id_r(bpr_snap_q),
    .map_dbg(map_dbg)
  );

  freelist u_fl (
    .clk, .rst_n,
    .can_alloc(fl_can_alloc), .alloc_fire(fl_alloc_fire),
    .alloc_preg(fl_alloc_preg),
    .free_fire(fl_free_fire), .free_preg(fl_free_preg),
    .snap_take(dispatch_fire && is_cf_d), .snap_restore(snap_restore_fire),
    .snap_id(snap_restore_fire ? bpr_snap_q : SNAP_W'(snap_tail_q)),
    .count(fl_count)
  );

  logic                     rob_allocatable;
  logic [RENAME_W-1:0]      rob_alloc_valid;
  uop_t [RENAME_W-1:0]      rob_alloc_uop;
  rob_ptr_t [RENAME_W-1:0]  rob_alloc_id;
  logic  [WAKEUP_W-1:0]     comp_valid;
  rob_ptr_t [WAKEUP_W-1:0]  comp_id;
  logic  [WAKEUP_W-1:0][31:0] comp_wdata;
  commit_t [COMMIT_W-1:0]   commit_o;
  logic [COMMIT_W-1:0]      rob_free_valid, rob_store_release;
  preg_t [COMMIT_W-1:0]     rob_free_preg;
  logic                     exc_at_head;
  logic [3:0]               exc_cause;
  word_t                    exc_tval, exc_pc;
  logic rob_head_valid, rob_head_done, rob_head_is_mem, rob_head_is_csr;
  logic rob_head_is_fence, rob_head_is_fence_i, rob_head_is_mret;
  logic comp_exc0; logic [3:0] comp_cause0; word_t comp_tval0;
  logic  [WAKEUP_W-1:0]      comp_exc_v;
  logic  [WAKEUP_W-1:0][3:0] comp_cause_v;
  logic  [WAKEUP_W-1:0][31:0] comp_tval_v;
  always_comb begin
    comp_exc_v[0]   = comp_exc0;
    comp_cause_v[0] = comp_cause0;
    comp_tval_v[0]  = comp_tval0;
  end
  if (WIDTH > 1) begin : g_lane2_noexc
    assign comp_exc_v[2]   = 1'b0;
    assign comp_cause_v[2] = '0;
    assign comp_tval_v[2]  = '0;
  end
  logic commit_ready, recovery_idle, csr_active, csr_comp, csr_illegal;
  word_t csr_old;
  logic mem_exc;
  logic br_tmis;
  rob_ptr_t                 rob_head_id;
  logic [ROB_W:0]           rob_count;

  rob u_rob (
    .clk, .rst_n,
    .allocatable(rob_allocatable),
    .alloc_valid(rob_alloc_valid), .alloc_uop(rob_alloc_uop),
    .alloc_ferr(fq_out_err_v[RENAME_W-1:0]),
    .alloc_id(rob_alloc_id),
    .comp_valid(comp_valid), .comp_id(comp_id), .comp_wdata(comp_wdata),
    .comp_exc(comp_exc_v), .comp_cause(comp_cause_v),
    .comp_tval(comp_tval_v),
    .commit_ready(commit_ready),
    .commit_single(rq_q == R_ACT),
    .commit_o(commit_o),
    .free_valid(rob_free_valid), .free_preg(rob_free_preg),
    .store_release(rob_store_release),
    .exc_at_head(exc_at_head), .exc_cause(exc_cause),
    .exc_tval(exc_tval), .exc_pc(exc_pc),
    .walk_pop(walk_pop), .walk_valid(walk_valid), .walk_entry(walk_entry),
    .walk_id(rob_walk_id),
    .head_bsnap(rob_head_bsnap), .tail_o(rob_tail_o),
    .viol_set(viol_any), .viol_set_id(viol_any_id),   // LSQ and snoop violations, merged
    .head_viol(rob_head_viol), .head_pc(rob_head_pc),
    .restore_valid(snap_restore_fire),
    .restore_tail(snapb_rob_q[bpr_snap_q]),
    .flush_all(1'b0),
    .head_valid(rob_head_valid), .head_done(rob_head_done),
    .head_is_mem(rob_head_is_mem), .head_is_csr(rob_head_is_csr),
    .head_is_fence(rob_head_is_fence),
    .head_is_fence_i(rob_head_is_fence_i), .head_is_mret(rob_head_is_mret),
    .head_id(rob_head_id),
    .count(rob_count)
  );

  logic  stub_disp_valid, stub_disp_ready, iss_valid, iss_ready;
  logic  iq_starved;
  uop_t  stub_disp_uop, iss_uop;
  logic  iss_valid_1, iss_ready_1;
  uop_t  iss_uop_1;
  preg_t [2*WIDTH-1:0] busy_raddr;
  logic  [2*WIDTH-1:0] busy_rdata;

  logic [WIDTH-1:0] iq_disp_valid;
  uop_t [WIDTH-1:0] iq_disp_uop;
  logic [WIDTH-1:0] iq_disp_ready;
  assign iq_disp_valid[0] = stub_disp_valid;
  assign iq_disp_uop[0]   = stub_disp_uop;
  assign stub_disp_ready  = iq_disp_ready[0];
  if (WIDTH > 1) begin : g_slot1_iqdisp
    assign iq_disp_valid[1] = disp_fire1 && !no_exec_1 && !is_csr_1;
    assign iq_disp_uop[1]   = disp_uop_1;
  end

  issue_queue u_iq (
    .clk, .rst_n,
    .disp_valid(iq_disp_valid), .disp_uop(iq_disp_uop),
    .disp_ready(iq_disp_ready),
    .iss_valid(iss_valid), .iss_uop(iss_uop), .iss_ready(iss_ready),
    .iss_valid_1(iss_valid_1), .iss_uop_1(iss_uop_1), .iss_ready_1(iss_ready_1),
    .busy_raddr(busy_raddr), .busy_rdata(busy_rdata),
    .wakeup_valid(iq_wake_valid),
    .wakeup_preg(iq_wake_preg),
    .div_ok(div_ok),
    .flush_all(stub_flush),
    .squash_valid(iq_squash),
    .squash_base(bpr_base_q),
    .squash_bound((ROB_W+1)'(bpr_age_q))
  );

  assign dispatch_fire = fq_out_valid
                      && rob_allocatable
                      && (no_exec_d || is_csr_d || stub_disp_ready)
                      && (!writes_d || fl_can_alloc[0])
                      && (!(is_mem_d && ctrl_d.mem_we) || sq_can_alloc)
                      && (!(is_mem_d && ctrl_d.mem_re) || lq_can_alloc)
                      && (!is_cf_d || snap_can_alloc[0])
                      && recovery_idle;
  assign fq_out_ready = dispatch_fire;

  logic slot0_simple, slot1_simple;
  assign slot0_simple = !is_mem_d && !is_cf_d && !is_csr_d && !no_exec_d;
  assign slot1_simple = !is_mem_1 && !is_cf_1 && !is_csr_1 && !no_exec_1;

  logic disp_fire1;
  if (WIDTH > 1) begin : g_disp_fire1
    assign disp_fire1 = dispatch_fire
                     && fq_out_valid_v[1]        // slot 1 actually present
                     && slot0_simple && slot1_simple
                     && (!writes_1 || fl_can_alloc[1])  // freelist room for two
                     && iq_disp_ready[1];               // IQ room for two
  end else begin : g_disp_fire1_off
    assign disp_fire1 = 1'b0;
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n)
    if (disp_fire1 && (is_cf_d || is_cf_1))
      $fatal(1, "core: control-flow op in a dual-dispatch group");
`endif

  logic w0_alloc, w1_alloc;
  assign w0_alloc = dispatch_fire && writes_d;
  assign w1_alloc = disp_fire1 && writes_1;
  preg_t slot1_pdst;
  assign slot1_pdst = w0_alloc ? fl_alloc_preg[1] : fl_alloc_preg[0];

  uop_t disp_uop;
  always_comb begin
    disp_uop            = '0;
    disp_uop.valid      = 1'b1;
    disp_uop.pc         = fq_out_pc;
    disp_uop.instr      = fq_out_instr;
    disp_uop.ctrl       = ctrl_d;
    disp_uop.imm        = imm_d;
    disp_uop.lrs1       = lrs1_d;
    disp_uop.lrs2       = lrs2_d;
    disp_uop.lrd        = lrd_d;
    disp_uop.prs1       = r_prs1[0];
    disp_uop.prs2       = r_prs2[0];
    disp_uop.pdst       = writes_d ? fl_alloc_preg[0] : preg_t'(0);
    disp_uop.stale_pdst = r_stale[0];
    disp_uop.rob_id     = rob_alloc_id[0];
    disp_uop.pred       = fq_out_bp;
    disp_uop.snap_id    = SNAP_W'(snap_tail_q);
  end

  uop_t disp_uop_1;
  always_comb begin
    disp_uop_1            = '0;
    disp_uop_1.valid      = 1'b1;
    disp_uop_1.pc         = fq_out_pc_v[1];
    disp_uop_1.instr      = fq_out_instr_v[1];
    disp_uop_1.ctrl       = ctrl_dv[1];
    disp_uop_1.imm        = imm_dv[1];
    disp_uop_1.lrs1       = lrs1_1;
    disp_uop_1.lrs2       = lrs2_1;
    disp_uop_1.lrd        = lrd_1;
    disp_uop_1.prs1       = r_prs1[1];
    disp_uop_1.prs2       = r_prs2[1];
    disp_uop_1.pdst       = writes_1 ? slot1_pdst : preg_t'(0);
    disp_uop_1.stale_pdst = r_stale[1];
    disp_uop_1.rob_id     = rob_alloc_id[1];
    disp_uop_1.pred       = fq_out_bp_v[1];
    disp_uop_1.snap_id    = SNAP_W'(snap_tail_q + snap_ptr_t'(rmt_snap_take[0]));
  end

  assign rob_alloc_valid[0] = dispatch_fire;
  assign rob_alloc_uop[0]   = disp_uop;
  assign fl_alloc_fire[0]   = w0_alloc || w1_alloc;
  logic walk_undo;
  assign walk_undo        = walk_pop && walk_entry.rf_we;
  assign r_remap_valid[0] = (dispatch_fire && writes_d) || walk_undo;
  assign r_remap_pdst[0]  = walk_undo ? walk_entry.stale_pdst
                                      : fl_alloc_preg[0];
  if (WIDTH > 1) begin : g_slot1_alloc
    assign rob_alloc_valid[1] = disp_fire1;
    assign rob_alloc_uop[1]   = disp_uop_1;
    assign fl_alloc_fire[1]   = w0_alloc && w1_alloc;
    assign r_remap_valid[1]   = disp_fire1 && writes_1;
    assign r_remap_pdst [1]   = slot1_pdst;
  end
  assign stub_disp_valid    = dispatch_fire && !no_exec_d && !is_csr_d;
  assign stub_disp_uop      = disp_uop;



  logic  lq_can_alloc, sq_can_alloc, lsq_quiet;
  logic  commit_mem_load;
  always_comb begin
    commit_mem_load = 1'b0;
    for (int i = 0; i < COMMIT_W; i++)
      if (commit_o[i].valid && commit_o[i].is_mem && !commit_o[i].is_store)
        commit_mem_load = 1'b1;
  end
  logic  lsq_ld_comp_valid, lsq_ld_comp_ready, lsq_ld_comp_err;
  rob_ptr_t lsq_ld_comp_rob_id;
  preg_t lsq_ld_comp_pdst;
  word_t lsq_ld_comp_data, lsq_ld_comp_addr;

  logic  is_load_ex, is_store_ex, mem_ex;
  assign is_load_ex  = ex_uop.ctrl.mem_re;
  assign is_store_ex = ex_uop.ctrl.mem_we;
  assign mem_ex      = is_load_ex || is_store_ex;
  logic  mem_mis_ex;
  always_comb begin
    unique case (ex_uop.ctrl.mem_size)
      MEM_W:          mem_mis_ex = (alu_result[1:0] != 2'b00);
      MEM_H, MEM_HU:  mem_mis_ex = alu_result[0];
      default:        mem_mis_ex = 1'b0;
    endcase
  end

  lsq u_lsq (
    .clk, .rst_n,
    .alloc_load (dispatch_fire && ctrl_d.mem_re),
    .alloc_store(dispatch_fire && ctrl_d.mem_we),
    .alloc_is_lr(dispatch_fire && ctrl_d.is_lr),
    .alloc_is_sc(dispatch_fire && ctrl_d.is_sc),
    .alloc_pdst(writes_d ? fl_alloc_preg[0] : preg_t'(0)),
    .sc_head_go(sc_head_go),
    .sc_done_pulse(lsq_sc_done), .sc_done_rob_id(lsq_sc_rob_id),
    .sc_done_pdst(lsq_sc_pdst),  .sc_done_val(lsq_sc_val),
    .lrsc_lr_valid(lrsc_lr_valid_o), .lrsc_sc_valid(lrsc_sc_valid_o),
    .lrsc_addr(lrsc_addr_o), .lrsc_acc_valid(lrsc_acc_valid_o),
    .lrsc_sc_success(lrsc_sc_success_i),
    .alloc_rob_id(rob_alloc_id[0]),
    .lq_can_alloc, .sq_can_alloc,
    .fill_valid   (ex_go && mem_ex && !mem_mis_ex),
    .fill_is_store(is_store_ex),
    .fill_rob_id  (ex_uop.rob_id),
    .fill_addr    (alu_result),
    .fill_size    (ex_uop.ctrl.mem_size),
    .fill_wdata   (rs2_v),
    .fill_pdst    (ex_uop.pdst),
    .ld_comp_valid (lsq_ld_comp_valid),
    .ld_comp_ready (lsq_ld_comp_ready),
    .ld_comp_rob_id(lsq_ld_comp_rob_id),
    .ld_comp_pdst  (lsq_ld_comp_pdst),
    .ld_comp_data  (lsq_ld_comp_data),
    .ld_comp_err   (lsq_ld_comp_err),
    .ld_comp_addr  (lsq_ld_comp_addr),
    .store_release (|rob_store_release),
    .load_release  (commit_mem_load),
    .lq_walk_pop   (walk_pop && walk_entry.is_mem && !walk_entry.is_store),
    .sq_walk_pop   (walk_pop && walk_entry.is_store),
    .rvfi_m_ld_valid(lsq_m_ld_valid), .rvfi_m_ld_id(lsq_m_ld_id),
    .rvfi_m_ld_addr(lsq_m_ld_addr),   .rvfi_m_ld_rdata(lsq_m_ld_rdata),
    .rvfi_m_ld_rmask(lsq_m_ld_rmask),
    .rvfi_m_st_valid(lsq_m_st_valid), .rvfi_m_st_id(lsq_m_st_id),
    .rvfi_m_st_addr(lsq_m_st_addr),   .rvfi_m_st_wdata(lsq_m_st_wdata),
    .rvfi_m_st_wmask(lsq_m_st_wmask),
    .dreq, .dgnt, .daddr, .dwe, .dis_lr, .dwstrb, .dwdata, .drvalid, .drdata,
    .drerr,
    .recovering(rq_q != R_IDLE),   // no new memory launch during recovery
    .lr_go_ok(lr_head_go),
    .pick_rob_id_o(lsq_pick_rob_id),
    .quiet(lsq_quiet),
    .lq_tail_o(lsq_lq_tail), .sq_tail_o(lsq_sq_tail),
    .restore_valid(snap_restore_fire),
    .lq_restore_tail(snapb_lq_q[bpr_snap_q]),
    .sq_restore_tail(snapb_sq_q[bpr_snap_q]),
    .viol_valid(lsq_viol_valid), .viol_rob_id(lsq_viol_rob_id),
    .snoop_valid(snoop_valid_i), .snoop_addr(snoop_addr_i),
    .snoop_hit(lsq_snoop_hit), .snoop_hit_rob_id(lsq_snoop_rob_id)
  );

  typedef struct packed {
    logic [11:0] addr;
    csr_op_e     op;
    logic        use_imm;
    logic [4:0]  zimm;
    preg_t       prs1;
    preg_t       pdst;
  } csrinfo_t;
  csrinfo_t csr_info [ROB_N];

  logic sc_is [ROB_N];
  logic lr_is [ROB_N];
  always_ff @(posedge clk) begin
    if (rst_n && dispatch_fire) begin
      sc_is[rob_alloc_id[0]] <= ctrl_d.is_sc;
      lr_is[rob_alloc_id[0]] <= ctrl_d.is_lr;
    end
    if (rst_n && disp_fire1) begin   // slot 1 never carries a memory op: clear the bits it inherits
      sc_is[rob_alloc_id[1]] <= 1'b0;
      lr_is[rob_alloc_id[1]] <= 1'b0;
    end
  end
  rob_ptr_t lsq_pick_rob_id;
  logic     lr_head_go;
  assign    lr_head_go = rob_head_valid && !rob_head_done && lr_is[rob_head_id]
                      && (rob_head_id == lsq_pick_rob_id);

  // A non-control-flow op the BTB predicted taken: a stale entry after
  // self-modifying code. It retires normally, then everything younger is
  // walked and fetch restarts at pc+4, and the BTB entry is invalidated.
  logic bogus_pred_ex;
  assign bogus_pred_ex = ex_go && (ex_uop.ctrl.cf_type == CF_NONE) && ex_uop.pred.taken;
  logic refetch_is [ROB_N];
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (dispatch_fire) refetch_is[rob_alloc_id[0]] <= 1'b0;
      if (disp_fire1)    refetch_is[rob_alloc_id[1]] <= 1'b0;
      if (bogus_pred_ex) refetch_is[ex_uop.rob_id]  <= 1'b1;
    end
  end
  logic     sc_head_go;
  assign    sc_head_go = rob_head_valid && !rob_head_done && sc_is[rob_head_id]
                      && recovery_idle;   // never launch an SC store into a recovery that walks it
  logic     lsq_sc_done;
  rob_ptr_t lsq_sc_rob_id;
  preg_t    lsq_sc_pdst;
  word_t    lsq_sc_val;
  always_ff @(posedge clk) begin
    if (rst_n && dispatch_fire && is_csr_d) begin
      csr_info[rob_alloc_id[0]] <= '{
        addr:    fq_out_instr[31:20],
        op:      ctrl_d.csr_op,
        use_imm: fq_out_instr[14],          // funct3[2]: the *I variants
        zimm:    lrs1_d,
        prs1:    r_prs1[0],
        pdst:    writes_d ? fl_alloc_preg[0] : preg_t'(0)
      };
    end
  end
  csrinfo_t ci;
  assign ci = csr_info[rob_head_id];

  assign csr_active = rob_head_valid && !rob_head_done && rob_head_is_csr
                   && recovery_idle;
  word_t csr_rdata_raw, perf_rdata;
  word_t csr_operand;
  assign csr_operand = ci.use_imm ? {27'd0, ci.zimm} : prf_rdata[0];
  assign csr_old     = csr_is_perf(ci.addr) ? perf_rdata : csr_rdata_raw;
  logic csr_would_write;
  assign csr_would_write = (ci.op == CSR_OP_RW)
                        || ((ci.op == CSR_OP_RS || ci.op == CSR_OP_RC)
                            && (ci.zimm != 5'd0));
  logic csr_addr_known;
  assign csr_addr_known = csr_addr_implemented(ci.addr);
  assign csr_illegal = !csr_addr_known
                    || (csr_would_write && (ci.addr[11:10] == 2'b11));
  assign csr_comp    = csr_active;             // one-cycle ACT

  logic perf_cwe; csr_op_e perf_cop; logic [11:0] perf_caddr; word_t perf_coper;
  word_t mtvec_o, mepc_o, mstatus_o, mie_o, mip_o;
  logic  trap_set_p, mret_p;
  word_t trap_epc_v, trap_cause_v, trap_val_v;

  logic       csr_wr_pend_q;
  logic [11:0] csr_wr_addr_q;
  csr_op_e    csr_wr_op_q;
  word_t      csr_wr_operand_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || stub_flush) begin
      csr_wr_pend_q <= 1'b0;
      csr_wr_addr_q <= '0; csr_wr_op_q <= CSR_OP_NONE; csr_wr_operand_q <= '0;
    end else begin
      csr_wr_pend_q    <= csr_comp && !csr_illegal;
      csr_wr_addr_q    <= ci.addr;
      csr_wr_op_q      <= ci.op;
      csr_wr_operand_q <= csr_operand;
    end
  end
  logic csr_commit_fire;
  assign csr_commit_fire = csr_wr_pend_q && commit_o[0].valid;

  csr_regfile u_csr (
    .clk, .rst_n,
    .hart_id_i,
    .raddr(ci.addr), .rdata(csr_rdata_raw),
    .commit_valid(csr_commit_fire),
    .commit_op(csr_wr_op_q), .commit_addr(csr_wr_addr_q),
    .commit_operand(csr_wr_operand_q),
    .commit_illegal(),                       // computed core-side (loop)
    .trap_set(trap_set_p), .trap_epc(trap_epc_v),
    .trap_cause(trap_cause_v), .trap_val(trap_val_v),
    .mret(mret_p),
    .irq_timer, .irq_soft, .irq_ext,
    .perf_rdata(perf_rdata),
    .perf_commit_we(perf_cwe), .perf_commit_op(perf_cop),
    .perf_commit_addr(perf_caddr), .perf_commit_operand(perf_coper),
    .mtvec_o(mtvec_o), .mepc_o(mepc_o),
    .mstatus_o(mstatus_o), .mie_o(mie_o), .mip_o(mip_o)
  );

  logic [1:0] perf_retire_cnt;
  always_comb begin
    perf_retire_cnt = '0;
    for (int i = 0; i < COMMIT_W; i++)
      perf_retire_cnt = perf_retire_cnt + 2'(commit_o[i].valid);
  end

  perf_counters u_perf (
    .clk, .rst_n,
    .instr_retired(perf_retire_cnt),
    .branch_resolved(is_cf_ex), .branch_mispred(mispredict_ex),
    .stall_cycle(iq_starved), .ic_miss(ev_ic_miss), .dc_miss(ev_dc_miss),
    .dc_writeback(ev_dc_wb),
    .mem_stall_cycle(1'b0), .flush_cycle(recov_redir),
    .raddr(ci.addr), .rdata(perf_rdata), .addr_hit(),
    .commit_we(perf_cwe), .commit_op(perf_cop),
    .commit_addr(perf_caddr), .commit_operand(perf_coper)
  );

  preg_t [2*WIDTH-1:0] prf_raddr;
  logic  [2*WIDTH-1:0][31:0] prf_rdata;
  logic  [WAKEUP_W-1:0]      prf_wen;
  preg_t [WAKEUP_W-1:0]      prf_waddr;
  logic  [WAKEUP_W-1:0][31:0] prf_wdata;
  logic  [WIDTH-1:0]         prf_set_busy;
  preg_t [WIDTH-1:0]         prf_set_preg;

  assign prf_raddr[0] = csr_active ? ci.prs1 : ex_uop.prs1;
  assign prf_raddr[1] = ex_uop.prs2;
  assign iss_ready_1  = iss_ready;
  if (WIDTH > 1) begin : g_port1_raddr
    assign prf_raddr[2] = ex_uop_1.prs1;
    assign prf_raddr[3] = ex_uop_1.prs2;
  end

  prf u_prf (
    .clk, .rst_n,
    .raddr(prf_raddr), .rdata(prf_rdata),
    .wen(prf_wen), .waddr(prf_waddr), .wdata(prf_wdata),
    .set_busy(prf_set_busy), .set_preg(prf_set_preg),
    .busy_raddr(busy_raddr), .busy_rdata(busy_rdata)
  );

  assign prf_set_busy[0] = dispatch_fire && writes_d;
  assign prf_set_preg[0] = fl_alloc_preg[0];
  if (WIDTH > 1) begin : g_slot1_setbusy
    assign prf_set_busy[1] = disp_fire1 && writes_1;
    assign prf_set_preg[1] = slot1_pdst;
  end

  logic div_busy, div_done;
  word_t div_result;
  logic div_running_q;
  logic div_ok;

  // Execute stage register: select and execute are separate cycles. An op
  // holds here while lane 0 is taken by a CSR, divide or SC completion, and a
  // wrong-path op loaded behind a mispredicted branch is dropped unexecuted.
  uop_t ex_uop, ex_uop_1;
  logic ex_valid_q, ex_valid_1_q;
  logic ex_stall, ex_go, ex_go_1, ex_drop, ex_drop_1;
  logic [ROB_W:0] ex_age, ex_age_1;
  assign ex_stall  = csr_active || div_done || lsq_sc_done;
  assign ex_age    = (ROB_W+1)'(ex_uop.rob_id)   - (ROB_W+1)'(bpr_base_q);
  assign ex_age_1  = (ROB_W+1)'(ex_uop_1.rob_id) - (ROB_W+1)'(bpr_base_q);
  assign ex_drop   = (rq_q == R_QUIESCE) && r_is_bpr_q && ex_valid_q   && (ex_age   > bpr_age_q);
  assign ex_drop_1 = (rq_q == R_QUIESCE) && r_is_bpr_q && ex_valid_1_q && (ex_age_1 > bpr_age_q);
  assign ex_go     = ex_valid_q   && !ex_stall && !ex_drop;
  assign ex_go_1   = ex_valid_1_q && !ex_stall && !ex_drop_1;
  assign iss_ready = !ex_stall && recovery_idle;
  assign div_ok    = !div_running_q && !div_done
                  && !(ex_valid_q && ex_uop.ctrl.is_m && ex_uop.ctrl.m_op[2]);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_valid_q <= 1'b0; ex_valid_1_q <= 1'b0;
      ex_uop <= '0; ex_uop_1 <= '0;
    end else if (stub_flush) begin
      ex_valid_q <= 1'b0; ex_valid_1_q <= 1'b0;
    end else begin
      if (!ex_stall) begin
        ex_valid_q   <= iss_valid   && iss_ready;
        ex_uop       <= iss_uop;
        ex_valid_1_q <= iss_valid_1 && iss_ready_1;
        ex_uop_1     <= iss_uop_1;
      end
      if (ex_drop)   ex_valid_q   <= 1'b0;
      if (ex_drop_1) ex_valid_1_q <= 1'b0;
    end
  end

  // A single-cycle ALU op wakes its consumers when it is selected: it writes
  // the register file at the end of the next cycle, before they can read it.
  logic  [WAKEUP_IQ_W-1:0] iq_wake_valid;
  preg_t [WAKEUP_IQ_W-1:0] iq_wake_preg;
  always_comb begin
    for (int w = 0; w < WAKEUP_W; w++) begin
      iq_wake_valid[w] = prf_wen[w];
      iq_wake_preg[w]  = prf_waddr[w];
    end
    iq_wake_valid[WAKEUP_W] = iss_valid && iss_ready && iss_uop.ctrl.rf_we
                            && !iss_uop.ctrl.is_m && !iss_uop.ctrl.mem_re
                            && !iss_uop.ctrl.is_sc && (iss_uop.pdst != '0);
    iq_wake_preg[WAKEUP_W]  = iss_uop.pdst;
    if (WIDTH > 1) begin
      iq_wake_valid[WAKEUP_W+1] = iss_valid_1 && iss_ready_1 && iss_uop_1.ctrl.rf_we
                                && (iss_uop_1.pdst != '0);
      iq_wake_preg[WAKEUP_W+1]  = iss_uop_1.pdst;
    end
  end

  word_t op_a, op_b, rs1_v, rs2_v;
  assign rs1_v = prf_rdata[0];
  assign rs2_v = prf_rdata[1];
  always_comb begin
    unique case (ex_uop.ctrl.op_a_sel)
      OP_A_RS1:  op_a = rs1_v;
      OP_A_PC:   op_a = ex_uop.pc;
      default:   op_a = '0;                      // OP_A_ZERO (lui)
    endcase
    op_b = (ex_uop.ctrl.op_b_sel == OP_B_IMM) ? ex_uop.imm : rs2_v;
  end

  word_t alu_result;
  logic  alu_comp;
  alu u_alu (.op(ex_uop.ctrl.alu_op), .a(op_a), .b(op_b),
             .result(alu_result), .comp_result(alu_comp));

  word_t alu2_result;
  if (WIDTH > 1) begin : g_port1_alu
    word_t op_a_1, op_b_1, rs1_v_1, rs2_v_1;
    logic  alu2_comp;
    assign rs1_v_1 = prf_rdata[2];
    assign rs2_v_1 = prf_rdata[3];
    always_comb begin
      unique case (ex_uop_1.ctrl.op_a_sel)
        OP_A_RS1:  op_a_1 = rs1_v_1;
        OP_A_PC:   op_a_1 = ex_uop_1.pc;
        default:   op_a_1 = '0;
      endcase
      op_b_1 = (ex_uop_1.ctrl.op_b_sel == OP_B_IMM) ? ex_uop_1.imm : rs2_v_1;
    end
    alu u_alu2 (.op(ex_uop_1.ctrl.alu_op), .a(op_a_1), .b(op_b_1),
                .result(alu2_result), .comp_result(alu2_comp));
`ifndef RVFI_NO_SIDEBAND
    always_ff @(posedge clk) if (ex_go_1) begin
      rvfi_side[ex_uop_1.rob_id].rs1_v <= rs1_v_1;
      rvfi_side[ex_uop_1.rob_id].rs2_v <= rs2_v_1;
    end
`endif
  end else begin : g_port1_alu_off
    assign alu2_result = '0;
  end

  logic  br_taken;
  word_t br_target;
  branch_unit u_bru (
    .cf_type(ex_uop.ctrl.cf_type), .comp_result(alu_comp),
    .pc(ex_uop.pc), .rs1_data(rs1_v), .imm(ex_uop.imm),
    .pred('0),
    .taken(br_taken), .target(br_target),
    .target_misaligned(br_tmis), .mispredict()
  );

  logic  is_cf_ex;
  assign is_cf_ex = ex_go && (ex_uop.ctrl.cf_type != CF_NONE);
  logic  mispredict_ex;
  assign mispredict_ex = is_cf_ex && !br_tmis &&
      ((br_taken != ex_uop.pred.taken) ||
       (br_taken && ex_uop.pred.taken && (br_target != ex_uop.pred.target)));
  word_t correct_next_pc;
  assign correct_next_pc = br_taken ? br_target : (ex_uop.pc + 32'd4);

  assign bp_update = '{
    valid:      is_cf_ex || bogus_pred_ex,
    pc:         ex_uop.pc,
    cf_type:    ex_uop.ctrl.cf_type,
    call:       bp_is_call(ex_uop.ctrl.cf_type, ex_uop.lrd),
    ret:        bp_is_ret (ex_uop.ctrl.cf_type, ex_uop.lrd, ex_uop.lrs1),
    taken:      br_taken,
    target:     br_target,
    mispredict: mispredict_ex || bogus_pred_ex,
    pred:       ex_uop.pred
  };

  assign redirect_valid    = recov_redir;
  assign redirect_target   = recov_target;
  assign redirect_consumed = recov_redir;

  logic start_div, div_flush, div_take;
  assign start_div = ex_go && ex_uop.ctrl.is_m && ex_uop.ctrl.m_op[2];
  assign div_take  = div_done && !lsq_sc_done && !csr_comp;   // lane 0 prefers SC and CSR completions
  logic [ROB_W:0] div_age;
  assign div_age = (ROB_W+1)'(div_id_q) - (ROB_W+1)'(rob_head_id);
  // A divide younger than a mispredicted branch is dead: abort it now instead
  // of holding the recovery quiesce for up to 34 cycles.
  assign div_flush = mispredict_ex && (div_running_q || div_done) && (div_age > mis_age);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                       div_running_q <= 1'b0;
    else if (start_div)               div_running_q <= 1'b1;
    else if (div_take || div_flush)   div_running_q <= 1'b0;
  end
  div_unit u_div (
    .clk, .rst_n,
    .start(start_div), .m_op(ex_uop.ctrl.m_op),
    .a(rs1_v), .b(rs2_v),
    .advance(div_take),                          // held until lane 0 takes it
    .flush(div_flush),
    .busy(div_busy), .done(div_done), .result(div_result)
  );
  rob_ptr_t div_id_q;  preg_t div_pdst_q;
  always_ff @(posedge clk) begin
    if (rst_n && start_div) begin
      div_id_q   <= ex_uop.rob_id;
      div_pdst_q <= ex_uop.pdst;
    end
  end

  logic mul_in_ex;
  assign mul_in_ex = ex_go && ex_uop.ctrl.is_m && !ex_uop.ctrl.m_op[2];
  word_t mul_result_w;
  mul_unit u_mul (
    .clk, .rst_n,
    .a(rs1_v), .b(rs2_v), .m_op(ex_uop.ctrl.m_op),
    .en_m(1'b1), .flush_m(1'b0), .en_w(1'b1), .flush_w(1'b0),
    .result_w(mul_result_w)
  );
  logic     mulv_m_q, mulv_w_q;
  rob_ptr_t mulid_m_q, mulid_w_q;
  preg_t    mulp_m_q, mulp_w_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mulv_m_q <= 1'b0; mulv_w_q <= 1'b0;
      mulid_m_q <= '0; mulid_w_q <= '0; mulp_m_q <= '0; mulp_w_q <= '0;
    end else begin
      mulv_m_q  <= mul_in_ex;
      mulid_m_q <= ex_uop.rob_id;
      mulp_m_q  <= ex_uop.pdst;
      mulv_w_q  <= mulv_m_q;
      mulid_w_q <= mulid_m_q;
      mulp_w_q  <= mulp_m_q;
    end
  end

  logic alu_comp_fire;
  assign alu_comp_fire = ex_go && !ex_uop.ctrl.is_m
                      && (!is_load_ex || mem_mis_ex)
                      && (!ex_uop.ctrl.is_sc || mem_mis_ex);

  word_t ex_wb_value;
  assign ex_wb_value = (ex_uop.ctrl.wb_sel == WB_PC4) ? (ex_uop.pc + 32'd4)
                                                       : alu_result;

  always_comb begin
    comp_valid[0] = 1'b0; comp_id[0] = '0; comp_wdata[0] = '0;
    prf_wen[0] = 1'b0;    prf_waddr[0] = '0; prf_wdata[0] = '0;
    comp_exc0     = 1'b0; comp_cause0 = '0; comp_tval0 = '0;
    if (lsq_sc_done) begin
      comp_valid[0] = 1'b1;
      comp_id[0]    = lsq_sc_rob_id;
      comp_wdata[0] = lsq_sc_val;
      prf_wen[0]    = (lsq_sc_pdst != '0);
      prf_waddr[0]  = lsq_sc_pdst;
      prf_wdata[0]  = lsq_sc_val;
    end else if (csr_comp) begin
      comp_valid[0] = 1'b1;
      comp_id[0]    = rob_head_id;
      comp_wdata[0] = csr_old;
      comp_exc0     = csr_illegal;
      comp_cause0   = 4'd2;              // illegal instruction, tval = 0
      prf_wen[0]    = !csr_illegal && (ci.pdst != '0);
      prf_waddr[0]  = ci.pdst;
      prf_wdata[0]  = csr_old;
    end else if (div_done) begin
      comp_valid[0] = 1'b1;
      comp_id[0]    = div_id_q;
      comp_wdata[0] = div_result;
      prf_wen[0]    = (div_pdst_q != '0);
      prf_waddr[0]  = div_pdst_q;
      prf_wdata[0]  = div_result;
    end else if (alu_comp_fire) begin
      comp_valid[0] = 1'b1;
      comp_id[0]    = ex_uop.rob_id;
      comp_wdata[0] = ex_wb_value;
      comp_exc0     = (is_cf_ex && br_taken && br_tmis)
                   || (mem_ex && mem_mis_ex);
      comp_cause0   = (mem_ex && mem_mis_ex)
                        ? (is_store_ex ? 4'd6 : 4'd4) : 4'd0;
      comp_tval0    = (mem_ex && mem_mis_ex)            ? alu_result
                    : (is_cf_ex && br_taken && br_tmis) ? br_target : 32'd0;
      prf_wen[0]    = (ex_uop.pdst != '0);
      prf_waddr[0]  = ex_uop.pdst;
      prf_wdata[0]  = ex_wb_value;
    end
  end
  assign lsq_ld_comp_ready = !mulv_w_q;
  always_comb begin
    comp_exc_v[1] = 1'b0; comp_cause_v[1] = '0; comp_tval_v[1] = '0;
    if (mulv_w_q) begin
      comp_valid[1] = 1'b1;
      comp_id[1]    = mulid_w_q;
      comp_wdata[1] = mul_result_w;
      prf_wen[1]    = (mulp_w_q != '0);
      prf_waddr[1]  = mulp_w_q;
      prf_wdata[1]  = mul_result_w;
    end else begin
      comp_valid[1] = lsq_ld_comp_valid;
      comp_id[1]    = lsq_ld_comp_rob_id;
      comp_wdata[1] = lsq_ld_comp_data;
      comp_exc_v[1]   = lsq_ld_comp_valid && lsq_ld_comp_err;
      comp_cause_v[1] = 4'd5;
      comp_tval_v[1]  = lsq_ld_comp_addr;
      prf_wen[1]    = lsq_ld_comp_valid && !lsq_ld_comp_err && (lsq_ld_comp_pdst != '0);
      prf_waddr[1]  = lsq_ld_comp_pdst;
      prf_wdata[1]  = lsq_ld_comp_data;
    end
  end

  if (WIDTH > 1) begin : g_lane2
    always_comb begin
      comp_valid[2] = ex_go_1;
      comp_id[2]    = ex_uop_1.rob_id;
      comp_wdata[2] = alu2_result;
      prf_wen[2]    = ex_go_1 && (ex_uop_1.pdst != '0);
      prf_waddr[2]  = ex_uop_1.pdst;
      prf_wdata[2]  = alu2_result;
    end
  end
  typedef enum logic [2:0] { R_IDLE, R_QUIESCE, R_ACT, R_FLUSH, R_WALK,
                             R_REDIR } rec_e;
  rec_e rq_q, rq_d;

  logic irq_pend;
  logic [4:0] irq_code;
  always_comb begin
    if      (mip_o[11] && mie_o[11]) begin irq_pend = mstatus_o[3]; irq_code = 5'd11; end
    else if (mip_o[3]  && mie_o[3])  begin irq_pend = mstatus_o[3]; irq_code = 5'd3;  end
    else if (mip_o[7]  && mie_o[7])  begin irq_pend = mstatus_o[3]; irq_code = 5'd7;  end
    else                             begin irq_pend = 1'b0;         irq_code = 5'd0;  end
  end

  logic trig_irq, trig_exc, trig_actor, trig_viol;
  assign trig_viol = rob_head_valid && rob_head_done && rob_head_viol;
  assign trig_irq   = irq_pend && rob_head_valid && !sc_is[rob_head_id];   // an SC stores before it retires: its actor path commits it first
  assign trig_exc   = exc_at_head;
  assign trig_actor = rob_head_valid && rob_head_done
                   && (rob_head_is_fence || rob_head_is_fence_i
                       || rob_head_is_mret || sc_is[rob_head_id]
                       || refetch_is[rob_head_id]);
  typedef logic [SNAP_W:0] snp_t;
  snp_t  snap_head_q, snap_tail_q;
  logic  snap_res_q [SNAP_N];
  logic [ROB_W:0] snapb_rob_q [SNAP_N];
  logic [LQ_W:0]  snapb_lq_q  [SNAP_N];
  logic [SQ_W:0]  snapb_sq_q  [SNAP_N];
  logic [SNAP_W:0] snap_cnt;
  logic [WIDTH-1:0] snap_can_alloc;
  assign snap_cnt = snap_tail_q - snap_head_q;
  always_comb
    for (int i = 0; i < WIDTH; i++)
      snap_can_alloc[i] =
        ((SNAP_W+1)'(SNAP_N) - snap_cnt) > (SNAP_W+1)'(i);
  logic [ROB_W:0] rob_tail_o;
  logic [LQ_W:0]  lsq_lq_tail;
  logic [SQ_W:0]  lsq_sq_tail;
  bp_snapshot_t   rob_head_bsnap;
  logic           bpr_pend_q;
  snap_ptr_t      bpr_snap_q;
  logic           r_is_viol_q;
  word_t          viol_pc_q;
  logic           lsq_viol_valid;
  rob_ptr_t       lsq_viol_rob_id;
  logic           lsq_snoop_hit;
  rob_ptr_t       lsq_snoop_rob_id;
  logic           viol_any;
  rob_ptr_t       viol_any_id;
  logic           viol_pend_q;
  rob_ptr_t       viol_pend_id_q;
  logic           rob_head_viol;
  word_t          rob_head_pc;
  bp_snapshot_t   r_bsnap_q;   // trap-point repair snapshot, latched at
  rob_ptr_t        bpr_id_q;
  rob_ptr_t        bpr_base_q;   // the head AT LATCH: ages for the walk
  logic [ROB_W:0]  bpr_age_q;
  word_t           bpr_npc_q;
  logic [ROB_W:0]  mis_age;
  assign mis_age = (ROB_W+1)'(ex_uop.rob_id) - (ROB_W+1)'(rob_head_id);

  logic quiet;
  assign quiet = !mulv_m_q && !mulv_w_q && !div_busy && !div_done
              && !ex_valid_q && !ex_valid_1_q
              && lsq_quiet;

  logic  r_is_irq_q, r_is_exc_q, r_is_mret_q, r_is_fence_q, r_is_fencei_q;
  logic  r_is_bpr_q;
  word_t r_epc_q, r_cause_q, r_tval_q, r_pc4_q;
  logic  recov_redir;
  word_t recov_target;
  logic  stub_flush, iq_squash;
  rob_ptr_t rob_walk_id;

  always_comb begin
    rq_d = rq_q;
    case (rq_q)
      R_IDLE:    if (trig_irq || trig_exc || trig_actor
                     || mispredict_ex || trig_viol) rq_d = R_QUIESCE;
      R_QUIESCE: if (quiet)   rq_d = r_is_bpr_q ? R_REDIR :
                                     (r_is_irq_q || r_is_exc_q
                                      || r_is_viol_q)
  // R_WALK pops the ROB youngest-first, undoing each rename and refunding its pdst.
                                       ? R_WALK : R_ACT;
      R_ACT:                  rq_d = (r_is_fence_q || r_is_fencei_q)
                                       ? R_FLUSH : R_WALK;
      R_FLUSH:   if (dc_flush_done) rq_d = R_WALK;
      R_WALK:    if (!walk_valid) rq_d = R_REDIR;
      R_REDIR:                rq_d = R_IDLE;
      default:                rq_d = R_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rq_q <= R_IDLE;
      r_is_irq_q <= 0; r_is_exc_q <= 0; r_is_mret_q <= 0;
      r_is_fence_q <= 0; r_is_fencei_q <= 0; r_is_bpr_q <= 0;
      bpr_pend_q <= 0; bpr_id_q <= '0; bpr_age_q <= '0; bpr_npc_q <= '0;
      bpr_base_q <= '0; bpr_snap_q <= '0; r_bsnap_q <= '0;
      r_is_viol_q <= 0; viol_pc_q <= '0;
      snap_head_q <= '0; snap_tail_q <= '0;
      for (int i = 0; i < SNAP_N; i++) begin
        snap_res_q[i] <= 1'b0; snapb_rob_q[i] <= '0;
        snapb_lq_q[i] <= '0;   snapb_sq_q[i] <= '0;
      end
      r_epc_q <= '0; r_cause_q <= '0; r_tval_q <= '0; r_pc4_q <= '0;
    end else begin
      rq_q <= rq_d;
      if (mispredict_ex &&
          ((rq_q == R_IDLE && !(trig_irq || trig_exc || trig_actor)) ||
           (rq_q == R_QUIESCE && r_is_bpr_q && mis_age < bpr_age_q))) begin
        bpr_pend_q <= 1'b1;
        bpr_id_q   <= ex_uop.rob_id;
        bpr_snap_q <= ex_uop.snap_id;
        bpr_base_q <= rob_head_id;
        bpr_age_q  <= mis_age;
        bpr_npc_q  <= correct_next_pc;
      end
      if (rq_q == R_REDIR) bpr_pend_q <= 1'b0;
      if (dispatch_fire && is_cf_d) begin
        snap_res_q[SNAP_W'(snap_tail_q)]  <= 1'b0;
        snapb_rob_q[SNAP_W'(snap_tail_q)] <= rob_tail_o + (ROB_W+1)'(1);
        snapb_lq_q[SNAP_W'(snap_tail_q)]  <= lsq_lq_tail;
        snapb_sq_q[SNAP_W'(snap_tail_q)]  <= lsq_sq_tail;
        snap_tail_q <= snap_tail_q + snp_t'(1);
      end
      if (is_cf_ex && !mispredict_ex)
        snap_res_q[ex_uop.snap_id] <= 1'b1;
      if ((snap_cnt != '0) && snap_res_q[SNAP_W'(snap_head_q)]
          && !(dispatch_fire && is_cf_d && snap_cnt == (SNAP_W+1)'(1)))
        snap_head_q <= snap_head_q + snp_t'(1);
      if (snap_restore_fire) begin
        for (int p = 0; p < SNAP_N; p++) begin
          automatic snp_t pp = snap_head_q + snp_t'(p);
          if ((snp_t'(p) < snap_cnt) && SNAP_W'(pp) == bpr_snap_q)
            snap_tail_q <= pp;
        end
      end
      if ((rq_q == R_REDIR) && !r_is_bpr_q) begin
        snap_head_q <= '0;
        snap_tail_q <= '0;
      end
      if (rq_q == R_IDLE && rq_d == R_QUIESCE) begin
        r_bsnap_q   <= rob_head_bsnap;   // trap-point repair reference
        r_is_bpr_q  <= !(trig_irq || trig_exc || trig_actor || trig_viol);
        r_is_viol_q <= !(trig_irq || trig_exc || trig_actor) && trig_viol;
        viol_pc_q   <= rob_head_pc;      // refetch the load itself
        r_is_irq_q  <= trig_irq;
        r_is_exc_q  <= !trig_irq && trig_exc;
        r_is_mret_q   <= !trig_irq && !trig_exc && rob_head_is_mret;
        r_is_fence_q  <= !trig_irq && !trig_exc && rob_head_is_fence;
        r_is_fencei_q <= !trig_irq && !trig_exc && rob_head_is_fence_i;
        r_epc_q   <= trig_irq ? commit_o[0].pc  : exc_pc;
        r_cause_q <= trig_irq ? {1'b1, 26'd0, irq_code}
                              : {1'b0, 27'd0, exc_cause};
        r_tval_q  <= trig_irq ? 32'd0 : exc_tval;
        r_pc4_q   <= commit_o[0].pc + 32'd4;   // valid for the actor path:
      end
    end
  end

  always_comb
    for (int i = 0; i < COMMIT_W; i++)
      rvfi_commit_id[i] = ROB_W'(rob_head_id + rob_ptr_t'(i));
  assign rvfi_mtvec = mtvec_o;
  assign rvfi_mepc  = mepc_o;

`ifndef RVFI_NO_SIDEBAND
  always_comb begin
    for (int i = 0; i < RENAME_W; i++) rvfi_alloc_id[i] = ROB_W'(rob_alloc_id[i]);
    rvfi_alloc_fire[0] = dispatch_fire;
    rvfi_alloc_fire[1] = disp_fire1;
  end
`endif

`ifndef RVFI_NO_SIDEBAND
  always_ff @(posedge clk) begin
    for (int i = 0; i < RENAME_W; i++)
      if (rvfi_alloc_fire[i]) rvfi_side[rvfi_alloc_id[i]] <= '0;
    if (ex_go) begin
      rvfi_side[ex_uop.rob_id].rs1_v <= rs1_v;
      rvfi_side[ex_uop.rob_id].rs2_v <= rs2_v;
      rvfi_side[ex_uop.rob_id].npc   <= correct_next_pc;
    end
    if (csr_comp) rvfi_side[rob_head_id].rs1_v <= prf_rdata[0];   // CSR ops execute at the head, not in EX
    if (lsq_m_ld_valid) begin
      rvfi_side[lsq_m_ld_id].m_addr  <= lsq_m_ld_addr;
      rvfi_side[lsq_m_ld_id].m_rdata <= lsq_m_ld_rdata;
      rvfi_side[lsq_m_ld_id].m_rmask <= lsq_m_ld_rmask;
    end
    if (lsq_m_st_valid) begin
      rvfi_side[lsq_m_st_id].m_addr  <= lsq_m_st_addr;
      rvfi_side[lsq_m_st_id].m_wdata <= lsq_m_st_wdata;
      rvfi_side[lsq_m_st_id].m_wmask <= lsq_m_st_wmask;
    end
    if (lsq_sc_done && (lsq_sc_val != 32'd0))
      rvfi_side[lsq_sc_rob_id].m_wmask <= '0;
  end
`endif

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvfi_prev_pc_wdata <= '0;
      rvfi_prev_valid    <= 1'b0;
    end else if (|rvfi_valid) begin
      rvfi_prev_pc_wdata <= rvfi_valid[COMMIT_W-1] ? rvfi_pc_wdata[COMMIT_W-1]
                                                   : rvfi_pc_wdata[0];
      rvfi_prev_valid    <= 1'b1;
    end
  end

  assign rvfi_exc_emit = (rq_q == R_IDLE) && trig_exc && !trig_irq;
  assign trap_taken    = trap_set_p;

  assign recovery_idle = (rq_q == R_IDLE)
                      && !(trig_irq || trig_exc || trig_actor);
  assign commit_ready  = (recovery_idle || (rq_q == R_ACT))
                       && !(rob_head_valid && rob_head_viol);

  logic walk_pop, walk_valid;
  rob_entry_t walk_entry;
  assign walk_pop = (rq_q == R_WALK) && walk_valid;

  assign stub_flush   = (rq_q == R_REDIR) && !r_is_bpr_q;
  assign iq_squash    = (rq_q == R_REDIR) && r_is_bpr_q;
  logic snap_restore_fire;
  assign snap_restore_fire = (rq_q == R_REDIR) && r_is_bpr_q;
  assign ic_flush = (rq_q == R_FLUSH) && r_is_fencei_q;
  assign dc_flush = (rq_q == R_FLUSH) && (r_is_fence_q || r_is_fencei_q);
  assign walk_undo_ldst_sel = (rq_q == R_WALK);
  assign walk_ldst          = walk_entry.lrd;
  assign recov_redir  = (rq_q == R_REDIR);
  assign recov_target = r_is_viol_q ? viol_pc_q :
                        r_is_bpr_q  ? bpr_npc_q :
                        r_is_irq_q  ? mtvec_o :
                        r_is_exc_q  ? mtvec_o :
                        r_is_mret_q ? mepc_o  : r_pc4_q;

  assign trap_set_p   = (rq_q == R_REDIR) && (r_is_irq_q || r_is_exc_q);
  assign trap_epc_v   = r_epc_q;
  assign trap_cause_v = r_cause_q;
  assign trap_val_v   = r_tval_q;
  assign mret_p       = (rq_q == R_ACT) && r_is_mret_q;

  assign iq_starved = iss_valid && !iss_ready;
  assign fl_free_fire[0] = rob_free_valid[0] || walk_undo;
  assign fl_free_preg[0] = walk_undo ? walk_entry.pdst : rob_free_preg[0];
  if (WIDTH > 1) begin : g_fl_free_slot_hi
    for (genvar gi = 1; gi < WIDTH; gi++) begin : g_free_lane
      assign fl_free_fire[gi] = rob_free_valid[gi];
      assign fl_free_preg[gi] = rob_free_preg[gi];
    end
  end


  always_comb begin
    if (viol_pend_q) begin
      viol_any    = 1'b1;
      viol_any_id = viol_pend_id_q;
    end else if (lsq_viol_valid) begin
      viol_any    = 1'b1;
      viol_any_id = lsq_viol_rob_id;
    end else if (lsq_snoop_hit) begin
      viol_any    = 1'b1;
      viol_any_id = lsq_snoop_rob_id;
    end else begin
      viol_any    = 1'b0;
      viol_any_id = '0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      viol_pend_q    <= 1'b0;
      viol_pend_id_q <= '0;
    end else begin
      if (viol_pend_q) begin
        viol_pend_q <= 1'b0;                  // issued this cycle
      end else if (lsq_viol_valid && lsq_snoop_hit) begin
        viol_pend_q    <= 1'b1;
        viol_pend_id_q <= lsq_snoop_rob_id;
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (viol_pend_q && lsq_viol_valid && lsq_snoop_hit)
      $fatal(1, "core: violation collision while one is already pending -- a squash would be lost");
  end
`endif

endmodule
