// Branch predictor top: arbitrates BTB, gshare and RAS into one prediction.
`timescale 1ns/1ps
module bp_top
  import rv32i_pkg::*;
#(
  parameter bit USE_HISTORY = 1'b1,
  parameter bit OVF_COUNT   = 1'b1,  // RAS overflow policy; see ras.sv
  parameter int unsigned WORDS_PER_LINE = 4,  // must match fetch_queue/btb/gshare
  parameter bit FETCH_WIDE  = 1'b0   // 0: predict only the offered word (scan=1)
) (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       fetch_pc_en,   // issue a predictor read this cycle (N)
  input  word_t      fetch_pc,      // read address (N)
  input  logic       fetch_valid,   // read is a real fetch (N)
  output bp_pred_t   pred,          // LINE redirect (first-taken word), N+1
  output bp_pred_t [WORDS_PER_LINE-1:0] pred_vec,
  output logic     [WORDS_PER_LINE-1:0] word_valid,

  input  bp_update_t update,

  input  logic         trap_flush,
  input  bp_snapshot_t trap_snapshot,
  input  logic         btb_flush      // fence.i
);


  logic  en_q;             // a read was issued at N  => N+1 outputs are live
  word_t fetch_pc_q;       // read-time PC, for the RAS push address at N+1
  logic  fetch_valid_q;    // read-time fetch validity, aligned to N+1
  ghr_t  ghr_snap_q;       // read-time GHR that indexed the PHT -> snapshot

  ghr_t  ghr_o;            // gshare's current ghr_q (combinational, = N value)

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      en_q          <= 1'b0;
      fetch_pc_q    <= '0;
      fetch_valid_q <= 1'b0;
      ghr_snap_q    <= '0;
    end else begin
      en_q <= fetch_pc_en;
      if (fetch_pc_en) begin
        fetch_pc_q    <= fetch_pc;
        fetch_valid_q <= fetch_valid;
        ghr_snap_q    <= ghr_o;      // read-time GHR (held until next read)
      end
    end
  end

  localparam int unsigned WOFF_W = $clog2(WORDS_PER_LINE);
  logic [WOFF_W-1:0] woff_q;
  assign woff_q = fetch_pc_q[2 +: WOFF_W];

  logic       [WORDS_PER_LINE-1:0] btb_hit_v;
  word_t      [WORDS_PER_LINE-1:0] btb_target_v;
  btb_class_e [WORDS_PER_LINE-1:0] btb_class_v;
  logic       [WORDS_PER_LINE-1:0] btb_call_v;

  btb #(.WORDS_PER_LINE(WORDS_PER_LINE)) u_btb (
    .clk, .rst_n,
    .fetch_pc_en (fetch_pc_en),
    .fetch_pc    (fetch_pc),
    .hit         (btb_hit_v),
    .target      (btb_target_v),
    .cf_class    (btb_class_v),
    .is_call     (btb_call_v),
    .update      (update),
    .flush       (btb_flush)
  );

  logic       [WORDS_PER_LINE-1:0]      dir_taken_v;
  logic [WORDS_PER_LINE-1:0][1:0]       pht_ctr_v;

  logic [WORDS_PER_LINE-1:0] spec_shift;
  always_comb
    for (int w = 0; w < WORDS_PER_LINE; w++)
      spec_shift[w] = word_valid[w] && btb_hit_v[w] && (btb_class_v[w] == BTB_BRANCH);

  gshare #(.USE_HISTORY(USE_HISTORY), .WORDS_PER_LINE(WORDS_PER_LINE)) u_gshare (
    .clk, .rst_n,
    .fetch_pc_en     (fetch_pc_en),
    .fetch_pc        (fetch_pc),
    .fetch_valid     (fetch_valid_q & en_q),
    .spec_shift      (spec_shift),
    .dir_taken       (dir_taken_v),
    .pht_ctr_o       (pht_ctr_v),
    .ghr_o           (ghr_o),
    .update          (update),
    .trap_restore    (trap_flush),
    .trap_ghr        (trap_snapshot.ghr)
  );

  logic     ras_push, ras_pop, ras_valid;
  word_t    ras_top;
  ras_ptr_t ras_tos_o;
  ras_ovf_t ras_ovf_o;
  logic     mispred, real_fetch;
  assign mispred    = update.valid && update.mispredict;
  assign real_fetch = en_q && fetch_valid_q;

  word_t line_base_q;
  assign line_base_q = {fetch_pc_q[XLEN-1:2+WOFF_W], {(WOFF_W+2){1'b0}}};

  logic [WOFF_W-1:0] hi;
  assign hi = FETCH_WIDE ? WOFF_W'(WORDS_PER_LINE-1) : woff_q;

  logic  [WORDS_PER_LINE-1:0] w_taken;
  word_t [WORDS_PER_LINE-1:0] w_target;
  always_comb begin
    for (int w = 0; w < WORDS_PER_LINE; w++) begin
      w_taken[w]  = 1'b0;
      w_target[w] = line_base_q + word_t'(w)*32'd4 + 32'd4;   // fall-through
      if (btb_hit_v[w]) begin
        unique case (btb_class_v[w])
          BTB_RET:           begin w_taken[w] = ras_valid;      w_target[w] = ras_top;         end
          BTB_JAL, BTB_JALR: begin w_taken[w] = 1'b1;           w_target[w] = btb_target_v[w]; end
          default:           begin w_taken[w] = dir_taken_v[w]; w_target[w] = btb_target_v[w]; end
        endcase
      end
    end
  end

  logic              any_taken;
  logic [WOFF_W-1:0] ftw;
  always_comb begin
    any_taken = 1'b0;
    ftw       = woff_q;
    for (int w = 0; w < WORDS_PER_LINE; w++)
      if (!any_taken && (WOFF_W'(w) >= woff_q) && (WOFF_W'(w) <= hi) && w_taken[w]) begin
        any_taken = 1'b1;
        ftw       = WOFF_W'(w);
      end
  end

  assign ras_push = real_fetch && any_taken && btb_call_v[ftw] &&
                    ((btb_class_v[ftw] == BTB_JAL) || (btb_class_v[ftw] == BTB_JALR));
  assign ras_pop  = real_fetch && any_taken && (btb_class_v[ftw] == BTB_RET);

  ras #(.OVF_COUNT(OVF_COUNT)) u_ras (
    .clk, .rst_n,
    .push        (ras_push),
    .push_addr   (line_base_q + word_t'(ftw)*32'd4 + 32'd4),
    .pop         (ras_pop),
    .restore     (trap_flush || mispred),
    .restore_tos (trap_flush ? trap_snapshot.ras_tos : update.pred.snapshot.ras_tos),
    .restore_ovf (trap_flush ? trap_snapshot.ras_ovf : update.pred.snapshot.ras_ovf),
    .top(ras_top), .top_valid(ras_valid), .tos_o(ras_tos_o), .ovf_o(ras_ovf_o)
  );

  bp_pred_t [WORDS_PER_LINE-1:0] pred_vec_c, pred_vec_q;
  logic     [WORDS_PER_LINE-1:0] word_valid_c, word_valid_q;
  bp_pred_t                      pred_c, pred_q;
  always_comb begin
    for (int w = 0; w < WORDS_PER_LINE; w++) begin
      pred_vec_c[w]              = BP_PRED_NONE;
      pred_vec_c[w].taken        = w_taken[w];
      pred_vec_c[w].target       = w_target[w];
      pred_vec_c[w].btb_hit      = btb_hit_v[w];
      pred_vec_c[w].btb_class    = btb_class_v[w];
      pred_vec_c[w].dir_taken    = dir_taken_v[w];
      pred_vec_c[w].snapshot.ghr     = ghr_snap_q;
      pred_vec_c[w].snapshot.ras_tos = ras_tos_o;
      pred_vec_c[w].snapshot.ras_ovf = ras_ovf_o;
      pred_vec_c[w].snapshot.pht_ctr = pht_ctr_v[w];
      word_valid_c[w] = (WOFF_W'(w) >= woff_q) && (WOFF_W'(w) <= hi) &&
                        (!any_taken || (WOFF_W'(w) <= ftw));
    end
  end

  always_comb begin
    pred_c = pred_vec_c[ftw];
    if (!any_taken) begin
      pred_c.taken  = 1'b0;
      pred_c.target = w_target[hi];
    end
  end

  // The fetch queue samples the prediction when the line arrives, which on an
  // I-cache miss is many cycles after the read: hold it until the next read.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pred_vec_q   <= {WORDS_PER_LINE{BP_PRED_NONE}};
      word_valid_q <= '0;
      pred_q       <= BP_PRED_NONE;
    end else if (en_q) begin
      pred_vec_q   <= pred_vec_c;
      word_valid_q <= word_valid_c;
      pred_q       <= pred_c;
    end
  end
  assign pred_vec   = en_q ? pred_vec_c   : pred_vec_q;
  assign word_valid = en_q ? word_valid_c : word_valid_q;
  assign pred       = en_q ? pred_c       : pred_q;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (ras_push && ras_pop)
      $fatal(1, "bp_top: double RAS action in one fetch");
    for (int w = 1; w < WORDS_PER_LINE; w++)
      if (word_valid[w] && !word_valid[w-1] && (WOFF_W'(w) > woff_q))
        $fatal(1, "bp_top: word_valid not contiguous (hole before word %0d)", w);
  end
`endif

endmodule
