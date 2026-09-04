// Unit proof of the map table.
`timescale 1ns/1ps
module tb_rename;
  import core_cfg_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic [WIDTH-1:0][4:0] lrs1, lrs2, ldst;
  preg_t [WIDTH-1:0] prs1, prs2, stale_pdst;
  logic  [WIDTH-1:0] remap_valid; preg_t [WIDTH-1:0] remap_pdst;
  logic  [WIDTH-1:0] snap_take; snap_ptr_t [WIDTH-1:0] snap_id_i;
  logic  snap_restore; snap_ptr_t snap_id_r;
  preg_t [31:0] map_dbg;

  rename dut (.*);

  int errors = 0;
  preg_t model [32];
  task chk(string s, logic c); if (!c) begin $display("FAIL %s", s); errors++; end endtask

  task automatic idle();
    for (int i = 0; i < WIDTH; i++) begin
      remap_valid[i] = 0; snap_take[i] = 0;
      lrs1[i] = '0; lrs2[i] = '0; ldst[i] = '0; remap_pdst[i] = '0;
      snap_id_i[i] = '0;
    end
    snap_restore = 0; snap_id_r = '0;
  endtask

  task automatic ren(input logic [4:0] d, input preg_t np, output preg_t stale);
    @(negedge clk);
    ldst[0] = d; remap_pdst[0] = np; remap_valid[0] = 1;
    #1 stale = stale_pdst[0];
    @(negedge clk);
    remap_valid[0] = 0;
    if (d != 0) model[d] = np;
  endtask

  task automatic verify_map(string tag);
    for (int r = 0; r < 32; r++)
      chk($sformatf("%s: map[x%0d]", tag, r), map_dbg[r] == model[r]);
  endtask

  preg_t st, st2;
  initial begin
    idle();
    for (int r = 0; r < 32; r++) model[r] = preg_t'(r);
    #12 rst_n = 1;
    @(negedge clk);

    verify_map("reset");
    lrs1[0] = 5'd7; lrs2[0] = 5'd0; #1;
    chk("read x7 -> p7", prs1[0] == preg_t'(7));
    chk("read x0 -> p0", prs2[0] == preg_t'(0));

    ren(5'd5, preg_t'(40), st);
    chk("waw1 stale = p5", st == preg_t'(5));
    ren(5'd5, preg_t'(41), st);
    chk("waw2 stale = p40", st == preg_t'(40));
    ren(5'd5, preg_t'(42), st);
    chk("waw3 stale = p41", st == preg_t'(41));
    lrs1[0] = 5'd5; #1;
    chk("x5 reads p42", prs1[0] == preg_t'(42));
    verify_map("post-waw");

    ren(5'd0, preg_t'(55), st);
    model[0] = preg_t'(0);
    lrs1[0] = 5'd0; #1;
    chk("x0 still p0", prs1[0] == preg_t'(0));
    verify_map("x0-pin");

    ren(5'd3, preg_t'(43), st);
    ren(5'd9, preg_t'(44), st);
    @(negedge clk);
    ldst[0] = 5'd12; remap_pdst[0] = preg_t'(45); remap_valid[0] = 1;
    snap_take[0] = 1; snap_id_i[0] = snap_ptr_t'(2);
    @(negedge clk);
    remap_valid[0] = 0; snap_take[0] = 0;
    model[12] = preg_t'(45);
    begin : snap_window
      preg_t snap_model [32];
      for (int r = 0; r < 32; r++) snap_model[r] = model[r];
      ren(5'd3,  preg_t'(46), st);
      ren(5'd12, preg_t'(47), st);
      chk("wrong-path stale sees p45", st == preg_t'(45));
      @(negedge clk);
      snap_restore = 1; snap_id_r = snap_ptr_t'(2);
      @(negedge clk);
      snap_restore = 0;
      for (int r = 0; r < 32; r++) model[r] = snap_model[r];
      @(negedge clk);
      verify_map("restore");
      lrs1[0] = 5'd12; #1;
      chk("snap included own slot: x12 -> p45", prs1[0] == preg_t'(45));
    end

    ren(5'd5, preg_t'(41), st);   // undo p42 (stale of the walk = don't care)
    ren(5'd5, preg_t'(40), st);
    ren(5'd5, preg_t'(5),  st);
    lrs1[0] = 5'd5; #1;
    chk("walk restored x5 -> p5", prs1[0] == preg_t'(5));

    if (WIDTH > 1) begin
      @(negedge clk);
      ldst[0] = 5'd6;  remap_pdst[0] = preg_t'(50); remap_valid[0] = 1;
      lrs1[1] = 5'd6;  ldst[1] = 5'd6; remap_pdst[1] = preg_t'(51);
      remap_valid[1] = 1;
      #1;
      chk("ingroup RAW: slot1 rs1 = p50",   prs1[1]       == preg_t'(50));
      chk("ingroup WAW: slot1 stale = p50", stale_pdst[1] == preg_t'(50));
      @(negedge clk);
      remap_valid[0] = 0; remap_valid[1] = 0;
      model[6] = preg_t'(51);          // youngest wins in the table
      @(negedge clk);
      verify_map("ingroup-write");

      @(negedge clk);
      ldst[0] = 5'd8; remap_pdst[0] = preg_t'(52); remap_valid[0] = 1;
      lrs1[1] = 5'd2; lrs2[1] = 5'd8; ldst[1] = 5'd0; remap_valid[1] = 0;
      #1;
      chk("ingroup RAW rs2: slot1 rs2 = p60", prs2[1] == preg_t'(52));
      chk("ingroup RAW rs2: slot1 rs1 = map", prs1[1] == map_dbg[2]);
      @(negedge clk); remap_valid[0] = 0; model[8] = preg_t'(52);

      @(negedge clk);
      ldst[0] = 5'd8;  remap_pdst[0] = preg_t'(53); remap_valid[0] = 1;
      lrs1[1] = 5'd9;  ldst[1] = 5'd9;  remap_pdst[1] = preg_t'(54);
      remap_valid[1] = 1;
      #1;
      chk("indep: slot1 rs1 = map[x9]",   prs1[1]       == map_dbg[9]);
      chk("indep: slot1 stale = map[x9]", stale_pdst[1] == map_dbg[9]);
      chk("indep: no cross to p61",       stale_pdst[1] != preg_t'(53));
      @(negedge clk);
      remap_valid[0] = 0; remap_valid[1] = 0;
      model[8] = preg_t'(53); model[9] = preg_t'(54);
      @(negedge clk); verify_map("indep-write");

      @(negedge clk);
      ldst[0] = 5'd10; remap_pdst[0] = preg_t'(55); remap_valid[0] = 1;
      lrs1[1] = 5'd1;  lrs2[1] = 5'd2; ldst[1] = 5'd10;
      remap_pdst[1] = preg_t'(56); remap_valid[1] = 1;
      #1;
      chk("waw-only: slot1 stale = p70",   stale_pdst[1] == preg_t'(55));
      chk("waw-only: slot1 rs1 = map[x1]", prs1[1] == map_dbg[1]);
      chk("waw-only: slot1 rs2 = map[x2]", prs2[1] == map_dbg[2]);
      @(negedge clk);
      remap_valid[0] = 0; remap_valid[1] = 0;
      model[10] = preg_t'(56);
      @(negedge clk); verify_map("waw-only-write");

      @(negedge clk);
      ldst[0] = 5'd0;  remap_pdst[0] = preg_t'(57); remap_valid[0] = 1;
      lrs1[1] = 5'd0;  ldst[1] = 5'd0; remap_valid[1] = 0;
      #1;
      chk("x0 group: slot1 reads x0 -> p0", prs1[1] == preg_t'(0));
      @(negedge clk); remap_valid[0] = 0;
    end

    if (errors == 0) $display("RENAME PASS");
    else $display("RENAME FAIL: %0d", errors);
    $finish;
  end
endmodule
