// Unit gate for the coherence encodings and helper functions.
module tb_coherence_pkg
  import mem_pkg::*;
  import coherence_pkg::*;
();
  int errors = 0;

  task automatic chk(input string what, input logic cond);
    if (!cond) begin errors++; $display("  [FAIL] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  initial begin
    $display("=== tb_coherence_pkg ===");

    chk("GetS needs data",        req_needs_data(REQ_GETS)    === 1'b1);
    chk("GetM needs data",        req_needs_data(REQ_GETM)    === 1'b1);
    chk("Upgrade needs NO data",  req_needs_data(REQ_UPGRADE) === 1'b0);
    chk("PutM needs no data",     req_needs_data(REQ_PUTM)    === 1'b0);

    chk("GetS    -> snoop-to-S", snoop_of(REQ_GETS)    === SNP_TO_S);
    chk("GetM    -> snoop-to-I", snoop_of(REQ_GETM)    === SNP_TO_I);
    chk("Upgrade -> snoop-to-I", snoop_of(REQ_UPGRADE) === SNP_TO_I);

    chk("TtoB keeps a copy", rsp_keeps_copy(RSP_TtoB) === 1'b1);
    chk("BtoB keeps a copy", rsp_keeps_copy(RSP_BtoB) === 1'b1);
    chk("TtoT keeps a copy", rsp_keeps_copy(RSP_TtoT) === 1'b1);
    chk("TtoN keeps NO copy", rsp_keeps_copy(RSP_TtoN) === 1'b0);
    chk("BtoN keeps NO copy", rsp_keeps_copy(RSP_BtoN) === 1'b0);
    chk("NtoN keeps NO copy", rsp_keeps_copy(RSP_NtoN) === 1'b0);

    chk("BtoN HAD a copy (distinct from keeps_copy)", rsp_had_copy(RSP_BtoN) === 1'b1);
    chk("NtoN never had a copy",                      rsp_had_copy(RSP_NtoN) === 1'b0);
    chk("had_copy and keeps_copy differ on BtoN",
        rsp_had_copy(RSP_BtoN) !== rsp_keeps_copy(RSP_BtoN));

    chk("GetS + nobody sharing -> E",
        install_state(REQ_GETS, 1'b0) === LINE_E);
    chk("GetS + someone sharing -> S",
        install_state(REQ_GETS, 1'b1) === LINE_S);
    chk("GetM -> M regardless of sharing (0)",
        install_state(REQ_GETM, 1'b0) === LINE_M);
    chk("GetM -> M regardless of sharing (1)",
        install_state(REQ_GETM, 1'b1) === LINE_M);
    chk("Upgrade -> M",
        install_state(REQ_UPGRADE, 1'b0) === LINE_M);

    chk("TR_NONE is not transient", is_transient(TR_NONE) === 1'b0);
    chk("IS_D transient", is_transient(TR_IS_D) === 1'b1);
    chk("IM_D transient", is_transient(TR_IM_D) === 1'b1);
    chk("SM_A transient", is_transient(TR_SM_A) === 1'b1);
    chk("MI_A transient", is_transient(TR_MI_A) === 1'b1);
    chk("SM_A is readable",      trans_readable(TR_SM_A) === 1'b1);
    chk("IS_D is NOT readable",  trans_readable(TR_IS_D) === 1'b0);
    chk("IM_D is NOT readable",  trans_readable(TR_IM_D) === 1'b0);
    chk("MI_A is NOT readable",  trans_readable(TR_MI_A) === 1'b0);

    chk("LINE_I still invalid", is_valid(LINE_I) === 1'b0);
    chk("LINE_S valid",         is_valid(LINE_S) === 1'b1);
    chk("LINE_E valid, clean",  is_valid(LINE_E) === 1'b1 && needs_wb(LINE_E) === 1'b0);
    chk("LINE_M needs wb",      needs_wb(LINE_M) === 1'b1);

    chk("R-COH-N-NONZERO", LRSC_WINDOW_N > 0);
    chk("R-COH-BACKOFF (backoff < window)", LRSC_BACKOFF < LRSC_WINDOW_N);
    chk("R-COH-CNT-W holds the window", (32'd1 << LRSC_CNT_W) > LRSC_WINDOW_N);

    $display("=== tb_coherence_pkg: %0d error(s) ===", errors);
    if (errors == 0) $display("TB_COHERENCE_PKG PASS");
    else             $display("TB_COHERENCE_PKG FAIL");
    $finish;
  end
endmodule
