// The MESI transition table. Eight cells are illegal and $fatal by design.
module mesi_ctrl
  import mem_pkg::*;
  import coherence_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  line_state_t cur_state,
  input  coh_trans_e  cur_trans,

  input  logic        ev_valid,
  input  coh_event_e  ev,

  input  logic        data_shared,

  output line_state_t nxt_state,
  output coh_trans_e  nxt_trans,

  output coh_act_t    act,

  output logic        mshr_valid,
  output coh_req_e    mshr_req,

  output logic        x_violation
);

  line_state_t ns;
  coh_trans_e  nt;
  coh_act_t    a;
  logic        xv;

  always_comb begin
    ns = cur_state;
    nt = cur_trans;
    xv = 1'b0;
    a  = '{ hit:0, stall:0, req_valid:0, req:REQ_GETS, wb:0, inv:0,
            silent_drop:0, snp_resp:0, snp_rsp:RSP_NtoN, rsv_clear:0,
            finish_load:0, finish_store:0 };

    if (ev_valid) begin
      if (cur_trans == TR_NONE) begin
        unique case (cur_state)

          LINE_I: case (ev)
            EV_LOAD:  begin a.req_valid=1; a.req=REQ_GETS; nt=TR_IS_D; end
            EV_STORE: begin a.req_valid=1; a.req=REQ_GETM; nt=TR_IM_D; end
            EV_EVICT: xv = 1'b1;
            EV_SNOOP_GETS: begin a.snp_resp=1; a.snp_rsp=RSP_NtoN; end
            EV_SNOOP_GETM: begin a.snp_resp=1; a.snp_rsp=RSP_NtoN; a.rsv_clear=1; end
            EV_DATA:  xv = 1'b1;         // no request outstanding
            default:  ;
          endcase

          LINE_S: case (ev)
            EV_LOAD:  a.hit = 1'b1;
            EV_STORE: begin a.req_valid=1; a.req=REQ_UPGRADE; nt=TR_SM_A; end
            EV_EVICT: begin a.silent_drop=1; ns=LINE_I; end   // clean: no bus
            EV_SNOOP_GETS: begin a.snp_resp=1; a.snp_rsp=RSP_BtoB; end
            EV_SNOOP_GETM: begin a.snp_resp=1; a.snp_rsp=RSP_BtoN;
                                 a.inv=1; ns=LINE_I; a.rsv_clear=1; end
            EV_DATA:  xv = 1'b1;
            default:  ;
          endcase

          LINE_E: case (ev)
            EV_LOAD:  a.hit = 1'b1;
            EV_STORE: begin a.hit=1'b1; ns=LINE_M; end
            EV_EVICT: begin a.silent_drop=1; ns=LINE_I; end   // clean: no bus
            EV_SNOOP_GETS: begin a.snp_resp=1; a.snp_rsp=RSP_TtoB; ns=LINE_S; end
            EV_SNOOP_GETM: begin a.snp_resp=1; a.snp_rsp=RSP_TtoN;
                                 a.inv=1; ns=LINE_I; a.rsv_clear=1; end
            EV_DATA:  xv = 1'b1;
            default:  ;
          endcase

          LINE_M: case (ev)
            EV_LOAD:  a.hit = 1'b1;
            EV_STORE: a.hit = 1'b1;                            // already dirty
            EV_EVICT: begin a.req_valid=1; a.req=REQ_PUTM; a.wb=1; nt=TR_MI_A; end
            EV_SNOOP_GETS: begin a.snp_resp=1; a.snp_rsp=RSP_TtoB;
                                 a.wb=1; ns=LINE_S; end
            EV_SNOOP_GETM: begin a.snp_resp=1; a.snp_rsp=RSP_TtoN;
                                 a.wb=1; a.inv=1; ns=LINE_I; a.rsv_clear=1; end
            EV_DATA:  xv = 1'b1;
            default:  ;
          endcase

          default: xv = 1'b1;    // LINE_O is unreachable: S6-1 rules MESI
        endcase

      end else begin
        unique case (cur_trans)

          TR_IS_D: case (ev)
            EV_LOAD, EV_STORE:            a.stall = 1'b1;
            EV_EVICT:                     xv = 1'b1;
            EV_SNOOP_GETS, EV_SNOOP_GETM: xv = 1'b1;
            EV_DATA: begin
              ns = install_state(REQ_GETS, data_shared);
              nt = TR_NONE;
              a.finish_load = 1'b1;
            end
            default: ;
          endcase

          TR_IM_D: case (ev)
            EV_LOAD, EV_STORE:            a.stall = 1'b1;
            EV_EVICT:                     a.stall = 1'b1;
            EV_SNOOP_GETS, EV_SNOOP_GETM: xv = 1'b1;
            EV_DATA: begin
              ns = LINE_M; nt = TR_NONE; a.finish_store = 1'b1;
            end
            default: ;
          endcase

          TR_SM_A: case (ev)
            EV_LOAD:                      a.hit = 1'b1;
            EV_STORE:                     a.stall = 1'b1;
            EV_EVICT:                     a.stall = 1'b1;
            EV_SNOOP_GETS, EV_SNOOP_GETM: xv = 1'b1;
            EV_DATA: begin                // permission ack, no data expected
              ns = LINE_M; nt = TR_NONE; a.finish_store = 1'b1;
            end
            default: ;
          endcase

          TR_MI_A: case (ev)
            EV_LOAD, EV_STORE:            a.stall = 1'b1;
            EV_EVICT:                     xv = 1'b1;
            EV_SNOOP_GETS, EV_SNOOP_GETM: xv = 1'b1;
            EV_DATA: begin                // writeback ack
              ns = LINE_I; nt = TR_NONE; a.inv = 1'b1;
            end
            default: ;
          endcase

          default: xv = 1'b1;
        endcase
      end
    end
  end

  assign nxt_state   = ns;
  assign nxt_trans   = nt;
  assign act         = a;
  assign x_violation = xv;

  logic     mshr_v_q;
  coh_req_e mshr_r_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mshr_v_q <= 1'b0;
      mshr_r_q <= REQ_GETS;
    end else if (ev_valid && a.req_valid) begin
      mshr_v_q <= 1'b1;
      mshr_r_q <= a.req;                       // re-derived, see above
    end else if (ev_valid && (ev == EV_DATA) && is_transient(cur_trans)) begin
      mshr_v_q <= 1'b0;                        // transaction complete
    end
  end

  assign mshr_valid = mshr_v_q;
  assign mshr_req   = mshr_r_q;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (x_violation)
      $fatal(1, "mesi_ctrl: X-CELL REACHED state=%s trans=%s ev=%s -- the ordering point failed to hold a snoop off a transient line (design doc S3.7(b))",
             cur_state.name(), cur_trans.name(), ev.name());

    if (act.hit && act.stall)
      $fatal(1, "mesi_ctrl: hit and stall asserted together");

    if (act.snp_resp && rsp_keeps_copy(act.snp_rsp) && (nxt_state == LINE_M))
      $fatal(1, "mesi_ctrl: SWMR violation -- responded keeps-copy while staying M");

    if (ev_valid && (ev == EV_DATA) && !is_transient(cur_trans))
      $fatal(1, "mesi_ctrl: EV_DATA with no transient state");

    if (act.snp_resp && (act.snp_rsp == RSP_TtoB || act.snp_rsp == RSP_TtoN)
        && (cur_state == LINE_M) && !act.wb)
      $fatal(1, "mesi_ctrl: dirty snoop response without writeback");

    if ((cur_state == LINE_E) && ev_valid && (ev == EV_STORE) && act.req_valid)
      $fatal(1, "mesi_ctrl: E+Store issued a bus request -- E->M must be silent");

    if ((cur_state == LINE_S) && (cur_trans == TR_NONE)
        && ev_valid && (ev == EV_STORE) && act.req_valid
        && (act.req != REQ_UPGRADE))
      $fatal(1, "mesi_ctrl: S+Store must issue UPGRADE, not %s", act.req.name());
  end
`endif

endmodule
