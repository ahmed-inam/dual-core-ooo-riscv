/* verilator lint_off UNUSEDSIGNAL */
// 64-entry direct-mapped branch target buffer; carries the is-a-call bit.
module btb
  import rv32i_pkg::*;
#(
  parameter int unsigned WORDS_PER_LINE = 4      // must match fetch_queue
)(
  input  logic       clk,
  input  logic       rst_n,

  input  logic       fetch_pc_en,   // issue a predictor read this cycle
  input  word_t      fetch_pc,
  output logic       [WORDS_PER_LINE-1:0] hit,
  output word_t      [WORDS_PER_LINE-1:0] target,
  output btb_class_e [WORDS_PER_LINE-1:0] cf_class,
  output logic       [WORDS_PER_LINE-1:0] is_call,

  input  bp_update_t update,
  input  logic       flush          // fence.i: drop every entry
);

  localparam int unsigned WOFF_W    = $clog2(WORDS_PER_LINE);   // 2
  localparam int unsigned LINE_IDX_W= BTB_IDX_W - WOFF_W;       // 4
  localparam int unsigned LINE_N    = BTB_ENTRIES / WORDS_PER_LINE; // 16
  localparam int unsigned COL_W     = 64;                        // one lane
  localparam int unsigned ROW_W     = WORDS_PER_LINE * COL_W;    // 256

  localparam int unsigned O_VALID = 0;
  localparam int unsigned O_TAG   = O_VALID + 1;                 // 1
  localparam int unsigned O_TGT   = O_TAG   + BTB_TAG_W;         // 25
  localparam int unsigned O_CLASS = O_TGT   + XLEN;              // 57
  localparam int unsigned O_CALL  = O_CLASS + 2;                 // 59

  function automatic logic [COL_W-1:0] pack
      (input logic v, input btb_tag_t t, input word_t tgt,
       input btb_class_e c, input logic cl);
    logic [COL_W-1:0] e;
    e = '0;
    e[O_VALID]              = v;
    e[O_TAG   +: BTB_TAG_W] = t;
    e[O_TGT   +: XLEN]      = tgt;
    e[O_CLASS +: 2]         = c;
    e[O_CALL]               = cl;
    return e;
  endfunction

  logic [LINE_IDX_W-1:0] rd_line;
  btb_tag_t              rd_tag;
  assign rd_line = fetch_pc[2+WOFF_W +: LINE_IDX_W];
  assign rd_tag  = fetch_pc[XLEN-1 : 2+WOFF_W+LINE_IDX_W];

  btb_tag_t              rd_tag_q;
  logic [LINE_IDX_W-1:0] rd_line_q;
  logic                  rd_seen_q;   // a read has happened; rd_row holds it
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rd_tag_q <= '0; rd_line_q <= '0; rd_seen_q <= 1'b0; end
    else if (fetch_pc_en) begin
      rd_tag_q  <= rd_tag;
      rd_line_q <= rd_line;
      rd_seen_q <= 1'b1;
    end
  end

  logic [LINE_IDX_W-1:0] wr_line;
  logic [WOFF_W-1:0]     wr_woff;
  btb_tag_t              wr_tag;
  logic                  wr_en;
  btb_class_e            wr_class;
  assign wr_line = update.pc[2+WOFF_W +: LINE_IDX_W];
  assign wr_woff = update.pc[2         +: WOFF_W];
  assign wr_tag  = update.pc[XLEN-1 : 2+WOFF_W+LINE_IDX_W];
  logic wr_bogus;
  assign wr_bogus = update.valid && (update.cf_type == CF_NONE);   // stale entry
  assign wr_en   = update.valid && update.taken && !wr_bogus;

  logic valid_q [LINE_N][WORDS_PER_LINE];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      for (int l = 0; l < LINE_N; l++)
        for (int w = 0; w < WORDS_PER_LINE; w++) valid_q[l][w] <= 1'b0;
    else if (flush)
      for (int l = 0; l < LINE_N; l++)
        for (int w = 0; w < WORDS_PER_LINE; w++) valid_q[l][w] <= 1'b0;
    else if (wr_en || wr_bogus)
      valid_q[wr_line][wr_woff] <= wr_en;
  end
  always_comb begin
    if      (update.ret)                 wr_class = BTB_RET;
    else if (update.cf_type == CF_JALR)  wr_class = BTB_JALR;
    else if (update.cf_type == CF_JAL)   wr_class = BTB_JAL;
    else                                 wr_class = BTB_BRANCH;
  end

  logic [COL_W-1:0] wr_col;
  assign wr_col = pack(1'b1, wr_tag, update.target, wr_class, update.call);
  logic [ROW_W-1:0]   wr_row;
  logic [ROW_W/8-1:0] wr_be;
  always_comb begin
    wr_row = {WORDS_PER_LINE{wr_col}};
    wr_be  = '0;
    if (wr_en) wr_be[wr_woff*(COL_W/8) +: (COL_W/8)] = '1;
  end

  logic [ROW_W-1:0] rd_row;
  sram_1r1w #(.WIDTH(ROW_W), .DEPTH(LINE_N)) u_ram (
    .clk,
    .rd_en   (fetch_pc_en),
    .rd_addr (rd_line),
    .rd_data (rd_row),
    .wr_en   (wr_en),
    .wr_addr (wr_line),
    .wr_data (wr_row),
    .wr_be   (wr_be)
  );

  always_comb begin
    for (int w = 0; w < WORDS_PER_LINE; w++) begin
      automatic logic [COL_W-1:0] col = rd_row[w*COL_W +: COL_W];
      hit[w]      = rd_seen_q && valid_q[rd_line_q][w] && col[O_VALID]
                    && (col[O_TAG +: BTB_TAG_W] == rd_tag_q);
      target[w]   = col[O_TGT   +: XLEN];
      cf_class[w] = btb_class_e'(col[O_CLASS +: 2]);
      is_call[w]  = col[O_CALL];
    end
  end

endmodule
/* verilator lint_on UNUSEDSIGNAL */
