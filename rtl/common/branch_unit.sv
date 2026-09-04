// Resolves branches and reports mispredictions.


module branch_unit
  import rv32i_pkg::*;
(
  input  cf_type_e cf_type,           // NONE / BRANCH / JAL / JALR
  input  logic     comp_result,       // branch condition, from alu.sv
  input  word_t    pc,                // PC of THIS instruction
  input  word_t    rs1_data,          // jalr base register
  input  word_t    imm,               // imm_gen: B for branch, J for jal, I for jalr

  input  bp_pred_t pred,

  output logic     taken,             // ACTUAL direction (the truth)
  output word_t    target,            // ACTUAL target
  output logic     target_misaligned, // target not 4-byte aligned -> cause 0

  output logic     mispredict
);

  word_t pc_rel;
  word_t reg_rel;

  logic dir_wrong, tgt_wrong;

  always_comb begin
    pc_rel  = pc + imm;

    reg_rel = (rs1_data + imm) & ~32'h1;
  end

  always_comb begin
    taken  = 1'b0;
    target = pc_rel;

    case (cf_type)
      CF_NONE:   taken = 1'b0;             // ordinary instruction: pc+4
      CF_BRANCH: taken = comp_result;      // the ONLY conditional case
      CF_JAL:    taken = 1'b1;             // unconditional, pc-relative
      CF_JALR:   begin
        taken  = 1'b1;                     // unconditional, register-relative
        target = reg_rel;
      end
      default:   taken = 1'b0;             // unreachable: 2-bit enum, 4 values
    endcase
  end

  assign target_misaligned = taken && (target[1:0] != 2'b00);


  assign dir_wrong = (taken != pred.taken);
  assign tgt_wrong = taken && pred.taken && (target != pred.target);
  assign mispredict = (cf_type != CF_NONE) ? (dir_wrong || tgt_wrong)
                                           : pred.taken;

endmodule
