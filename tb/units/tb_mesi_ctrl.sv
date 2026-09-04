// Gate for mesi_ctrl: walk ALL 48 cells of the C1.
module tb_mesi_ctrl
  import mem_pkg::*;
  import coherence_pkg::*;
();

  logic        clk = 1'b0, rst_n = 1'b0;
  line_state_t cur_state;
  coh_trans_e  cur_trans;
  logic        ev_valid;
  coh_event_e  ev;
  logic        data_shared;
  line_state_t nxt_state;
  coh_trans_e  nxt_trans;
  coh_act_t    act;
  logic        mshr_valid, x_violation;
  coh_req_e    mshr_req;

  int errors = 0;
  int checked = 0;

  always #5 clk = ~clk;

  mesi_ctrl dut (
    .clk, .rst_n, .cur_state, .cur_trans, .ev_valid, .ev, .data_shared,
    .nxt_state, .nxt_trans, .act, .mshr_valid, .mshr_req, .x_violation
  );

  task automatic apply(input line_state_t st, input coh_trans_e tr,
                       input coh_event_e e, input logic shared = 1'b0);
    cur_state = st; cur_trans = tr; ev = e; data_shared = shared; ev_valid = 1'b1;
    #1;
  endtask

  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [FAIL] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  int xcell;

  initial begin
    if (!$value$plusargs("XCELL=%d", xcell)) xcell = -1;
    rst_n = 1'b0; ev_valid = 1'b0;
    cur_state = LINE_I; cur_trans = TR_NONE; ev = EV_NONE; data_shared = 1'b0;
    repeat (3) @(negedge clk); rst_n = 1'b1; @(negedge clk);

    if (xcell >= 0) begin
      $display("=== tb_mesi_ctrl: provoking x-cell %0d ===", xcell);
      case (xcell)
        0: apply(LINE_I, TR_NONE, EV_EVICT);        // invalid line as victim
        1: apply(LINE_S, TR_NONE, EV_DATA);         // data with no request
        2: apply(LINE_I, TR_IS_D, EV_SNOOP_GETS);   // snoop on transient
        3: apply(LINE_I, TR_IS_D, EV_SNOOP_GETM);
        4: apply(LINE_I, TR_IM_D, EV_SNOOP_GETS);
        5: apply(LINE_S, TR_SM_A, EV_SNOOP_GETM);
        6: apply(LINE_M, TR_MI_A, EV_SNOOP_GETS);
        7: apply(LINE_M, TR_MI_A, EV_EVICT);        // re-evict during writeback
        default: ;
      endcase
      @(negedge clk);
      $display("XCELL %0d NOT DETECTED -- FAIL", xcell);
      $finish;
    end

    $display("=== tb_mesi_ctrl: walking the 40 legal C1 cells ===");

    apply(LINE_I, TR_NONE, EV_LOAD);
    ck("I+Load  -> GetS, IS_D",
       act.req_valid && act.req==REQ_GETS && nxt_trans==TR_IS_D && !act.hit);
    apply(LINE_I, TR_NONE, EV_STORE);
    ck("I+Store -> GetM, IM_D",
       act.req_valid && act.req==REQ_GETM && nxt_trans==TR_IM_D);
    apply(LINE_I, TR_NONE, EV_SNOOP_GETS);
    ck("I+SnoopGetS -> resp NtoN (not-shared), stay I",
       act.snp_resp && act.snp_rsp==RSP_NtoN && !rsp_keeps_copy(act.snp_rsp)
       && nxt_state==LINE_I);
    apply(LINE_I, TR_NONE, EV_SNOOP_GETM);
    ck("I+SnoopGetM -> resp NtoN, , stay I",
       act.snp_resp && act.snp_rsp==RSP_NtoN && act.rsv_clear && nxt_state==LINE_I);

    apply(LINE_S, TR_NONE, EV_LOAD);
    ck("S+Load -> hit, stay S", act.hit && nxt_state==LINE_S && !act.req_valid);
    apply(LINE_S, TR_NONE, EV_STORE);
    ck("S+Store -> UPGRADE (not a refetch), SM_A",
       act.req_valid && act.req==REQ_UPGRADE && nxt_trans==TR_SM_A);
    ck("S+Store upgrade needs NO data returned", !req_needs_data(act.req));
    apply(LINE_S, TR_NONE, EV_EVICT);
    ck("S+Evict -> silent drop, no bus",
       act.silent_drop && nxt_state==LINE_I && !act.req_valid && !act.wb);
    apply(LINE_S, TR_NONE, EV_SNOOP_GETS);
    ck("S+SnoopGetS -> resp BtoB (shared), stay S",
       act.snp_resp && act.snp_rsp==RSP_BtoB && rsp_keeps_copy(act.snp_rsp)
       && nxt_state==LINE_S && !act.wb);
    apply(LINE_S, TR_NONE, EV_SNOOP_GETM);
    ck("S+SnoopGetM -> resp BtoN, inv->I, , no wb (clean)",
       act.snp_resp && act.snp_rsp==RSP_BtoN && act.inv && nxt_state==LINE_I
       && act.rsv_clear && !act.wb);

    apply(LINE_E, TR_NONE, EV_LOAD);
    ck("E+Load -> hit, stay E", act.hit && nxt_state==LINE_E);
    apply(LINE_E, TR_NONE, EV_STORE);
    ck("E+Store -> SILENT ->M, no bus traffic",
       act.hit && nxt_state==LINE_M && !act.req_valid);
    apply(LINE_E, TR_NONE, EV_EVICT);
    ck("E+Evict -> silent drop (clean), no wb",
       act.silent_drop && nxt_state==LINE_I && !act.wb);
    apply(LINE_E, TR_NONE, EV_SNOOP_GETS);
    ck("E+SnoopGetS -> resp TtoB, ->S, NO data (clean downgrade)",
       act.snp_resp && act.snp_rsp==RSP_TtoB && nxt_state==LINE_S && !act.wb);
    apply(LINE_E, TR_NONE, EV_SNOOP_GETM);
    ck("E+SnoopGetM -> resp TtoN, inv->I, , no wb",
       act.snp_resp && act.snp_rsp==RSP_TtoN && act.inv && nxt_state==LINE_I
       && act.rsv_clear && !act.wb);

    apply(LINE_M, TR_NONE, EV_LOAD);
    ck("M+Load -> hit, stay M", act.hit && nxt_state==LINE_M);
    apply(LINE_M, TR_NONE, EV_STORE);
    ck("M+Store -> hit, stay M, no bus",
       act.hit && nxt_state==LINE_M && !act.req_valid);
    apply(LINE_M, TR_NONE, EV_EVICT);
    ck("M+Evict -> PutM with wb, MI_A (ordered+acked)",
       act.req_valid && act.req==REQ_PUTM && act.wb && nxt_trans==TR_MI_A);
    apply(LINE_M, TR_NONE, EV_SNOOP_GETS);
    ck("M+SnoopGetS -> resp TtoB, WB, ->S",
       act.snp_resp && act.snp_rsp==RSP_TtoB && act.wb && nxt_state==LINE_S);
    apply(LINE_M, TR_NONE, EV_SNOOP_GETM);
    ck("M+SnoopGetM -> resp TtoN, WB, inv->I, ",
       act.snp_resp && act.snp_rsp==RSP_TtoN && act.wb && act.inv
       && nxt_state==LINE_I && act.rsv_clear);

    apply(LINE_I, TR_IS_D, EV_LOAD);   ck("IS_D+Load  stalls",  act.stall && !act.hit);
    apply(LINE_I, TR_IS_D, EV_STORE);  ck("IS_D+Store stalls",  act.stall);
    apply(LINE_I, TR_IS_D, EV_DATA, 1'b0);
    ck("IS_D+Data, NOT shared -> E (the E optimisation)",
       nxt_state==LINE_E && nxt_trans==TR_NONE && act.finish_load);
    apply(LINE_I, TR_IS_D, EV_DATA, 1'b1);
    ck("IS_D+Data, shared -> S",
       nxt_state==LINE_S && nxt_trans==TR_NONE && act.finish_load);

    apply(LINE_I, TR_IM_D, EV_LOAD);   ck("IM_D+Load  stalls", act.stall);
    apply(LINE_I, TR_IM_D, EV_STORE);  ck("IM_D+Store stalls", act.stall);
    apply(LINE_I, TR_IM_D, EV_EVICT);  ck("IM_D+Evict stalls", act.stall);
    apply(LINE_I, TR_IM_D, EV_DATA);
    ck("IM_D+Data -> M, finish store",
       nxt_state==LINE_M && nxt_trans==TR_NONE && act.finish_store);
    apply(LINE_I, TR_IM_D, EV_DATA, 1'b1);
    ck("IM_D+Data ignores shared-bit -> still M", nxt_state==LINE_M);

    apply(LINE_S, TR_SM_A, EV_LOAD);
    ck("SM_A+Load HITS (still holds S) -- S3.3", act.hit && !act.stall);
    apply(LINE_S, TR_SM_A, EV_STORE);  ck("SM_A+Store stalls", act.stall);
    apply(LINE_S, TR_SM_A, EV_EVICT);  ck("SM_A+Evict stalls", act.stall);
    apply(LINE_S, TR_SM_A, EV_DATA);
    ck("SM_A+Ack -> M, finish store",
       nxt_state==LINE_M && nxt_trans==TR_NONE && act.finish_store);

    apply(LINE_M, TR_MI_A, EV_LOAD);   ck("MI_A+Load  stalls", act.stall);
    apply(LINE_M, TR_MI_A, EV_STORE);  ck("MI_A+Store stalls", act.stall);
    apply(LINE_M, TR_MI_A, EV_DATA);
    ck("MI_A+wbAck -> I, invalidate",
       nxt_state==LINE_I && nxt_trans==TR_NONE && act.inv);

    apply(LINE_S, TR_NONE, EV_LOAD);
    ev_valid = 1'b0; #1;
    ck("ev_valid low: no hit/stall/req/resp",
       !act.hit && !act.stall && !act.req_valid && !act.snp_resp);
    ck("ev_valid low: state held", nxt_state==cur_state && nxt_trans==cur_trans);

    $display("=== tb_mesi_ctrl: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_MESI_CTRL PASS");
    else             $display("TB_MESI_CTRL FAIL");
    $finish;
  end

  initial begin
    #100000; $display("TB_MESI_CTRL FAIL (timeout)"); $finish;
  end

endmodule
