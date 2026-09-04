// 16-entry age-ordered issue queue with broadcast wakeup.
module issue_queue
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
(
  input  logic   clk,
  input  logic   rst_n,

  input  logic   [WIDTH-1:0] disp_valid,
  input  uop_t   [WIDTH-1:0] disp_uop,
  output logic   [WIDTH-1:0] disp_ready,   // cumulative room (slot k assumes 0..k-1 inserted)

  output logic   iss_valid,
  output uop_t   iss_uop,
  input  logic   iss_ready,
  output logic   iss_valid_1,
  output uop_t   iss_uop_1,
  input  logic   iss_ready_1,

  output preg_t [2*WIDTH-1:0] busy_raddr,
  input  logic  [2*WIDTH-1:0] busy_rdata,

  input  logic  [WAKEUP_IQ_W-1:0] wakeup_valid,
  input  preg_t [WAKEUP_IQ_W-1:0] wakeup_preg,

  input  logic   div_ok,

  input  logic   flush_all,

  input  logic     squash_valid,
  input  rob_ptr_t squash_base,     // the frozen head
  input  logic [ROB_W:0] squash_bound   // the branch's age; drop age > bound
);

  uop_t q  [IQ_N];
  logic r1 [IQ_N];
  logic r2 [IQ_N];
  logic [IQ_W:0] cnt_q;

  for (genvar k = 0; k < WIDTH; k++)
    assign disp_ready[k] = (cnt_q + (IQ_W+1)'(k) < (IQ_W+1)'(IQ_N));

  for (genvar k = 0; k < WIDTH; k++) begin : g_braddr
    assign busy_raddr[2*k]   = disp_uop[k].prs1;
    assign busy_raddr[2*k+1] = disp_uop[k].prs2;
  end

  function automatic logic wakes(preg_t p);
    logic hit = 1'b0;
    for (int w = 0; w < WAKEUP_IQ_W; w++)
      if (wakeup_valid[w] && wakeup_preg[w] == p) hit = 1'b1;
    return hit;
  endfunction

  function automatic logic ingroup_busy(preg_t p, int k);
    logic hit = 1'b0;
    for (int j = 0; j < WIDTH; j++)
      if (j < k && disp_valid[j] && disp_uop[j].ctrl.rf_we
          && disp_uop[j].pdst != preg_t'(0) && disp_uop[j].pdst == p) hit = 1'b1;
    return hit;
  endfunction

  logic [WIDTH-1:0] init_r1, init_r2;
  for (genvar k = 0; k < WIDTH; k++) begin : g_init
    assign init_r1[k] = !disp_uop[k].ctrl.uses_rs1
                      || (!busy_rdata[2*k]   && !ingroup_busy(disp_uop[k].prs1, k))
                      || wakes(disp_uop[k].prs1);
    assign init_r2[k] = !disp_uop[k].ctrl.uses_rs2
                      || (!busy_rdata[2*k+1] && !ingroup_busy(disp_uop[k].prs2, k))
                      || wakes(disp_uop[k].prs2);
  end

  logic [IQ_N-1:0] request;
  always_comb begin
    for (int i = 0; i < IQ_N; i++) begin
      automatic logic is_div = q[i].ctrl.is_m && q[i].ctrl.m_op[2];
      request[i] = (i < 32'(cnt_q)) && r1[i] && r2[i] && (!is_div || div_ok);
    end
  end

  function automatic logic alu_only(uop_t u);
    return !(u.ctrl.mem_re || u.ctrl.mem_we) && (u.ctrl.cf_type == CF_NONE)
        && !u.ctrl.is_m && (u.ctrl.csr_op == CSR_OP_NONE) && !u.pred.taken;
  endfunction

  logic [IQ_W-1:0] grant0;
  logic            grant0_v;
  always_comb begin
    grant0 = '0; grant0_v = 1'b0;
    for (int i = IQ_N-1; i >= 0; i--)
      if (request[i]) begin grant0 = IQ_W'(i); grant0_v = 1'b1; end
  end

  logic [IQ_W-1:0] grant1;
  logic            grant1_v;
  always_comb begin
    grant1 = '0; grant1_v = 1'b0;
    if (WIDTH > 1)
      for (int i = IQ_N-1; i >= 0; i--)
        if (request[i] && alu_only(q[i]) && !(grant0_v && IQ_W'(i) == grant0)) begin
          grant1 = IQ_W'(i); grant1_v = 1'b1;
        end
  end

  assign iss_valid   = grant0_v;
  assign iss_uop     = q[grant0];
  assign iss_valid_1 = grant1_v;
  assign iss_uop_1   = q[grant1];

  logic pop0, pop1;
  logic [WIDTH-1:0] push;
  assign pop0 = grant0_v && iss_ready;
  assign pop1 = grant1_v && iss_ready_1;
  for (genvar k = 0; k < WIDTH; k++)
    assign push[k] = disp_valid[k] && disp_ready[k];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_q <= '0;
      for (int i = 0; i < IQ_N; i++) begin
        q[i] <= '0; r1[i] <= 1'b0; r2[i] <= 1'b0;
      end
    end else if (flush_all) begin
      cnt_q <= '0;
    end else begin
      automatic int j = 0;
      for (int i = 0; i < IQ_N; i++) begin
        automatic logic [ROB_W:0] age_i =
            (ROB_W+1)'(q[i].rob_id) - (ROB_W+1)'(squash_base);
        automatic logic squashed =
            squash_valid && (age_i > squash_bound);
        if (i < 32'(cnt_q)
            && !(pop0 && IQ_W'(i) == grant0)
            && !(pop1 && IQ_W'(i) == grant1)
            && !squashed) begin
          q[j]  <= q[i];
          r1[j] <= r1[i] || wakes(q[i].prs1);
          r2[j] <= r2[i] || wakes(q[i].prs2);
          j++;
        end
      end
      for (int k = 0; k < WIDTH; k++) begin
        if (push[k]) begin
          q[j]  <= disp_uop[k];
          r1[j] <= init_r1[k];
          r2[j] <= init_r2[k];
          j++;
        end
      end
      cnt_q <= (IQ_W+1)'(j);
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && !flush_all) begin
      if (pop0 && !request[grant0])
        $fatal(1, "issue_queue: port0 granted a non-requesting slot %0d", grant0);
      if (pop1 && !request[grant1])
        $fatal(1, "issue_queue: port1 granted a non-requesting slot %0d", grant1);
      if (pop1 && !alu_only(q[grant1]))
        $fatal(1, "issue_queue: port1 issued a non-ALU-only uop");
      for (int k = 0; k < WIDTH; k++)
        if (disp_valid[k] && !disp_ready[k] && cnt_q != (IQ_W+1)'(IQ_N))
          $fatal(1, "issue_queue: refusing dispatch slot %0d while not full", k);
    end
  end
`endif

endmodule
