// Arithmetic and logic unit; branch comparisons reuse the subtractor.

module alu
  import rv32i_pkg::*;
(
  input  alu_op_e op,
  input  word_t   a,
  input  word_t   b,
  output word_t   result,       // register writeback value
  output logic    comp_result   // branch condition, for branch_unit
);

  logic is_eq, is_lt_s, is_lt_u;

  always_comb begin
    is_eq   = (a == b);
    is_lt_s = ($signed(a) < $signed(b));   // BOTH operands cast
    is_lt_u = (a < b);                     // neither cast -> unsigned
  end

  always_comb begin
    case (op)
      ALU_ADD:  result = a + b;
      ALU_SUB:  result = a - b;

      ALU_XOR:  result = a ^ b;
      ALU_OR:   result = a | b;
      ALU_AND:  result = a & b;

      ALU_SLL:  result = a << b[4:0];

      ALU_SRL:  result = a >> b[4:0];

      ALU_SRA:  result = $signed(a) >>> b[4:0];

      ALU_SLT:  result = {31'b0, is_lt_s};
      ALU_SLTU: result = {31'b0, is_lt_u};

      default:  result = '0;
    endcase
  end

  always_comb begin
    case (op)
      ALU_EQ:   comp_result =  is_eq;
      ALU_NE:   comp_result = ~is_eq;
      ALU_LT:   comp_result =  is_lt_s;
      ALU_GE:   comp_result = ~is_lt_s;   // bge is "not less than"
      ALU_LTU:  comp_result =  is_lt_u;
      ALU_GEU:  comp_result = ~is_lt_u;   // bgeu likewise
      default:  comp_result = 1'b0;
    endcase
  end

endmodule
