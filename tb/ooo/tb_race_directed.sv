// G3: the four races written BY HAND, because.
module tb_race_directed
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coherence_pkg::*;
  import platform_cfg_pkg::*;
();

  localparam int    NLINES = 2;
  localparam word_t LINE_A = 32'h8000_1000;   // the contended line
  localparam word_t LINE_B = 32'h8000_2000;   // the unrelated line (R4)

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0, ev_seen = 0, x_seen = 0;

  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  function automatic int line_idx(input word_t a);
    return (a == LINE_A) ? 0 : 1;
  endfunction
  function automatic word_t line_addr(input int i);
    return (i == 0) ? LINE_A : LINE_B;
  endfunction

  line_state_t st0 [NLINES], st1 [NLINES];
  coh_trans_e  tr0 [NLINES], tr1 [NLINES];
  int          al0, al1;

  logic     [NUM_HARTS-1:0] req_valid;
  word_t                    req_addr [NUM_HARTS];
  coh_req_e                 req_type [NUM_HARTS];
  logic     [NUM_HARTS-1:0] req_gnt;
  logic     [NUM_HARTS-1:0] snp_valid;
  word_t                    snp_addr;
  coh_snoop_e               snp_type;
  logic     [NUM_HARTS-1:0] snp_ack;
  coh_rsp_e                 snp_rsp  [NUM_HARTS];
  logic     [NUM_HARTS-1:0] cmp_valid;
  logic                     cmp_shared, cmp_dirty;
  logic     [NUM_HARTS-1:0] prot_valid;
  word_t                    prot_addr [NUM_HARTS];
  logic                     prot_deferred, ord_violation;

  assign prot_valid   = '0;
  assign prot_addr[0] = '0;
  assign prot_addr[1] = '0;

  coherence_mgr u_mgr (
    .clk, .rst_n, .req_valid, .req_addr, .req_type, .req_gnt,
    .req_atomic('0),      // [S6] no LR/SC here: never arm the post-grant window
    .snp_valid, .snp_addr, .snp_type, .snp_ack, .snp_rsp,
    .req_installed('1),   // TB has no fill stage: install is instant
    .cmp_valid, .cmp_shared, .cmp_dirty,
    .prot_valid, .prot_addr, .prot_deferred, .ord_violation
  );

  line_state_t m0_cs, m0_ns;  coh_trans_e m0_ct, m0_nt;
  logic        m0_evv, m0_shr, m0_xv;  coh_event_e m0_ev;  coh_act_t m0_act;
  mesi_ctrl u_m0 (.clk, .rst_n, .cur_state(m0_cs), .cur_trans(m0_ct),
                  .ev_valid(m0_evv), .ev(m0_ev), .data_shared(m0_shr),
                  .nxt_state(m0_ns), .nxt_trans(m0_nt), .act(m0_act),
                  .mshr_valid(), .mshr_req(), .x_violation(m0_xv));

  line_state_t m1_cs, m1_ns;  coh_trans_e m1_ct, m1_nt;
  logic        m1_evv, m1_shr, m1_xv;  coh_event_e m1_ev;  coh_act_t m1_act;
  mesi_ctrl u_m1 (.clk, .rst_n, .cur_state(m1_cs), .cur_trans(m1_ct),
                  .ev_valid(m1_evv), .ev(m1_ev), .data_shared(m1_shr),
                  .nxt_state(m1_ns), .nxt_trans(m1_nt), .act(m1_act),
                  .mshr_valid(), .mshr_req(), .x_violation(m1_xv));

  always_ff @(posedge clk) if (rst_n) begin
    if (m0_xv || m1_xv) x_seen++;
    if (ord_violation) begin errors++; $display("  [BAD ] ordering violation"); end
  end

  int  n_wb0, n_wb1, n_silent0, n_snp_ack0, n_snp_ack1;
  int  n_gnt0_upg, n_gnt0_getm;      // R2: which request hart0 actually ORDERED

  logic       w0, w1;
  coh_event_e we0, we1;

  task automatic want_op(input int h, input int li, input coh_event_e e);
    if (h == 0) begin al0 = li; we0 = e; w0 = 1'b1; end
    else        begin al1 = li; we1 = e; w1 = 1'b1; end
  endtask

  task automatic force_state(input int h, input int li,
                             input line_state_t s, input coh_trans_e t);
    if (h == 0) begin st0[li] = s; tr0[li] = t; end
    else        begin st1[li] = s; tr1[li] = t; end
  endtask

  task automatic reset_counters();
    n_wb0=0; n_wb1=0; n_silent0=0; n_snp_ack0=0; n_snp_ack1=0;
    n_gnt0_upg=0; n_gnt0_getm=0; x_seen=0;
  endtask

  logic g0, g1;

  task automatic step();
    int li0, li1;
    @(negedge clk);
    m0_evv=1'b0; m0_ev=EV_NONE; m0_shr=1'b0;
    m1_evv=1'b0; m1_ev=EV_NONE; m1_shr=1'b0;
    snp_ack='0; req_valid='0;
    req_addr[0]=line_addr(al0); req_type[0]=REQ_GETS;
    req_addr[1]=line_addr(al1); req_type[1]=REQ_GETS;
    li0=al0; li1=al1;

    if (snp_valid[0]) begin
      li0 = line_idx(snp_addr);
      m0_cs=st0[li0]; m0_ct=tr0[li0]; m0_evv=1'b1;
      m0_ev=(snp_type==SNP_TO_S)?EV_SNOOP_GETS:EV_SNOOP_GETM;
    end else if (cmp_valid[0]) begin
      m0_cs=st0[li0]; m0_ct=tr0[li0]; m0_evv=1'b1; m0_ev=EV_DATA; m0_shr=cmp_shared;
    end else if (w0) begin
      m0_cs=st0[li0]; m0_ct=tr0[li0]; m0_evv=1'b1; m0_ev=we0;
    end else begin
      m0_cs=st0[li0]; m0_ct=tr0[li0];
    end

    if (snp_valid[1]) begin
      li1 = line_idx(snp_addr);
      m1_cs=st1[li1]; m1_ct=tr1[li1]; m1_evv=1'b1;
      m1_ev=(snp_type==SNP_TO_S)?EV_SNOOP_GETS:EV_SNOOP_GETM;
    end else if (cmp_valid[1]) begin
      m1_cs=st1[li1]; m1_ct=tr1[li1]; m1_evv=1'b1; m1_ev=EV_DATA; m1_shr=cmp_shared;
    end else if (w1) begin
      m1_cs=st1[li1]; m1_ct=tr1[li1]; m1_evv=1'b1; m1_ev=we1;
    end else begin
      m1_cs=st1[li1]; m1_ct=tr1[li1];
    end

    #1;
    if (m0_evv) ev_seen++;
    if (m1_evv) ev_seen++;

    if (m0_evv && m0_act.req_valid) begin
      req_valid[0]=1'b1; req_type[0]=m0_act.req; req_addr[0]=line_addr(al0);
    end
    if (m1_evv && m1_act.req_valid) begin
      req_valid[1]=1'b1; req_type[1]=m1_act.req; req_addr[1]=line_addr(al1);
    end
    if (m0_evv && m0_act.snp_resp) begin snp_ack[0]=1'b1; snp_rsp[0]=m0_act.snp_rsp; n_snp_ack0++; end
    if (m1_evv && m1_act.snp_resp) begin snp_ack[1]=1'b1; snp_rsp[1]=m1_act.snp_rsp; n_snp_ack1++; end

    if (m0_evv && m0_act.wb)          n_wb0++;
    if (m1_evv && m1_act.wb)          n_wb1++;
    if (m0_evv && m0_act.silent_drop) n_silent0++;

    #1;
    g0 = req_gnt[0];
    g1 = req_gnt[1];

    if (g0) begin
      if (req_type[0] == REQ_UPGRADE) n_gnt0_upg++;
      if (req_type[0] == REQ_GETM)    n_gnt0_getm++;
    end

    @(posedge clk);
    #1;

    if (m0_evv) begin
      if (!m0_act.req_valid || g0) begin
        st0[li0]=m0_ns; tr0[li0]=m0_nt;
      end
      if (m0_act.req_valid && g0) w0=1'b0;
      if (m0_act.hit || m0_act.silent_drop) w0=1'b0;
      if (m0_ev==EV_DATA) w0=1'b0;
    end
    if (m1_evv) begin
      if (!m1_act.req_valid || g1) begin
        st1[li1]=m1_ns; tr1[li1]=m1_nt;
      end
      if (m1_act.req_valid && g1) w1=1'b0;
      if (m1_act.hit || m1_act.silent_drop) w1=1'b0;
      if (m1_ev==EV_DATA) w1=1'b0;
    end
  endtask

  task automatic settle(input int limit);
    int n = 0;
    while (n < limit) begin
      if (!w0 && !w1 && !is_transient(tr0[0]) && !is_transient(tr0[1])
                     && !is_transient(tr1[0]) && !is_transient(tr1[1])) break;
      step(); n++;
    end
  endtask

  task automatic quiesce();
    w0=1'b0; w1=1'b0;
    for (int l = 0; l < NLINES; l++) begin
      st0[l]=LINE_I; st1[l]=LINE_I; tr0[l]=TR_NONE; tr1[l]=TR_NONE;
    end
    repeat (4) step();
  endtask

  int i, ev_before;
  int writers, sharers;

  task automatic swmr_check(input string tag, input int li);
    writers = 0; sharers = 0;
    if (st0[li]==LINE_M || st0[li]==LINE_E) writers++;
    if (st1[li]==LINE_M || st1[li]==LINE_E) writers++;
    if (st0[li]==LINE_S) sharers++;
    if (st1[li]==LINE_S) sharers++;
    ck($sformatf("%s: SWMR -- at most one writable copy", tag), writers <= 1);
    ck($sformatf("%s: SWMR -- no writer alongside a sharer", tag),
       !(writers==1 && sharers>0));
  endtask

  initial begin
    for (int l = 0; l < NLINES; l++) begin
      st0[l]=LINE_I; st1[l]=LINE_I; tr0[l]=TR_NONE; tr1[l]=TR_NONE;
    end
    al0=0; al1=0; w0=0; w1=0; we0=EV_NONE; we1=EV_NONE;
    snp_rsp[0]=RSP_NtoN; snp_rsp[1]=RSP_NtoN;
    m0_cs=LINE_I; m0_ct=TR_NONE; m1_cs=LINE_I; m1_ct=TR_NONE;
    reset_counters();
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_race_directed (G3: the four hand-crafted races) ===");

    $display("--- R1: concurrent GetM, same line");
    quiesce(); reset_counters(); ev_before = ev_seen;
    want_op(0, 0, EV_STORE);
    want_op(1, 0, EV_STORE);
    settle(200);
    ck("R1 LIVENESS: events delivered", (ev_seen - ev_before) > 0);
    ck("R1: both stores resolved (neither hart left waiting)", !w0 && !w1);
    ck("R1: no line left transient",
       !is_transient(tr0[0]) && !is_transient(tr1[0]));
    ck("R1: exactly one hart ends in M",
       ((st0[0]==LINE_M) ^ (st1[0]==LINE_M)));
    ck("R1: the loser is INVALID, not stale-shared",
       (st0[0]==LINE_M) ? (st1[0]==LINE_I) : (st0[0]==LINE_I));
    ck("R1: zero x-cell violations", x_seen == 0);
    swmr_check("R1", 0);

    $display("--- R2: upgrade loses the race");
    quiesce(); reset_counters(); ev_before = ev_seen;
    force_state(0, 0, LINE_S, TR_NONE);      // both harts share line A
    force_state(1, 0, LINE_S, TR_NONE);
    want_op(1, 0, EV_STORE);                 // hart1 goes first
    step();                                  // hart1's Upgrade is ordered here
    want_op(0, 0, EV_STORE);                 // hart0 now wants to store too
    settle(200);
    ck("R2 LIVENESS: events delivered", (ev_seen - ev_before) > 0);
    ck("R2: exactly one hart ends in M", (st0[0]==LINE_M) ^ (st1[0]==LINE_M));
    ck("R2: the other hart is INVALID, not stale-shared",
       (st0[0]==LINE_M) ? (st1[0]==LINE_I) : (st0[0]==LINE_I));
    ck("R2: hart0 ordered a GetM (re-derived at ordering)", n_gnt0_getm > 0);
    ck("R2: hart0 was NEVER granted a stale Upgrade", n_gnt0_upg == 0);
    ck("R2: zero x-cell violations", x_seen == 0);
    swmr_check("R2", 0);

    $display("--- R3: snoop during eviction");
    quiesce(); reset_counters(); ev_before = ev_seen;
    force_state(0, 0, LINE_M, TR_NONE);      // hart0 owns it dirty
    force_state(1, 0, LINE_I, TR_NONE);
    want_op(1, 0, EV_LOAD);                  // remote GetS goes first
    step();
    want_op(0, 0, EV_EVICT);                 // hart0's eviction is now pending
    settle(200);
    ck("R3 LIVENESS: events delivered", (ev_seen - ev_before) > 0);
    ck("R3: hart0's line ended INVALID (the eviction completed)",
       st0[0] === LINE_I);
    ck("R3: the requester got its copy", st1[0] === LINE_S || st1[0] === LINE_E);
    ck("R3: exactly ONE writeback total (no double writeback)", n_wb0 == 1);
    ck("R3: the eviction itself was a SILENT drop", n_silent0 > 0);
    ck("R3: zero x-cell violations", x_seen == 0);

    $display("--- R4: snoop to line Y while MSHR busy on line X");
    quiesce(); reset_counters(); ev_before = ev_seen;
    force_state(0, 1, LINE_M, TR_NONE);      // hart0 owns line B dirty
    force_state(0, 0, LINE_I, TR_IS_D);      // ...and is TRANSIENT on line A
    al0 = 0;                                 // its MSHR is on line A
    want_op(1, 1, EV_LOAD);                  // hart1 wants line B
    settle(200);
    ck("R4 LIVENESS: events delivered", (ev_seen - ev_before) > 0);
    ck("R4: hart0 ANSWERED the snoop for line B while transient on line A",
       n_snp_ack0 > 0);
    ck("R4: hart1's request COMPLETED (no stall behind the unrelated MSHR)",
       !w1 && !is_transient(tr1[1]));
    ck("R4: hart1 got line B", st1[1] === LINE_S || st1[1] === LINE_E);
    ck("R4: hart0's line B downgraded by the snoop", st0[1] === LINE_S);
    ck("R4: hart0's transient line A was NOT disturbed", tr0[0] === TR_IS_D);
    ck("R4: zero x-cell violations (per-LINE, not per-FSM)", x_seen == 0);

    $display("=== tb_race_directed: %0d checks, %0d error(s), ev_seen=%0d ===",
             checked, errors, ev_seen);
    if (errors == 0) $display("TB_RACE_DIRECTED PASS");
    else             $display("TB_RACE_DIRECTED BROKEN");
    $finish;
  end

  initial begin
    #500000; $display("TB_RACE_DIRECTED BROKEN (timeout)"); $finish;
  end

endmodule
