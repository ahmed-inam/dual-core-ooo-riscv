// Unit proof of the free list.
`timescale 1ns/1ps
module tb_freelist;
  import core_cfg_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic  [WIDTH-1:0] can_alloc, alloc_fire, free_fire;
  preg_t [WIDTH-1:0] alloc_preg;
  preg_t [WIDTH-1:0] free_preg;
  logic              snap_take, snap_restore;
  snap_ptr_t         snap_id;
  logic [PREG_W:0]   count;

  freelist dut (.*);

  localparam int N = PRF_N - 32;
  int errors = 0;
  task chk(string s, logic c); if (!c) begin $display("FAIL %s", s); errors++; end endtask

  task automatic alloc1(output preg_t p);
    @(negedge clk);
    chk("can_alloc[0] while allocating", can_alloc[0]);
    p = alloc_preg[0];
    alloc_fire[0] = 1;
    @(negedge clk);
    alloc_fire[0] = 0;
  endtask

  task automatic free1(input preg_t p);
    @(negedge clk);
    free_preg[0] = p;
    free_fire[0] = 1;
    @(negedge clk);
    free_fire[0] = 0;
  endtask

  task automatic drain_verify(input logic [PRF_N-1:0] expect_set, input int expect_n, string tag);
    logic [PRF_N-1:0] seen = '0;
    int n = 0;
    preg_t p;
    while (can_alloc[0]) begin
      alloc1(p);
      chk($sformatf("%s: name %0d in range", tag, p), p >= 32 && p < PRF_N);
      chk($sformatf("%s: name %0d not duplicated", tag, p), !seen[p]);
      seen[p] = 1'b1;
      n++;
      if (n > N + 4) break;   // runaway guard
    end
    chk($sformatf("%s: drained %0d == expected %0d", tag, n, expect_n), n == expect_n);
    chk($sformatf("%s: drained SET matches", tag), seen == expect_set);
    chk($sformatf("%s: count zero after drain", tag), count == '0);
  endtask

  logic [PRF_N-1:0] full_set, exp;
  preg_t got [64];
  preg_t a1, a2, a3;
  initial begin
    alloc_fire = '0; free_fire = '0; free_preg[0] = '0;
    snap_take = 0; snap_restore = 0; snap_id = '0;
    full_set = '0;
    for (int i = 32; i < PRF_N; i++) full_set[i] = 1'b1;
    #12 rst_n = 1;
    @(negedge clk);

    chk("reset count", count == (PREG_W+1)'(N));
    chk("first name is p32", alloc_preg[0] == preg_t'(32));

    drain_verify(full_set, N, "drain1");
    chk("can_alloc off at empty", !can_alloc[0]);

    for (int i = 0; i < N; i++) free1(preg_t'(32 + ((i * 7) % N)));
    @(negedge clk);
    chk("count full after refill", count == (PREG_W+1)'(N));
    drain_verify(full_set, N, "drain2");

    for (int i = 0; i < N; i++) free1(preg_t'(32 + i));

    for (int i = 0; i < 6; i++) alloc1(got[i]);
    @(negedge clk);
    snap_take = 1; snap_id = snap_ptr_t'(1);
    @(negedge clk);
    snap_take = 0;
    alloc1(a1);
    free1(got[0]);            // an older instr commits, frees a held name
    alloc1(a2);
    free1(got[1]);
    alloc1(a3);
    chk("interleave names distinct", a1 != a2 && a2 != a3 && a1 != a3);
    @(negedge clk);
    snap_restore = 1; snap_id = snap_ptr_t'(1);
    @(negedge clk);
    snap_restore = 0;
    @(negedge clk);
    exp = full_set;
    for (int i = 2; i < 6; i++) exp[got[i]] = 1'b0;
    chk("post-restore count", count == (PREG_W+1)'(N - 4));
    drain_verify(exp, N - 4, "rollback");

    rst_n = 0; @(negedge clk); rst_n = 1; @(negedge clk);
    alloc1(got[0]); alloc1(got[1]);
    snap_take = 1; snap_id = snap_ptr_t'(0); @(negedge clk); snap_take = 0;   // S0
    alloc1(got[2]);
    snap_take = 1; snap_id = snap_ptr_t'(2); @(negedge clk); snap_take = 0;   // S2
    alloc1(got[3]);
    snap_restore = 1; snap_id = snap_ptr_t'(0); @(negedge clk); snap_restore = 0;
    @(negedge clk);
    exp = full_set; exp[got[0]] = 1'b0; exp[got[1]] = 1'b0;
    chk("older-snap count", count == (PREG_W+1)'(N - 2));
    drain_verify(exp, N - 2, "older-snap");

    if (errors == 0) $display("FREELIST PASS");
    else $display("FREELIST FAIL: %0d", errors);
    $finish;
  end
endmodule
