// The ordering point: one coherence transaction at a time, machine-wide.
module coherence_mgr
  import rv32i_pkg::*;      // word_t
  import mem_pkg::*;
  import coherence_pkg::*;
  import platform_cfg_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic     [NUM_HARTS-1:0] req_valid,
  input  word_t                    req_addr  [NUM_HARTS],
  input  coh_req_e                 req_type  [NUM_HARTS],
  input  logic     [NUM_HARTS-1:0] req_atomic,
  output logic     [NUM_HARTS-1:0] req_gnt,     // ORDERED this cycle

  output logic     [NUM_HARTS-1:0] snp_valid,
  output word_t                    snp_addr,
  output coh_snoop_e               snp_type,
  input  logic     [NUM_HARTS-1:0] snp_ack,     // response presented this cycle
  input  coh_rsp_e                 snp_rsp   [NUM_HARTS],

  input  logic     [NUM_HARTS-1:0] req_installed,

  output logic     [NUM_HARTS-1:0] cmp_valid,
  output logic                     cmp_shared,  // aggregate: someone kept a copy
  output logic                     cmp_dirty,   // aggregate: a responder was dirty

  input  logic     [NUM_HARTS-1:0] prot_valid,  // hart h holds an open window
  input  word_t                    prot_addr [NUM_HARTS],
  output logic                     prot_deferred, // we held a request off for it

  output logic                     ord_violation
);


  typedef enum logic [1:0] { O_IDLE, O_SNOOP, O_CMPL } ord_e;

  ord_e                 st_q,  st_d;
  logic [HART_W-1:0]    own_q, own_d;      // hart owning the transaction
  coh_req_e             rq_q,  rq_d;
  word_t                ad_q,  ad_d;
  logic [NUM_HARTS-1:0] todo_q, todo_d;    // snoops still to deliver (rocket probe_todo)
  logic [NUM_HARTS-1:0] wait_q, wait_d;    // responses still outstanding (rocket count)
  logic                 shr_q,  shr_d;     // accumulated shared-bit
  logic                 dty_q,  dty_d;     // accumulated dirty-bit
  logic [HART_W-1:0]    rr_q,   rr_d;      // round-robin pointer (fairness)
  // A line stays busy from its grant until the requester has installed it, so
  // the ordering point is free to order other lines while the fill is in flight.
  logic [NUM_HARTS-1:0] busy_q, busy_d;
  logic [31:OFF_W]      busy_line_q [NUM_HARTS];
  logic [31:OFF_W]      busy_line_d [NUM_HARTS];

  logic [NUM_HARTS-1:0] eligible;
  logic                 any_elig;
  logic [HART_W-1:0]    pick;
  localparam int PG_CYCLES = `ifdef PG_N `PG_N `else 255 `endif;
  logic [7:0]           pg_cnt_q, pg_cnt_d;
  logic [31:OFF_W]      pg_line_q, pg_line_d;
  logic [HART_W-1:0]    pg_hart_q, pg_hart_d;
  logic                 defer_seen;

  always_comb begin
    defer_seen = 1'b0;
    for (int h = 0; h < NUM_HARTS; h++) begin
      automatic logic same_line_busy;
      automatic logic prot_block;
      same_line_busy = (st_q != O_IDLE) && ((req_addr[h][31:OFF_W] == ad_q[31:OFF_W]));
      for (int o = 0; o < NUM_HARTS; o++)
        if (busy_q[o] && (req_addr[h][31:OFF_W] == busy_line_q[o])) same_line_busy = 1'b1;
      prot_block = 1'b0;
      for (int o = 0; o < NUM_HARTS; o++)
        if ((o != h) && prot_valid[o]
            && (req_addr[h][31:OFF_W] == prot_addr[o][31:OFF_W])
            && ((req_type[h] == REQ_GETM) || (req_type[h] == REQ_UPGRADE)))
          prot_block = 1'b1;
      if ((pg_cnt_q != '0) && (HART_W'(h) != pg_hart_q)
          && (req_addr[h][31:OFF_W] == pg_line_q)
          && !(prot_valid[h]
               && (req_addr[h][31:OFF_W] == prot_addr[h][31:OFF_W]))
          && ((req_type[h] == REQ_GETM) || (req_type[h] == REQ_UPGRADE)))
        prot_block = 1'b1;
      eligible[h] = req_valid[h] && !same_line_busy && !prot_block;
      if (req_valid[h] && prot_block) defer_seen = 1'b1;
    end

    any_elig = 1'b0;
    pick     = rr_q;
    for (int k = 0; k < NUM_HARTS; k++) begin
      automatic logic [HART_W-1:0] idx = HART_W'((int'(rr_q) + k) % NUM_HARTS);
      if (!any_elig && eligible[idx]) begin
        any_elig = 1'b1;
        pick     = idx;
      end
    end
  end

  assign prot_deferred = defer_seen;

  logic [NUM_HARTS-1:0] snp_next;
  always_comb begin
    snp_next = '0;
    for (int h = 0; h < NUM_HARTS; h++) begin
      if (todo_q[h] && (snp_next == '0)) snp_next[h] = 1'b1;   // lowest set bit
    end
  end

  assign snp_valid = (st_q == O_SNOOP) ? snp_next : '0;   // held until that hart acks
  assign snp_addr  = ad_q;
  assign snp_type  = snoop_of(rq_q);

  always_comb begin
    st_d = st_q; own_d = own_q; rq_d = rq_q; ad_d = ad_q;
    todo_d = todo_q; wait_d = wait_q; shr_d = shr_q; dty_d = dty_q; rr_d = rr_q;
    req_gnt   = '0;
    cmp_valid = '0;
    pg_cnt_d  = (pg_cnt_q != '0) ? pg_cnt_q - 8'd1 : '0;
    if ((pg_cnt_q != '0) && prot_valid[pg_hart_q]
        && (prot_addr[pg_hart_q][31:OFF_W] == pg_line_q))
      pg_cnt_d = '0;
    pg_line_d = pg_line_q;
    pg_hart_d = pg_hart_q;
    busy_d    = busy_q;
    for (int h = 0; h < NUM_HARTS; h++) begin
      busy_line_d[h] = busy_line_q[h];
      if (req_installed[h]) busy_d[h] = 1'b0;
    end

    unique case (st_q)
      O_IDLE: if (any_elig) begin
        req_gnt[pick] = 1'b1;
        if (req_atomic[pick]) begin
          pg_cnt_d = 8'(PG_CYCLES); pg_line_d = req_addr[pick][31:OFF_W]; pg_hart_d = HART_W'(pick);
        end                  // ORDERED here; nothing earlier
        if (req_type[pick] != REQ_PUTM) begin
          busy_d[pick]      = 1'b1;
          busy_line_d[pick] = req_addr[pick][31:OFF_W];
        end
        own_d  = pick;
        rq_d   = req_type[pick];
        ad_d   = req_addr[pick];
        shr_d  = 1'b0;
        dty_d  = 1'b0;
        if (req_type[pick] == REQ_PUTM) begin
          todo_d = '0; wait_d = '0; st_d = O_CMPL;
        end else begin
          todo_d = '1;
          // Snoop everyone except the requester.
          todo_d[pick] = 1'b0;
          wait_d = todo_d;
          st_d   = O_SNOOP;
        end
      end

      O_SNOOP: begin
        for (int h = 0; h < NUM_HARTS; h++) begin
          if (snp_ack[h] && wait_q[h]) begin
            todo_d[h] = 1'b0;
            wait_d[h] = 1'b0;
            if (rsp_keeps_copy(snp_rsp[h])) shr_d = 1'b1;
            if (snp_rsp[h] == RSP_TtoB || snp_rsp[h] == RSP_TtoN) dty_d = 1'b1;
          end
        end
        if ((todo_d == '0) && (wait_d == '0)) st_d = O_CMPL;
      end

      O_CMPL: begin
        cmp_valid[own_q] = 1'b1;
        rr_d = HART_W'((int'(own_q) + 1) % NUM_HARTS);   // fairness
        st_d = O_IDLE;
      end

      default: st_d = O_IDLE;
    endcase
  end

  assign cmp_shared = shr_q;
  assign cmp_dirty  = dty_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q <= O_IDLE; own_q <= '0; rq_q <= REQ_GETS; ad_q <= '0;
      todo_q <= '0; wait_q <= '0; shr_q <= 1'b0; dty_q <= 1'b0; rr_q <= '0;
      pg_cnt_q <= '0; pg_line_q <= '0; pg_hart_q <= '0;
      busy_q <= '0;
      for (int h = 0; h < NUM_HARTS; h++) busy_line_q[h] <= '0;
    end else begin
      st_q <= st_d; own_q <= own_d; rq_q <= rq_d; ad_q <= ad_d;
      todo_q <= todo_d; wait_q <= wait_d; shr_q <= shr_d; dty_q <= dty_d;
      rr_q <= rr_d;
      pg_cnt_q <= pg_cnt_d; pg_line_q <= pg_line_d; pg_hart_q <= pg_hart_d;
      busy_q <= busy_d;
      for (int h = 0; h < NUM_HARTS; h++) busy_line_q[h] <= busy_line_d[h];
    end
  end

  logic ov;
  always_comb begin
    ov = 1'b0;
    for (int h = 0; h < NUM_HARTS; h++) begin
      if (req_gnt[h] && (st_q != O_IDLE)
          && ((req_addr[h][31:OFF_W] == ad_q[31:OFF_W]))) ov = 1'b1;
      for (int o = 0; o < NUM_HARTS; o++)
        if (req_gnt[h] && busy_q[o] && (req_addr[h][31:OFF_W] == busy_line_q[o])) ov = 1'b1;
    end
    if ((st_q == O_SNOOP) && snp_valid[own_q]) ov = 1'b1;
  end
  assign ord_violation = ov;

`ifndef SYNTHESIS
  logic [15:0] snp_wait_cnt_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                 snp_wait_cnt_q <= '0;
    else if (st_q != O_SNOOP)   snp_wait_cnt_q <= '0;
    else                        snp_wait_cnt_q <= snp_wait_cnt_q + 16'd1;
  end
  always_ff @(posedge clk) if (rst_n) begin
    if (snp_wait_cnt_q == 16'd4096)
      $fatal(1, "coherence_mgr: no snoop ack for 4096 cycles (todo=%b wait=%b): a dcache ignored a one-cycle snp_valid", todo_q, wait_q);
    if (ord_violation)
      $fatal(1, "coherence_mgr: ORDERING VIOLATION -- same-line request ordered while busy, or snoop sent to the owner. mesi_ctrl's x-cells are now reachable (design doc S3.7(b))");
    if ($countones(req_gnt) > 1)
      $fatal(1, "coherence_mgr: multiple requests ordered in one cycle");
    if ($countones(cmp_valid) > 1)
      $fatal(1, "coherence_mgr: multiple completions in one cycle");
    for (int h = 0; h < NUM_HARTS; h++)
      if (cmp_valid[h] && (h != int'(own_q)))
        $fatal(1, "coherence_mgr: completion to hart %0d but owner is %0d", h, own_q);
    for (int h = 0; h < NUM_HARTS; h++)
      for (int o = 0; o < NUM_HARTS; o++)
        if (req_gnt[h] && (o != h) && prot_valid[o]
            && (req_addr[h][31:OFF_W] == prot_addr[o][31:OFF_W])
            && ((req_type[h] == REQ_GETM) || (req_type[h] == REQ_UPGRADE)))
          $fatal(1, "coherence_mgr: ordered a competing GetM/Upgrade inside hart %0d's LR/SC protection window", o);
  end
`endif

endmodule
