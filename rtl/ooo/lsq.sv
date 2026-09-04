// Load/store queue: disambiguation, store-to-load forwarding, violation recovery.
module lsq
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
#(
  parameter int unsigned LINE_OFF_W = 4   // cache line offset bits: a snoop names a whole line
) (
  input  logic  clk,
  input  logic  rst_n,

  input  logic      alloc_load,
  input  logic      alloc_store,
  input  rob_ptr_t  alloc_rob_id,
  input  logic      alloc_is_lr,
  input  logic      alloc_is_sc,
  input  preg_t     alloc_pdst,      // SC only: destination for the verdict
  output logic      lq_can_alloc,
  output logic      sq_can_alloc,

  input  logic      fill_valid,
  input  logic      fill_is_store,
  input  rob_ptr_t  fill_rob_id,
  input  word_t     fill_addr,
  input  mem_size_e fill_size,
  input  word_t     fill_wdata,      // stores: raw rs2 value
  input  preg_t     fill_pdst,       // loads

  output logic      ld_comp_valid,
  input  logic      ld_comp_ready,
  output rob_ptr_t  ld_comp_rob_id,

  output logic      rvfi_m_ld_valid,
  output rob_ptr_t  rvfi_m_ld_id,
  output word_t     rvfi_m_ld_addr,
  output word_t     rvfi_m_ld_rdata,   // RAW, pre-extension: the spec wants
  output logic[3:0] rvfi_m_ld_rmask,   //   "pre-state data read from memory"
  output logic      rvfi_m_st_valid,
  output rob_ptr_t  rvfi_m_st_id,
  output word_t     rvfi_m_st_addr,
  output word_t     rvfi_m_st_wdata,
  output logic[3:0] rvfi_m_st_wmask,
  output preg_t     ld_comp_pdst,
  output word_t     ld_comp_data,
  output logic      ld_comp_err,      // load access fault
  output word_t     ld_comp_addr,

  input  logic      store_release,   // ROB: head-most uncommitted -> committed
  input  logic      sc_head_go,
  output logic      sc_done_pulse,
  output rob_ptr_t  sc_done_rob_id,
  output preg_t     sc_done_pdst,
  output word_t     sc_done_val,
  input  logic      load_release,    // a load RETIRED: pop the LQ head.
  input  logic      lq_walk_pop,     // recovery walked a load
  input  logic      sq_walk_pop,     // recovery walked a store

  output logic  dreq,
  input  logic  dgnt,
  output word_t daddr,
  output logic  dwe,
  output logic  dis_lr,
  output logic [3:0] dwstrb,
  output word_t dwdata,
  input  logic  drvalid,
  input  word_t drdata,
  input  logic  drerr = 1'b0,

  input  logic  recovering,       // rq_q != R_IDLE: no new ld/st memory access
  input  logic  lr_go_ok = 1'b1,   // the picked LR is the ROB head; unit tests leave it high
  output rob_ptr_t pick_rob_id_o,    // rob id of the picked load, for that check
  output logic  quiet,            // no in-flight access, no committed-undrained

  output logic [LQ_W:0] lq_tail_o,
  output logic [SQ_W:0] sq_tail_o,
  input  logic          restore_valid,
  input  logic [LQ_W:0] lq_restore_tail,
  input  logic [SQ_W:0] sq_restore_tail,

  output logic      viol_valid,
  output rob_ptr_t  viol_rob_id,

  output logic      lrsc_lr_valid,
  output logic      lrsc_sc_valid,
  output word_t     lrsc_addr,
  output logic      lrsc_acc_valid,   // any qualifying data access (clear rule)
  input  logic      lrsc_sc_success,  // lrsc_unit's verdict for the SC in flight

  input  logic      snoop_valid,      // a snoop is being searched this cycle
  input  word_t     snoop_addr,       // its line address
  output logic      snoop_hit,        // a resident load overlaps it
  output rob_ptr_t  snoop_hit_rob_id  // ...the OLDEST such load
);

  typedef struct packed {
    logic      addr_known;
    logic      committed;
    word_t     addr;
    word_t     data;             // raw rs2 value
    mem_size_e size;
    rob_ptr_t  rob_id;
    logic      is_sc;            // this store is an SC
    preg_t     pdst;             // SC only: where the verdict goes
    logic      sc_done;          // SC has acted; awaiting its commit
  } sq_e;
  typedef logic [SQ_W:0] sqp_t;
  sq_e  sq [SQ_N];
  sqp_t sq_head_q, sq_tail_q;
  logic [SQ_W:0] sq_cnt;
  assign sq_cnt       = sq_tail_q - sq_head_q;
  assign sq_can_alloc = (sq_cnt < (SQ_W+1)'(SQ_N));

  logic [SQ_W:0] sq_committed_n;
  always_comb begin
    sq_committed_n = '0;
    for (int i = 0; i < SQ_N; i++) begin
      automatic sqp_t p = sq_head_q + sqp_t'(i);
      if ((sqp_t'(i) < sq_cnt) && sq[SQ_W'(p)].committed)
        sq_committed_n = sq_committed_n + 1;
    end
  end

  typedef struct packed {
    logic      filled;
    logic      executed;         // completed (or handed to the comp skid)
    word_t     addr;
    mem_size_e size;
    preg_t     pdst;
    rob_ptr_t  rob_id;
    sqp_t      sq_horizon;       // SQ tail at this load's dispatch: stores
    logic      fwd_valid;        // provenance: this load's value
    sqp_t      fwd_sq;           //   came from SQ ring id fwd_sq (BOOM's
    logic      is_lr;            // this load is an LR
  } lq_e;
  typedef logic [LQ_W:0] lqp_t;
  lq_e  lq [LQ_N];
  lqp_t lq_head_q, lq_tail_q;
  logic [LQ_W:0] lq_cnt;
  assign lq_cnt       = lq_tail_q - lq_head_q;
  assign lq_can_alloc = (lq_cnt < (LQ_W+1)'(LQ_N));

  // Loads execute out of order: the oldest load that has its address and has
  // not run is picked, so a younger load never waits on an older one's operands.
  lqp_t lq_pick;
  logic lq_pick_v;
  always_comb begin
    lq_pick_v = 1'b0;
    lq_pick   = lq_head_q;
    for (int i = 0; i < LQ_N; i++) begin
      automatic lqp_t p = lq_head_q + lqp_t'(i);
      if (!lq_pick_v && (lqp_t'(i) < lq_cnt) && lq[LQ_W'(p)].filled && !lq[LQ_W'(p)].executed) begin
        lq_pick_v = 1'b1;
        lq_pick   = p;
      end
    end
  end

  lqp_t lq_inf_q;                 // the load the memory FSM is serving
  lqp_t hl_idx;
  lq_e  hl;                       // the resolver's view
  logic hl_valid;
  assign hl_idx   = (lm_q != M_IDLE) ? lq_inf_q : lq_pick;
  assign hl       = lq[LQ_W'(hl_idx)];
  assign hl_valid = (lm_q != M_IDLE) ? 1'b1 : lq_pick_v;

  logic  older_all_known, fwd_hit, conflict;
  word_t fwd_raw;
  sqp_t  fwd_src;                 // ring id of the forwarding store
  mem_size_e fwd_size_dbg;
  always_comb begin
    older_all_known = 1'b1;
    fwd_src  = '0;
    fwd_hit  = 1'b0;
    conflict = 1'b0;
    fwd_raw  = '0;
    fwd_size_dbg = MEM_W;
    for (int k = SQ_N; k >= 1; k--) begin
      automatic sqp_t id = hl.sq_horizon - sqp_t'(k);
      automatic logic in_range = (sqp_t'(id - sq_head_q) < sq_cnt);
      automatic sq_e s = sq[SQ_W'(id)];
      if (in_range) begin
        if (!s.addr_known) older_all_known = 1'b0;
        else if (s.addr[31:2] == hl.addr[31:2]) begin
          if (s.addr == hl.addr && width_of(s.size) == width_of(hl.size)) begin
            fwd_hit  = 1'b1;
            conflict = 1'b0;
            fwd_raw  = s.data;
            fwd_src  = id;
            fwd_size_dbg = s.size;
          end else begin
            conflict = 1'b1;
            fwd_hit  = 1'b0;
          end
        end
      end
    end
  end

  function automatic logic [3:0] bmask(mem_size_e sz, logic [1:0] lo);
    unique case (sz)
      MEM_B, MEM_BU: bmask = 4'b0001 << lo;
      MEM_H, MEM_HU: bmask = 4'b0011 << lo;
      default:       bmask = 4'b1111;
    endcase
  endfunction

  logic exec_now_fire;
  assign exec_now_fire = fwd_fire;

  always_comb begin
    automatic sqp_t fid;
    automatic logic fid_found;
    viol_valid  = 1'b0;
    viol_rob_id = '0;
    fid         = '0;
    fid_found   = 1'b0;
    begin
      for (int i = 0; i < SQ_N; i++) begin
        automatic sqp_t p;
        p = sq_head_q + sqp_t'(i);
        if (fill_valid && fill_is_store
            && (sqp_t'(i) < sq_cnt) && sq[SQ_W'(p)].rob_id == fill_rob_id
            && !sq[SQ_W'(p)].addr_known && !fid_found) begin
          fid = p; fid_found = 1'b1;
        end
      end
      for (int i = LQ_N - 1; i >= 0; i--) begin     // downward: index 0
        automatic lqp_t p;                          //   (oldest) wins
        automatic lq_e  le;
        automatic sqp_t d_fill;
        automatic logic st_older, done_or_now, overlap, safe;
        p        = lq_head_q + lqp_t'(i);
        le       = lq[LQ_W'(p)];
        d_fill   = le.sq_horizon - fid;
        st_older = (sqp_t'(d_fill - sqp_t'(1)) < sqp_t'(SQ_N));
        done_or_now = le.executed
            || ((exec_now_fire || ld_go) && (p == lq_pick))
            || ((lm_q != M_IDLE) && (p == lq_inf_q));
        overlap  = (le.addr[31:2] == fill_addr[31:2])
            && ((bmask(le.size, le.addr[1:0])
                 & bmask(fill_size, fill_addr[1:0])) != 4'b0000);
        safe     = le.fwd_valid
            && (sqp_t'(le.sq_horizon - le.fwd_sq) < d_fill);
        if (fid_found && (lqp_t'(i) < lq_cnt) && done_or_now && st_older
            && overlap && !safe) begin
          viol_valid  = 1'b1;
          viol_rob_id = le.rob_id;
        end
      end
    end
  end

  // A load is stale only if it bound its value before the snoop while an OLDER load has not
  // bound its value yet: that older load will read the line after the remote store and the
  // two would disagree. The oldest in-flight load can never be stale, and a load still
  // waiting on the cache is not stale either, since it reads the line after the snoop is
  // served. Flagging either only costs squashes, and flagging the head load livelocks a
  // hart whose peer keeps a store waiting at the ordering point.
  always_comb begin
    automatic logic older_unbound = 1'b0;
    snoop_hit        = 1'b0;
    snoop_hit_rob_id = '0;
    for (int i = 0; i < LQ_N; i++) begin                // oldest first
      automatic lqp_t p;
      automatic lq_e  le;
      automatic logic in_range, bound, overlap;
      p        = lq_head_q + lqp_t'(i);
      le       = lq[LQ_W'(p)];
      in_range = (lqp_t'(i) < lq_cnt);
      bound    = le.executed
          || (exec_now_fire && (p == lq_pick))
          || ((lm_q == M_LRESP) && drvalid && (p == lq_inf_q));
      overlap  = (le.addr[31:LINE_OFF_W] == snoop_addr[31:LINE_OFF_W]);   // any word of the line
      if (snoop_valid && in_range && bound && overlap && older_unbound && !snoop_hit) begin
        snoop_hit        = 1'b1;
        snoop_hit_rob_id = le.rob_id;
      end
      if (in_range && !bound) older_unbound = 1'b1;
    end
  end


  function automatic logic [1:0] width_of(mem_size_e sz);
    unique case (sz)
      MEM_B, MEM_BU: width_of = 2'd0;
      MEM_H, MEM_HU: width_of = 2'd1;
      default:       width_of = 2'd2;
    endcase
  endfunction

  function automatic word_t extend_fwd(word_t raw, mem_size_e ld_sz);
    unique case (ld_sz)
      MEM_B:   extend_fwd = {{24{raw[7]}},  raw[7:0]};
      MEM_BU:  extend_fwd = {24'd0, raw[7:0]};
      MEM_H:   extend_fwd = {{16{raw[15]}}, raw[15:0]};
      MEM_HU:  extend_fwd = {16'd0, raw[15:0]};
      default: extend_fwd = raw;
    endcase
  endfunction

  typedef enum logic [1:0] { M_IDLE, M_LREQ, M_LRESP } lm_e;
  typedef enum logic [1:0] { S_IDLE, S_REQ, S_RESP }   sm_e;
  lm_e lm_q; sm_e sm_q;

  sq_e hs;                        // head store view (drain candidate)
  logic hs_drain;
  assign hs       = sq[SQ_W'(sq_head_q)];
  logic sc_retire;
  assign sc_retire = (sq_cnt != '0) && hs.is_sc && hs.sc_done && hs.committed
                  && (sm_q == S_IDLE);

  assign hs_drain = (sq_cnt != '0)
                 && !(hs.is_sc && hs.sc_done)
                 && (hs.committed || (hs.is_sc && sc_head_go && hs.addr_known))   // an SC at the head may not have executed yet
                 && (sm_q == S_IDLE)
                 && (lm_q == M_IDLE) && !ld_go;   // loads first

  logic sc_lat_q, sc_held_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sc_lat_q <= 1'b0; sc_held_q <= 1'b0;
    end else if (lrsc_sc_valid && !sc_held_q) begin
      sc_lat_q  <= lrsc_sc_success;   // the verdict, at the one valid instant
      sc_held_q <= 1'b1;
    end else if (sm_q == S_IDLE) begin
      sc_held_q <= 1'b0;
    end
  end

  logic     sc_dn_q, sc_dn_ack;
  rob_ptr_t sc_dn_id_q;
  preg_t    sc_dn_pdst_q;
  word_t    sc_dn_val_q;
  assign sc_done_pulse  = sc_dn_q;
  assign sc_done_rob_id = sc_dn_id_q;
  assign sc_done_pdst   = sc_dn_pdst_q;
  assign sc_done_val    = sc_dn_val_q;
  assign sc_dn_ack      = sc_dn_q;

  logic sc_outstanding;
  always_comb begin
    sc_outstanding = 1'b0;
    for (int i = 0; i < SQ_N; i++) begin
      automatic sqp_t pp = sq_head_q + sqp_t'(i);
      if ((sqp_t'(i) < sq_cnt) && sq[SQ_W'(pp)].is_sc && !sq[SQ_W'(pp)].sc_done)
        sc_outstanding = 1'b1;
    end
  end

  logic sc_verdict;
  assign sc_verdict = sc_held_q ? sc_lat_q : lrsc_sc_success;

  assign lrsc_lr_valid  = ld_go && hl.is_lr;
  assign lrsc_sc_valid  = (sm_q == S_REQ) && hs.is_sc && dgnt;
  assign lrsc_addr      = lrsc_sc_valid ? hs.addr : hl.addr;
  assign lrsc_acc_valid = ld_go || (hs_drain && !hs.is_sc);

  // An LR runs only at the ROB head with every committed store drained: a younger or
  // wrong-path LR would open a reservation window that an older SC could then use.
  logic lr_ok;
  assign lr_ok = !hl.is_lr || (lr_go_ok && (sq_committed_n == '0));
  assign pick_rob_id_o = hl.rob_id;

  logic ld_go;
  assign ld_go = hl_valid && !fwd_hit && !conflict
              && (lm_q == M_IDLE) && (sm_q == S_IDLE)
              && !skid_v_q      // a response landing on a held skid would drop a completion
              && lr_ok
              && !recovering;   // no new load launch during recovery

  logic     skid_v_q;
  rob_ptr_t skid_id_q;
  preg_t    skid_pdst_q;
  word_t    skid_data_q;
  word_t      skid_raw_q;
  word_t      skid_addr_q;
  mem_size_e  skid_size_q;
  logic       skid_err_q;

  logic fwd_fire;
  assign fwd_fire = hl_valid && fwd_hit && !skid_v_q
                 && (lm_q == M_IDLE)
                 && !hl.is_lr      // an LR must read memory so that its reservation is real
                 && !recovering;   // no new forward-complete in recovery

  logic ld_resp;
  assign ld_resp = (lm_q == M_LRESP) && drvalid;

  word_t st_wdata;
  logic [3:0] st_wstrb;
  lsu u_slsu (
    .is_lr(1'b0), .is_sc(hs.is_sc), .sc_success(sc_verdict),
    .mem_re(1'b0), .mem_we(1'b1), .mem_size(hs.size),
    .addr(hs.addr), .rs2_data(hs.data),
    .mem_wdata(st_wdata), .mem_wstrb(st_wstrb),
    .mem_rdata('0), .load_data(),
    .load_misaligned(), .store_misaligned()
  );
  word_t ld_data_mem;
  lsu u_llsu (
    .is_lr(hl.is_lr), .is_sc(1'b0), .sc_success(1'b0),  // load side
    .mem_re(1'b1), .mem_we(1'b0), .mem_size(hl.size),
    .addr(hl.addr), .rs2_data('0),
    .mem_wdata(), .mem_wstrb(),
    .mem_rdata(drdata), .load_data(ld_data_mem),
    .load_misaligned(), .store_misaligned()
  );

  assign dreq   = (lm_q == M_LREQ) || (sm_q == S_REQ);
  assign dwe    = (sm_q == S_REQ);
  assign dis_lr = (lm_q == M_LREQ) && hl.is_lr;
  assign daddr  = (sm_q == S_REQ) ? hs.addr : hl.addr;
  assign dwstrb = st_wstrb;
  assign dwdata = st_wdata;

  assign lq_tail_o = lq_tail_q;
  assign sq_tail_o = sq_tail_q;

  assign quiet = (lm_q == M_IDLE) && (sm_q == S_IDLE)
              && (sq_committed_n == '0) && !skid_v_q && !ld_comp_valid;

  assign rvfi_m_st_valid = fill_valid && fill_is_store;
  assign rvfi_m_st_id    = fill_rob_id;
  assign rvfi_m_st_addr  = fill_addr;
  assign rvfi_m_st_wdata = word_t'(fill_wdata << {fill_addr[1:0], 3'b000});
  assign rvfi_m_st_wmask = bmask(fill_size, fill_addr[1:0]);

  assign rvfi_m_ld_valid = skid_v_q;
  assign rvfi_m_ld_id    = skid_id_q;
  assign rvfi_m_ld_addr  = skid_addr_q;
  assign rvfi_m_ld_rdata = skid_raw_q;
  assign rvfi_m_ld_rmask = bmask(skid_size_q, skid_addr_q[1:0]);

  assign ld_comp_valid  = skid_v_q;
  assign ld_comp_rob_id = skid_id_q;
  assign ld_comp_pdst   = skid_pdst_q;
  assign ld_comp_data   = skid_data_q;
  assign ld_comp_err    = skid_err_q;
  assign ld_comp_addr   = skid_addr_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sq_head_q <= '0; sq_tail_q <= '0;
      lq_head_q <= '0; lq_tail_q <= '0; lq_inf_q <= '0;
      lm_q <= M_IDLE;  sm_q <= S_IDLE;
      sc_dn_q <= 1'b0; sc_dn_id_q <= '0; sc_dn_pdst_q <= '0; sc_dn_val_q <= '0;
      skid_v_q <= 1'b0; skid_id_q <= '0; skid_pdst_q <= '0; skid_data_q <= '0;
      skid_err_q <= 1'b0;
      for (int i = 0; i < SQ_N; i++) sq[i] <= '0;
      for (int i = 0; i < LQ_N; i++) lq[i] <= '0;
    end else begin
      if (alloc_store) begin
        sq[SQ_W'(sq_tail_q)] <= '{addr_known: 1'b0, committed: 1'b0,
                                  addr: '0, data: '0, size: MEM_W,
                                  rob_id: alloc_rob_id, is_sc: alloc_is_sc,
                                  pdst: alloc_pdst, sc_done: 1'b0};
        sq_tail_q <= sq_tail_q + sqp_t'(1);
      end
      if (alloc_load) begin
        lq[LQ_W'(lq_tail_q)] <= '{filled: 1'b0, executed: 1'b0,
                                  addr: '0, size: MEM_W,
                                  pdst: '0, rob_id: alloc_rob_id,
                                  sq_horizon: sq_tail_q + sqp_t'(alloc_store),
                                  fwd_valid: 1'b0, fwd_sq: '0,
                                  is_lr: alloc_is_lr};
        lq_tail_q <= lq_tail_q + lqp_t'(1);
      end

      if (fill_valid) begin
        if (fill_is_store) begin
          for (int i = 0; i < SQ_N; i++) begin
            automatic sqp_t p = sq_head_q + sqp_t'(i);
            if ((sqp_t'(i) < sq_cnt) && sq[SQ_W'(p)].rob_id == fill_rob_id
                && !sq[SQ_W'(p)].addr_known) begin
              sq[SQ_W'(p)].addr_known <= 1'b1;
              sq[SQ_W'(p)].addr       <= fill_addr;
              sq[SQ_W'(p)].data       <= fill_wdata;
              sq[SQ_W'(p)].size       <= fill_size;
            end
          end
        end else begin
          for (int i = 0; i < LQ_N; i++) begin
            automatic lqp_t p = lq_head_q + lqp_t'(i);
            if ((lqp_t'(i) < lq_cnt) && lq[LQ_W'(p)].rob_id == fill_rob_id
                && !lq[LQ_W'(p)].filled) begin
              lq[LQ_W'(p)].filled <= 1'b1;
              lq[LQ_W'(p)].addr   <= fill_addr;
              lq[LQ_W'(p)].size   <= fill_size;
              lq[LQ_W'(p)].pdst   <= fill_pdst;
            end
          end
        end
      end

      if (fwd_fire) begin
        skid_v_q    <= 1'b1;
        skid_id_q   <= hl.rob_id;
        skid_pdst_q <= hl.pdst;
        skid_data_q <= extend_fwd(fwd_raw, hl.size);
        skid_raw_q  <= word_t'(fwd_raw << {hl.addr[1:0], 3'b000});
        skid_addr_q <= hl.addr;
        skid_size_q <= hl.size;
        skid_err_q  <= 1'b0;
        lq[LQ_W'(lq_pick)].executed  <= 1'b1;
        lq[LQ_W'(lq_pick)].fwd_valid <= 1'b1;
        lq[LQ_W'(lq_pick)].fwd_sq    <= fwd_src;
      end

      unique case (lm_q)
        M_IDLE:  if (ld_go) begin
                   lm_q     <= M_LREQ;
                   lq_inf_q <= lq_pick;
                 end
        M_LREQ:  if (dgnt)                  lm_q <= M_LRESP;
        M_LRESP: if (drvalid) begin
                   lm_q <= M_IDLE;
                   skid_v_q    <= 1'b1;
                   skid_id_q   <= hl.rob_id;
                   skid_pdst_q <= hl.pdst;
                   skid_data_q <= ld_data_mem;
                   skid_raw_q  <= drdata;      // raw, pre-extension
                   skid_addr_q <= hl.addr;
                   skid_size_q <= hl.size;
                   skid_err_q  <= drerr;
                   lq[LQ_W'(lq_inf_q)].executed <= 1'b1;
                 end
        default: lm_q <= M_IDLE;
      endcase

      if (skid_v_q && ld_comp_ready)
        skid_v_q <= 1'b0;

      if (store_release) begin
        begin
          automatic logic donez = 1'b0;
          for (int i = 0; i < SQ_N; i++) begin
            automatic sqp_t p = sq_head_q + sqp_t'(i);
            if (!donez && (sqp_t'(i) < sq_cnt) && !sq[SQ_W'(p)].committed) begin
              sq[SQ_W'(p)].committed <= 1'b1;
              donez = 1'b1;
            end
          end
        end
      end
      if (sc_retire) sq_head_q <= sq_head_q + sqp_t'(1);
      sc_dn_q <= sc_dn_q && !sc_dn_ack;

      unique case (sm_q)
        S_IDLE:  if (hs_drain)              sm_q <= S_REQ;
        S_REQ:   if (dgnt)                  sm_q <= S_RESP;
        S_RESP:  if (drvalid) begin
                   sm_q <= S_IDLE;
                   if (hs.is_sc && !hs.sc_done) begin
                     sq[SQ_W'(sq_head_q)].sc_done <= 1'b1;   // stay queued
                     sc_dn_q      <= 1'b1;
                     sc_dn_id_q   <= hs.rob_id;
                     sc_dn_pdst_q <= hs.pdst;
                     sc_dn_val_q  <= sc_lat_q ? 32'd0 : 32'd1;  // ISA: 0 = success
                   end else begin
                     sq_head_q <= sq_head_q + sqp_t'(1);
                   end
                 end
        default: sm_q <= S_IDLE;
      endcase

      if (restore_valid) begin
        lq_tail_q <= lq_restore_tail;
        sq_tail_q <= sq_restore_tail;
      end

      if (load_release) lq_head_q <= lq_head_q + lqp_t'(1);
      if (lq_walk_pop)  lq_tail_q <= lq_tail_q - lqp_t'(1);
      if (sq_walk_pop)  sq_tail_q <= sq_tail_q - sqp_t'(1);
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (alloc_store && !sq_can_alloc) $fatal(1, "lsq: SQ overflow");
      if (alloc_load  && !lq_can_alloc) $fatal(1, "lsq: LQ overflow");
      if (sq_walk_pop && sq[SQ_W'(sq_tail_q - sqp_t'(1))].committed)
        $fatal(1, "lsq: walking a COMMITTED store");
      if (sq_walk_pop && sq_cnt == '0) $fatal(1, "lsq: SQ walk on empty");
      if (lq_walk_pop && lq_cnt == '0) $fatal(1, "lsq: LQ walk on empty");
      if (load_release && !lq[LQ_W'(lq_head_q)].executed)
        $fatal(1, "lsq: retiring an unexecuted load");
      if (restore_valid)
        for (int i = 0; i < SQ_N; i++) begin
          automatic sqp_t p = sq_head_q + sqp_t'(i);
          if ((sqp_t'(i) < sq_cnt)
              && (sqp_t'(i) >= sqp_t'(sq_restore_tail - sq_head_q))
              && sq[SQ_W'(p)].committed)
            $fatal(1, "lsq: restore dropping a COMMITTED store");
        end
    end
  end
`endif

endmodule
