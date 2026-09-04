/* verilator lint_off UNUSEDSIGNAL */
// 1024 two-bit counters indexed by PC xor a 10-bit global history.
`timescale 1ns/1ps
module gshare
  import rv32i_pkg::*;
#(
  parameter bit USE_HISTORY = 1'b1,
  parameter int unsigned WORDS_PER_LINE = 4       // must match fetch_queue/btb
) (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       fetch_pc_en,     // issue a PHT read this cycle
  input  word_t      fetch_pc,
  input  logic       fetch_valid,
  input  logic       [WORDS_PER_LINE-1:0] spec_shift,
  output logic       [WORDS_PER_LINE-1:0]      dir_taken,
  output logic [WORDS_PER_LINE-1:0][1:0]       pht_ctr_o,   // per-word counters
  output ghr_t       ghr_o,

  input  bp_update_t update,

  input  logic       trap_restore,
  input  ghr_t       trap_ghr
);

  localparam int unsigned WOFF_W   = $clog2(WORDS_PER_LINE);   // 2
  localparam int unsigned ROW_IDX_W= GHR_W - WOFF_W;           // 8 (256 rows)
  localparam int unsigned LINE_N   = PHT_ENTRIES / WORDS_PER_LINE; // 256
  localparam int unsigned COL_W    = 8;                         // one byte lane
  localparam int unsigned RAM_W    = WORDS_PER_LINE * COL_W;    // 32

  ghr_t ghr_q, ghr_d;
  assign ghr_o = ghr_q;

  logic [ROW_IDX_W-1:0] rd_row_idx;
  assign rd_row_idx = USE_HISTORY
      ? (fetch_pc[GHR_W+1 : 2+WOFF_W] ^ ghr_q[GHR_W-1 : WOFF_W])
      :  fetch_pc[GHR_W+1 : 2+WOFF_W];

  logic [WOFF_W-1:0] ghr_lo_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)           ghr_lo_q <= '0;
    else if (fetch_pc_en) ghr_lo_q <= USE_HISTORY ? ghr_q[WOFF_W-1:0] : '0;
  end

  logic [ROW_IDX_W-1:0] wr_row_idx;
  logic [WOFF_W-1:0]    wr_col;
  logic                 is_cond;
  logic [1:0]           old_ctr, new_ctr;
  assign wr_row_idx = USE_HISTORY
      ? (update.pc[GHR_W+1 : 2+WOFF_W] ^ update.pred.snapshot.ghr[GHR_W-1 : WOFF_W])
      :  update.pc[GHR_W+1 : 2+WOFF_W];
  assign wr_col = USE_HISTORY
      ? (update.pc[2 +: WOFF_W] ^ update.pred.snapshot.ghr[WOFF_W-1:0])
      :  update.pc[2 +: WOFF_W];
  assign is_cond = update.valid && (update.cf_type == CF_BRANCH);
  assign old_ctr = update.pred.snapshot.pht_ctr;
  always_comb begin
    if (update.taken) new_ctr = (old_ctr == 2'd3) ? 2'd3 : old_ctr + 2'd1;
    else              new_ctr = (old_ctr == 2'd0) ? 2'd0 : old_ctr - 2'd1;
  end

  logic [RAM_W-1:0]   rd_row, wr_row;
  logic [RAM_W/8-1:0] wr_be;
  always_comb begin
    for (int w = 0; w < WORDS_PER_LINE; w++) begin
      automatic logic [WOFF_W-1:0] col = w[WOFF_W-1:0] ^ ghr_lo_q;
      pht_ctr_o[w] = rd_row[col*COL_W +: 2];
      dir_taken[w] = rd_row[col*COL_W + 1];
    end
  end
  always_comb begin
    wr_row = {WORDS_PER_LINE{ {6'b0, new_ctr} }};
    wr_be  = '0;
    if (is_cond) wr_be[wr_col] = 1'b1;   // one byte-lane = one column
  end

  sram_1r1w #(.WIDTH(RAM_W), .DEPTH(LINE_N),
              .INIT_POISON(1'b1), .POISON_WORD(32'h0202_0202)) u_pht (
    .clk,
    .rd_en   (fetch_pc_en),
    .rd_addr (rd_row_idx),
    .rd_data (rd_row),
    .wr_en   (is_cond),
    .wr_addr (wr_row_idx),
    .wr_data (wr_row),
    .wr_be   (wr_be)
  );

  logic mispred;
  assign mispred = update.valid && update.mispredict;
  ghr_t ghr_folded;
  always_comb begin
    ghr_folded = ghr_q;
    for (int w = 0; w < WORDS_PER_LINE; w++)
      if (spec_shift[w]) ghr_folded = {ghr_folded[GHR_W-2:0], dir_taken[w]};
  end
  always_comb begin
    if (trap_restore)     ghr_d = trap_ghr;
    else if (mispred)     ghr_d = {update.pred.snapshot.ghr[GHR_W-2:0], update.taken};
    else if (fetch_valid) ghr_d = ghr_folded;   // this line's branch outcomes
    else                  ghr_d = ghr_q;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) ghr_q <= '0;
    else        ghr_q <= ghr_d;
  end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
