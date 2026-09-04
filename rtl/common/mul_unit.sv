// One 33-bit signed multiplier serves all four RV32M flavours; 3 cycles.
module mul_unit
  import rv32i_pkg::*;
(
  input  logic   clk,
  input  logic   rst_n,

  input  word_t  a,
  input  word_t  b,
  input  m_op_e  m_op,      // only [1:0] decode the flavor; qualified upstream

  input  logic   en_m,      // = ex_mem's gated enable
  input  logic   flush_m,   // = ex_mem's flush arm

  input  logic   en_w,      // = mem_wb's gated enable
  input  logic   flush_w,   // = mem_wb's flush arm

  output word_t  result_w   // aligned with mem_wb_q; consumed by WB_MUL
);

  logic  sign_a, sign_b, take_upper;
  assign sign_a     = (m_op == M_MULH) || (m_op == M_MULHSU);
  assign sign_b     = (m_op == M_MULH);
  assign take_upper = (m_op != M_MUL);

  logic signed [65:0] prod;
  assign prod = $signed({a[31] & sign_a, a}) * $signed({b[31] & sign_b, b});

  word_t sel_e;
  assign sel_e = take_upper ? prod[63:32] : prod[31:0];

  word_t p_m_q, p_w_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if      (!rst_n)   p_m_q <= '0;
    else if (flush_m)  p_m_q <= '0;
    else if (en_m)     p_m_q <= sel_e;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if      (!rst_n)   p_w_q <= '0;
    else if (flush_w)  p_w_q <= '0;
    else if (en_w)     p_w_q <= p_m_q;
  end

  assign result_w = p_w_q;

endmodule
