// Restoring radix-2 divider: one quotient bit per cycle, about 35 cycles.
module div_unit
  import rv32i_pkg::*;
(
  input  logic   clk,
  input  logic   rst_n,

  input  logic   start,     // valid div in E, this cycle (core qualifies)
  input  m_op_e  m_op,      // M_DIV / M_DIVU / M_REM / M_REMU
  input  word_t  a,         // dividend (rs1, forwarded)
  input  word_t  b,         // divisor  (rs2, forwarded)

  input  logic   advance,   // the instruction in E moved on (consume)
  input  logic   flush,     // squash of the E occupant: abort to IDLE

  output logic   busy,      // pipeline hold (hazard_unit)
  output logic   done,      // result valid, held until advance
  output word_t  result     // quotient or remainder, sign-fixed
);

  typedef enum logic [1:0] { DV_IDLE, DV_RUN, DV_DONE } dvstate_e;
  dvstate_e st_q, st_d;

  logic        sign_a, sign_b, is_signed, want_rem_q, want_rem_d;
  logic        neg_q_q, neg_q_d;      // negate quotient at the end
  logic        neg_r_q, neg_r_d;      // negate remainder at the end
  logic        bzero_q, bzero_d;      // divide by zero, resolved at load

  logic [32:0] rem_q, rem_d;          // running remainder (extra bit for cmp)
  word_t       dvd_q, dvd_d;          // |dividend|, shifting out MSB-first
  word_t       quo_q, quo_d;          // quotient, shifting in LSB-first
  word_t       bab_q, bab_d;          // |divisor|
  logic [5:0]  cnt_q, cnt_d;

  assign is_signed = !m_op[0];                    // DIV/REM signed
  assign sign_a    = is_signed && a[31];
  assign sign_b    = is_signed && b[31];

  logic [32:0] shifted, diff;
  logic        ge;
  assign shifted = {rem_q[31:0], dvd_q[31]};
  assign diff    = shifted - {1'b0, bab_q};
  assign ge      = !diff[32];

  always_comb begin
    st_d       = st_q;
    rem_d      = rem_q;
    dvd_d      = dvd_q;
    quo_d      = quo_q;
    bab_d      = bab_q;
    cnt_d      = cnt_q;
    want_rem_d = want_rem_q;
    neg_q_d    = neg_q_q;
    neg_r_d    = neg_r_q;
    bzero_d    = bzero_q;

    case (st_q)
      DV_IDLE: if (start) begin
        want_rem_d = m_op[1];                     // REM/REMU
        neg_q_d    = (sign_a ^ sign_b) && (b != '0);  // ibex's ~bzero guard
        neg_r_d    = sign_a;
        bzero_d    = (b == '0);
        if (b == '0) begin
          quo_d = 32'hFFFF_FFFF;                  // spec: all-ones
          rem_d = {1'b0, a};                      // spec: the ORIGINAL a
          st_d  = DV_DONE;                        // loop skipped
        end else begin
          dvd_d = sign_a ? (~a + 32'd1) : a;      // |a|
          bab_d = sign_b ? (~b + 32'd1) : b;      // |b|
          rem_d = '0;
          quo_d = '0;
          cnt_d = 6'd32;
          st_d  = DV_RUN;
        end
      end

      DV_RUN: begin
        rem_d = ge ? diff : {1'b0, shifted[31:0]};
        quo_d = {quo_q[30:0], ge};
        dvd_d = {dvd_q[30:0], 1'b0};
        cnt_d = cnt_q - 6'd1;
        if (cnt_q == 6'd1) st_d = DV_DONE;
      end

      DV_DONE: if (advance) st_d = DV_IDLE;

      default: st_d = DV_IDLE;
    endcase

    if (flush) st_d = DV_IDLE;                    // squash outranks everything
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q  <= DV_IDLE;
      rem_q <= '0; dvd_q <= '0; quo_q <= '0; bab_q <= '0; cnt_q <= '0;
      want_rem_q <= 1'b0; neg_q_q <= 1'b0; neg_r_q <= 1'b0; bzero_q <= 1'b0;
    end else begin
      st_q  <= st_d;
      rem_q <= rem_d; dvd_q <= dvd_d; quo_q <= quo_d; bab_q <= bab_d;
      cnt_q <= cnt_d;
      want_rem_q <= want_rem_d; neg_q_q <= neg_q_d; neg_r_q <= neg_r_d;
      bzero_q <= bzero_d;
    end
  end

  word_t quo_fix, rem_fix;
  assign quo_fix = neg_q_q ? (~quo_q + 32'd1) : quo_q;
  assign rem_fix = (neg_r_q && !bzero_q) ? (~rem_q[31:0] + 32'd1)
                                         : rem_q[31:0];

  assign busy   = (st_q == DV_RUN) || (st_q == DV_IDLE && start);
  assign done   = (st_q == DV_DONE);
  assign result = want_rem_q ? rem_fix : quo_fix;

endmodule
