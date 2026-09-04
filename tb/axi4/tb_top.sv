// Hardware top for the crossbar environment: clock, interfaces, DUT and test.

`timescale 1ns/1ps

import axi4_pkg::*;
import axi4_tb_pkg::*;

module tb_top;

  logic aclk   = 0;
  logic arst_n = 0;

  always #5 aclk = ~aclk;

  axi4_if #(.ID_W(ID_WIDTH)) m0 (.aclk(aclk), .arst_n(arst_n));
  axi4_if #(.ID_W(ID_WIDTH)) m1 (.aclk(aclk), .arst_n(arst_n));
  axi4_if #(.ID_W(M_ID_W))   s0 (.aclk(aclk), .arst_n(arst_n));
  axi4_if #(.ID_W(M_ID_W))   s1 (.aclk(aclk), .arst_n(arst_n));

  axi4_xbar_top dut (.aclk(aclk), .arst_n(arst_n),
                     .m0(m0), .m1(m1), .s0(s0), .s1(s1));

  xbar_probe_if pb (.aclk(aclk), .arst_n(arst_n));

  assign pb.p0_aw_pending = dut.g_mport[0].u_wr_ctrl.aw_pending;
  assign pb.p0_w_pending  = dut.g_mport[0].u_wr_ctrl.w_pending;
  assign pb.p0_tenure_cnt = dut.g_mport[0].u_wr_ctrl.tenure_cnt;
  assign pb.p0_mw_grant   = dut.mw_grant[0];
  assign pb.p0_mw_dest    = dut.mw_dest[0];
  assign pb.p0_mw_full    = dut.g_mport[0].u_wr_ctrl.mw_full;
  assign pb.p0_aw_admit   = dut.g_mport[0].u_wr_ctrl.aw_admit;
  assign pb.p0_aw_dest    = dut.aw_dest[0];
  assign pb.p0_mw_release = dut.g_mport[0].u_wr_ctrl.mw_release;
  assign pb.p0_arb_req    = dut.g_mport[0].u_wr_ctrl.arb_req;
  assign pb.p0_thr_ok     = dut.wr_thr_ok[0];

  assign pb.p1_aw_pending = dut.g_mport[1].u_wr_ctrl.aw_pending;
  assign pb.p1_w_pending  = dut.g_mport[1].u_wr_ctrl.w_pending;
  assign pb.p1_tenure_cnt = dut.g_mport[1].u_wr_ctrl.tenure_cnt;
  assign pb.p1_mw_grant   = dut.mw_grant[1];
  assign pb.p1_mw_dest    = dut.mw_dest[1];
  assign pb.p1_mw_full    = dut.g_mport[1].u_wr_ctrl.mw_full;
  assign pb.p1_aw_admit   = dut.g_mport[1].u_wr_ctrl.aw_admit;
  assign pb.p1_aw_dest    = dut.aw_dest[1];
  assign pb.p1_mw_release = dut.g_mport[1].u_wr_ctrl.mw_release;
  assign pb.p1_arb_req    = dut.g_mport[1].u_wr_ctrl.arb_req;
  assign pb.p1_thr_ok     = dut.wr_thr_ok[1];

  assign pb.s0w_arb_gnt   = dut.g_sport[0].u_swr.arb_gnt;
  assign pb.s0w_gnt_valid = dut.g_sport[0].u_swr.gnt_valid;
  assign pb.s1w_arb_gnt   = dut.g_sport[1].u_swr.arb_gnt;
  assign pb.s1w_gnt_valid = dut.g_sport[1].u_swr.gnt_valid;

  axi4_test test;

  bit  rst_busy = 0;

  always begin
    wait (pb.rst_req > 0);
    rst_busy = 1;
    @(negedge aclk);
    arst_n = 0;
    repeat (pb.rst_req) @(posedge aclk);
    @(negedge aclk);
    arst_n = 1;
    repeat (pb.rst_settle) @(posedge aclk);
    pb.rst_req = 0;
    rst_busy   = 0;
  end

  initial begin
    string tname;
    if (!$value$plusargs("TEST=%s", tname)) tname = "smoke";
    void'($value$plusargs("VERBOSITY=%d", tb_verbosity));
    verbose = (tb_verbosity >= 3);

    case (tname)
      "smoke":     begin automatic axi4_test_smoke t = new(m0, m1, s0, s1, pb); test = t; end
      "cross":     begin automatic axi4_test_cross t = new(m0, m1, s0, s1, pb); test = t; end
      "cross_rd":  begin automatic axi4_test_cross_rd t = new(m0, m1, s0, s1, pb); test = t; end
      "decerr":    begin automatic axi4_test_decerr t = new(m0, m1, s0, s1, pb); test = t; end
      "t7":        begin automatic axi4_test_t7 t = new(m0, m1, s0, s1, pb); test = t; end
      "t9":        begin automatic axi4_test_t9 t = new(m0, m1, s0, s1, pb); test = t; end
      "t10":       begin automatic axi4_test_t10 t = new(m0, m1, s0, s1, pb); test = t; end
      "t11":       begin automatic axi4_test_t11 t = new(m0, m1, s0, s1, pb); test = t; end
      "t13":       begin automatic axi4_test_t13 t = new(m0, m1, s0, s1, pb); test = t; end
      "t14":       begin automatic axi4_test_t14 t = new(m0, m1, s0, s1, pb); test = t; end
      "t15":       begin automatic axi4_test_t15 t = new(m0, m1, s0, s1, pb); test = t; end
      "t16":       begin automatic axi4_test_t16 t = new(m0, m1, s0, s1, pb); test = t; end
      "t17":       begin automatic axi4_test_t17 t = new(m0, m1, s0, s1, pb); test = t; end
      "t20":       begin automatic axi4_test_t20 t = new(m0, m1, s0, s1, pb); test = t; end
      "t21":       begin automatic axi4_test_t21 t = new(m0, m1, s0, s1, pb); test = t; end
      "t22":       begin automatic axi4_test_t22 t = new(m0, m1, s0, s1, pb); test = t; end
      "rd_handover": begin automatic axi4_test_rd_handover t = new(m0, m1, s0, s1, pb); test = t; end
      "rstwin":      begin automatic axi4_test_rstwin t = new(m0, m1, s0, s1, pb); test = t; end
      "committed": begin automatic axi4_test_committed t = new(m0, m1, s0, s1, pb); test = t; end
      "example":     begin automatic axi4_test_example t = new(m0, m1, s0, s1, pb); test = t; end
      "bursts":    begin automatic axi4_test_bursts t = new(m0, m1, s0, s1, pb); test = t; end
      "random":    begin automatic axi4_test_random t = new(m0, m1, s0, s1, pb); test = t; end
      default: begin
        automatic int n;
        automatic bit numeric = (tname.len() > 0);
        for (int i = 0; i < tname.len(); i++)
          if (tname[i] < "0" || tname[i] > "9") numeric = 0;
        if (numeric) begin
          automatic axi4_test_random t = new(m0, m1, s0, s1, pb);
          n = tname.atoi();
          t.n_txn = n;
          $display("[tb_top] numeric TEST: random, %0d transactions per master", n);
          test = t;
        end
        else begin
          automatic axi4_test_smoke t = new(m0, m1, s0, s1, pb);
          $display("[tb_top] unknown TEST=%s, running smoke", tname);
          test = t;
        end
      end
    endcase

    fork test.run(); join_none

    repeat (5) @(posedge aclk);
    @(negedge aclk);
    arst_n = 1;

    wait (test.done === 1'b1);
    repeat (50) @(posedge aclk);
    $finish;
  end

  initial begin
    #2000000;
    $display("[tb_top] GLOBAL TIMEOUT");
    $finish;
  end

endmodule
