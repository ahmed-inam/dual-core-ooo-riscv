// Decouples instruction requests from their use; one request outstanding.

module fetch_queue
  import rv32i_pkg::*;
#(
  parameter int unsigned DEPTH = 2,
  parameter word_t RESET_PC_P = RESET_PC,
  parameter bit FETCH_WIDE = 1'b0
) (
  input  logic  clk,
  input  logic  rst_n,

  output logic  ireq,
  input  logic  ignt,
  output word_t iaddr,
  input  logic  irvalid,
  input  word_t irdata,
  input  logic [3:0][31:0] irdata_line,
  input  logic [3:0]       iwmask,
  input  logic  irerr = 1'b0,       // with irvalid: the line fetch faulted

  input  bp_pred_t bp_pred,
  input  bp_pred_t [3:0] bp_pred_vec,
  input  logic     [3:0] word_valid,
  output logic     accept,        // offered address accepted -> read issued

  input  logic  redirect_resolve_valid,
  input  word_t redirect_resolve_target,
  input  logic  ex_mem_en,        // E advancing: the resolve event completes
  input  logic  redirect_trap_valid,
  input  word_t redirect_trap_target,

  input  logic [1:0]           out_pop_n,   // 0/1/2 entries consumed this cycle
  output logic [1:0]           out_valid,
  output word_t [1:0]          out_pc,
  output word_t [1:0]          out_instr,
  output bp_pred_t [1:0]       out_bp,
  output logic [1:0]           out_err,       // instruction access fault
  output logic                 out_empty      // -> hazard_unit.ifetch_stall
);

  localparam int unsigned PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  logic resolve_taken_q;
  logic resolve_event;
  assign resolve_event = redirect_resolve_valid && !resolve_taken_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                        resolve_taken_q <= 1'b0;
    else if (ex_mem_en)                resolve_taken_q <= 1'b0;
    else if (resolve_event)            resolve_taken_q <= 1'b1;
  end

  logic redirect_now;
  assign redirect_now = redirect_trap_valid || resolve_event;

  logic     outstanding_q;
  logic     pend_valid_q;
  word_t    pend_target_q;
  word_t    infl_pc_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if      (!rst_n)            outstanding_q <= 1'b0;
    else if (ireq && ignt)      outstanding_q <= 1'b1;   // set wins on b2b
    else if (irvalid)           outstanding_q <= 1'b0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pend_valid_q  <= 1'b0;
      pend_target_q <= '0;
    end else if (redirect_now && outstanding_q) begin
      pend_valid_q  <= 1'b1;
      pend_target_q <= redirect_trap_valid ? redirect_trap_target
                                           : redirect_resolve_target;
    end else if (pend_valid_q && !outstanding_q) begin
      pend_valid_q  <= 1'b0;                             // applied this cycle
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)            infl_pc_q <= RESET_PC_P;
    else if (ireq && ignt) infl_pc_q <= iaddr;   // read-issue PC; bp arrives N+1
  end

  localparam int unsigned LINE_BYTES_FQ = 16;
  word_t fetch_addr_q;
  word_t pred_next_seq;
  assign pred_next_seq = bp_pred.taken ? bp_pred.target
                       : FETCH_WIDE ? (infl_line_base + word_t'(LINE_BYTES_FQ))
                                    : (infl_pc_q + 32'd4);   // parked: +4

  // A resolve landing in the cycle a pended redirect applies is the younger of
  // the two recoveries, so its target supersedes the pended one.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                                   fetch_addr_q <= RESET_PC_P;
    else if (redirect_trap_valid && !outstanding_q)
                                                  fetch_addr_q <= redirect_trap_target;
    else if (resolve_event && !outstanding_q)     fetch_addr_q <= redirect_resolve_target;
    else if (pend_valid_q && !outstanding_q)      fetch_addr_q <= pend_target_q;
    else if (irvalid && !redirect_now && !pend_valid_q)
                                                  fetch_addr_q <= pred_next_seq;
  end

  assign iaddr = fetch_addr_q;

  typedef struct packed {
    word_t    pc;
    word_t    instr;
    bp_pred_t bp;
    logic     err;
  } fq_entry_t;

  fq_entry_t             fifo_q [DEPTH];
  logic [PTR_W-1:0]      rd_q, wr_q;
  logic [PTR_W:0]        count_q;

  logic push, flush;
  assign flush = redirect_now;
  assign push  = irvalid && !pend_valid_q && !flush;

  word_t infl_line_base;
  assign infl_line_base = {infl_pc_q[31:4], 4'b0000};   // 16 B line base

  logic [3:0] eff_mask;
  always_comb begin
    if (FETCH_WIDE) eff_mask = iwmask & word_valid;
    else begin
      eff_mask = '0;
      eff_mask[infl_pc_q[3:2]] = 1'b1;
    end
  end

  logic [2:0] push_n;
  always_comb begin
    push_n = '0;
    for (int i = 0; i < 4; i++) push_n += 3'(eff_mask[i]);
  end

  logic [1:0] offered_n;
  assign offered_n = out_valid[0] + out_valid[1];   // 0/1/2 entries present
  logic [1:0] pop_n;
  assign pop_n = flush ? 2'd0
               : (out_pop_n < offered_n) ? out_pop_n : offered_n;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_q <= '0; wr_q <= '0; count_q <= '0;
    end else if (flush) begin
      rd_q <= '0; wr_q <= '0; count_q <= '0;
    end else begin
      if (push) begin
        automatic logic [PTR_W-1:0] w = wr_q;
        for (int i = 0; i < 4; i++) begin
          if (eff_mask[i]) begin
            fifo_q[w] <= '{pc:    infl_line_base + word_t'(i) * 32'd4,
                           instr: irdata_line[i],
                           bp:    bp_pred_vec[i],
                           err:   irerr};
            w = (w == PTR_W'(DEPTH-1)) ? '0 : w + 1'b1;
          end
        end
        wr_q <= w;
      end
      begin
        automatic logic [PTR_W-1:0] r = rd_q;
        for (int k = 0; k < 2; k++)
          if (2'(k) < pop_n) r = (r == PTR_W'(DEPTH-1)) ? '0 : r + 1'b1;
        rd_q <= r;
      end
      count_q <= count_q + (push ? (PTR_W+1)'(push_n) : (PTR_W+1)'(0))
                         - (PTR_W+1)'(pop_n);
    end
  end

  logic [PTR_W-1:0] rd_q1;
  assign rd_q1 = (rd_q == PTR_W'(DEPTH-1)) ? '0 : rd_q + 1'b1;

  assign out_valid[0] = (count_q >= (PTR_W+1)'(1));
  assign out_valid[1] = (count_q >= (PTR_W+1)'(2));
  assign out_empty    = (count_q == '0);
  assign out_pc[0]    = fifo_q[rd_q].pc;
  assign out_instr[0] = fifo_q[rd_q].instr;
  assign out_bp[0]    = fifo_q[rd_q].bp;
  assign out_pc[1]    = fifo_q[rd_q1].pc;
  assign out_instr[1] = fifo_q[rd_q1].instr;
  assign out_bp[1]    = fifo_q[rd_q1].bp;
  assign out_err[0]   = fifo_q[rd_q].err;
  assign out_err[1]   = fifo_q[rd_q1].err;

  localparam int unsigned WORDS_PER_LINE = 4;
  assign ireq   = !pend_valid_q && !redirect_now && !outstanding_q
                  && (FETCH_WIDE
                      ? ((count_q + (PTR_W+1)'(WORDS_PER_LINE)) <= (PTR_W+1)'(DEPTH))
                      : ((count_q + (PTR_W+1)'(outstanding_q)) < (PTR_W+1)'(DEPTH)));
  assign accept = ireq && ignt;

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && (FETCH_WIDE
                  ? ((count_q + (PTR_W+1)'(WORDS_PER_LINE) * (PTR_W+1)'(outstanding_q))
                      > (PTR_W+1)'(DEPTH))
                  : ((count_q + (PTR_W+1)'(outstanding_q)) > (PTR_W+1)'(DEPTH))))
      $fatal(1, "fetch_queue: count_q + outstanding reserve exceeds DEPTH");
  end
  initial if (FETCH_WIDE && (DEPTH < 2*WORDS_PER_LINE))
    $fatal(1, "fetch_queue: FETCH_WIDE DEPTH (%0d) < 2*WORDS_PER_LINE (%0d)", DEPTH, 2*WORDS_PER_LINE);
`endif

endmodule
