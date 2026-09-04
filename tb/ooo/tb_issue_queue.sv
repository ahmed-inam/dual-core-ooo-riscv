// Unit proof of the real issuer.
`timescale 1ns/1ps
module tb_issue_queue;
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic disp_valid, disp_ready, iss_valid, iss_ready, flush_all, div_ok;
  logic squash_valid; rob_ptr_t squash_base; logic [ROB_W:0] squash_bound;
  uop_t disp_uop, iss_uop;
  logic  [WAKEUP_IQ_W-1:0] wakeup_valid;
  preg_t [WAKEUP_IQ_W-1:0] wakeup_preg;

  logic  [WIDTH-1:0]   dv_v, dr_v;
  uop_t  [WIDTH-1:0]   du_v;
  preg_t [2*WIDTH-1:0] bra_v;
  logic  [2*WIDTH-1:0] brd_v;
  logic busy_model [64];
  assign dv_v[0] = disp_valid;
  assign du_v[0] = disp_uop;
  assign disp_ready = dr_v[0];
  for (genvar k = 1; k < WIDTH; k++) begin : g_inert
    assign dv_v[k] = 1'b0; assign du_v[k] = '0;
  end
  for (genvar k = 0; k < 2*WIDTH; k++) assign brd_v[k] = busy_model[bra_v[k]];

  logic  iss_valid_1_o; uop_t iss_uop_1_o;
  issue_queue dut (
    .clk, .rst_n,
    .disp_valid(dv_v), .disp_uop(du_v), .disp_ready(dr_v),
    .iss_valid, .iss_uop, .iss_ready,
    .iss_valid_1(iss_valid_1_o), .iss_uop_1(iss_uop_1_o), .iss_ready_1(1'b0),
    .busy_raddr(bra_v), .busy_rdata(brd_v),
    .wakeup_valid, .wakeup_preg, .div_ok, .flush_all,
    .squash_valid, .squash_base, .squash_bound
  );

  int errors = 0;
  task chk(string s, logic c); if (!c) begin $display("FAIL %s", s); errors++; end endtask

  function automatic uop_t mk(int tag, preg_t s1, preg_t s2,
                              logic u1, logic u2, logic is_div);
    uop_t u = '0;
    u.valid = 1;
    u.pc    = 32'h2000 + 32'(tag) * 4;
    u.ctrl  = CTRL_NOP;
    u.ctrl.uses_rs1 = u1;
    u.ctrl.uses_rs2 = u2;
    if (is_div) begin
      u.ctrl.is_m = 1'b1;
      u.ctrl.m_op = m_op_e'(3'b100);   // div-class: m_op[2]
    end
    u.prs1  = s1;
    u.prs2  = s2;
    return u;
  endfunction

  task automatic disp(input uop_t u);
    @(negedge clk);
    disp_uop = u; disp_valid = 1;
    @(negedge clk);
    disp_valid = 0;
  endtask

  task automatic wake(input int l, input preg_t p);
    @(negedge clk);
    wakeup_valid[l] = 1; wakeup_preg[l] = p;
    @(negedge clk);
    wakeup_valid[l] = 0;
  endtask

  int obs_q [$];
  always @(negedge clk)
    if (rst_n && iss_valid && iss_ready)
      obs_q.push_back(int'((iss_uop.pc - 32'h2000) >> 2));

  task automatic take(output int tag, input int limit);
    tag = -1;
    for (int c = 0; c < limit; c++) begin
      if (obs_q.size() > 0) begin
        tag = obs_q.pop_front();
        return;
      end
      @(negedge clk);
    end
    if (obs_q.size() > 0) tag = obs_q.pop_front();
  endtask

  int t;
  initial begin
    disp_valid = 0; iss_ready = 1; flush_all = 0; disp_uop = '0;
    div_ok = 1; wakeup_valid = '0; wakeup_preg = '0;
    for (int i = 0; i < 64; i++) busy_model[i] = 0;
    #12 rst_n = 1;

    disp(mk(1, preg_t'(33), preg_t'(34), 1, 1, 0));
    take(t, 6); chk("passthrough", t == 1);

    busy_model[40] = 1;
    disp(mk(2, preg_t'(40), preg_t'(0), 1, 0, 0));
    repeat (5) @(negedge clk);
    chk("held while busy-init and no wakeup", obs_q.size() == 0);
    busy_model[40] = 0;           // model consistency: producer wrote
    wake(0, preg_t'(40));
    take(t, 6); chk("released by wakeup", t == 2);

    busy_model[45] = 1;
    disp(mk(12, preg_t'(45), preg_t'(0), 1, 0, 0));
    repeat (3) @(negedge clk);
    busy_model[45] = 0;
    wake(1, preg_t'(45));
    take(t, 6); chk("released by LANE-1 wakeup", t == 12);

    busy_model[41] = 1;
    disp(mk(3, preg_t'(41), preg_t'(0), 1, 0, 0));   // A: blocked
    disp(mk(4, preg_t'(35), preg_t'(0), 1, 0, 0));   // B: ready
    take(t, 8);
    chk("B PASSED blocked A (the stage's purpose)", t == 4);
    busy_model[41] = 0;
    wake(0, preg_t'(41));
    take(t, 6); chk("A follows on its wakeup", t == 3);

    iss_ready = 0;
    disp(mk(5, preg_t'(35), preg_t'(0), 1, 0, 0));
    disp(mk(6, preg_t'(36), preg_t'(0), 1, 0, 0));
    disp(mk(7, preg_t'(37), preg_t'(0), 1, 0, 0));
    repeat (2) @(negedge clk);
    @(negedge clk); iss_ready = 1;
    take(t, 6); chk("age order 5 (oldest of three coexisting)", t == 5);
    take(t, 6); chk("age order 6", t == 6);
    take(t, 6); chk("age order 7", t == 7);

    busy_model[42] = 1;
    @(negedge clk);
    disp_uop = mk(8, preg_t'(42), preg_t'(0), 1, 0, 0); disp_valid = 1;
    wakeup_valid[0] = 1; wakeup_preg[0] = preg_t'(42);
    @(negedge clk);
    disp_valid = 0; wakeup_valid[0] = 0;
    busy_model[42] = 0;
    take(t, 6); chk("dispatch-race wakeup caught at entry", t == 8);

    busy_model[46] = 1;
    disp(mk(13, preg_t'(46), preg_t'(0), 1, 0, 0));
    repeat (2) @(negedge clk);
    @(negedge clk);
    wakeup_valid[0] = 1; wakeup_preg[0] = preg_t'(46);
    chk("no same-cycle issue on wakeup", obs_q.size() == 0);
    @(negedge clk);
    wakeup_valid[0] = 0;
    busy_model[46] = 0;
    take(t, 6); chk("issues the cycle after", t == 13);

    iss_ready = 0;
    disp(mk(9, preg_t'(37), preg_t'(0), 1, 0, 0));
    repeat (4) @(negedge clk);
    chk("held under backpressure (still offered)", iss_valid == 1'b1);
    @(negedge clk); iss_ready = 1;
    take(t, 6); chk("issues on ready", t == 9);

    div_ok = 0;
    disp(mk(20, preg_t'(33), preg_t'(34), 1, 1, 1));  // div, sources ready
    disp(mk(21, preg_t'(35), preg_t'(0), 1, 0, 0));   // alu behind it
    disp(mk(22, preg_t'(36), preg_t'(0), 1, 0, 0));
    take(t, 8); chk("alu passed the parked div (21)", t == 21);
    take(t, 6); chk("alu passed the parked div (22)", t == 22);
    repeat (3) @(negedge clk);
    chk("div still parked", obs_q.size() == 0);
    @(negedge clk); div_ok = 1;
    take(t, 6); chk("div issues when div_ok", t == 20);

    busy_model[43] = 1;
    for (int n = 0; n < IQ_N; n++)
      disp(mk(30 + n, preg_t'(43), preg_t'(0), 1, 0, 0));
    @(negedge clk); #1;
    chk("disp_ready low at full", disp_ready == 1'b0);
    @(negedge clk); flush_all = 1;
    @(negedge clk); flush_all = 0;
    @(negedge clk); #1;
    chk("flush empties", disp_ready == 1'b1);
    repeat (3) @(negedge clk);
    chk("nothing issues after flush", obs_q.size() == 0);
    busy_model[43] = 0;

    busy_model[44] = 1;
    disp(mk(10, preg_t'(44), preg_t'(44), 0, 0, 0));
    take(t, 6); chk("no-source uop issues", t == 10);

    flush_all = 1; @(negedge clk); flush_all = 0; @(negedge clk);
    iss_ready = 0;
    begin
      automatic uop_t u;
      for (int n = 10; n <= 13; n++) begin
        u = mk(n, '0, '0, 1'b0, 1'b0, 1'b0);   // no operands: born ready
        u.rob_id = rob_ptr_t'(n);
        disp(u);
      end
    end
    @(negedge clk);
    squash_valid = 1; squash_base = rob_ptr_t'(10);
    squash_bound = (ROB_W+1)'(1);
    @(negedge clk); squash_valid = 0;
    begin
      automatic int a, b, c2;
      iss_ready = 1;
      take(a, 10); take(b, 10); take(c2, 6);
      chk("squash: age-0 survivor issues first",         a == 10);
      chk("squash: age-1 (== bound) SURVIVES, in order", b == 11);
      chk("squash: age>bound never issue",               c2 == -1);
    end

    if (errors == 0) $display("ISSUE_QUEUE PASS");
    else $display("ISSUE_QUEUE FAIL: %0d", errors);
    $finish;
  end
endmodule
