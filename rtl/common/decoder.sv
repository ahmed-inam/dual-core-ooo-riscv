// Decodes RV32IM into the control bundle.

module decoder
  import rv32i_pkg::*;
(
  input  word_t instr,
  output ctrl_t ctrl
);

  logic [6:0]  opcode;
  logic [2:0]  funct3;
  logic [6:0]  funct7;
  logic        alt;         // instr[30]: add/sub, srl/sra selector
  logic [11:0] imm12;       // instr[31:20], for the SYSTEM demux

  assign opcode = get_opcode(instr);
  assign funct3 = get_funct3(instr);
  assign funct7 = get_funct7(instr);
  assign alt    = get_alt_op(instr);
  assign imm12  = get_imm12(instr);

  function automatic alu_op_e arith_op(logic [2:0] f3, logic alt_bit, logic is_imm);
    case (f3)
      F3_ADD_SUB: arith_op = (alt_bit && !is_imm) ? ALU_SUB : ALU_ADD;
      F3_SLL:     arith_op = ALU_SLL;
      F3_SLT:     arith_op = ALU_SLT;
      F3_SLTU:    arith_op = ALU_SLTU;
      F3_XOR:     arith_op = ALU_XOR;
      F3_SRL_SRA: arith_op = alt_bit ? ALU_SRA : ALU_SRL;
      F3_OR:      arith_op = ALU_OR;
      F3_AND:     arith_op = ALU_AND;
      default:    arith_op = ALU_ADD;
    endcase
  endfunction

  function automatic alu_op_e branch_cond(logic [2:0] f3);
    case (f3)
      F3_BEQ:  branch_cond = ALU_EQ;
      F3_BNE:  branch_cond = ALU_NE;
      F3_BLT:  branch_cond = ALU_LT;
      F3_BGE:  branch_cond = ALU_GE;
      F3_BLTU: branch_cond = ALU_LTU;
      F3_BGEU: branch_cond = ALU_GEU;
      default: branch_cond = ALU_EQ;
    endcase
  endfunction

  function automatic mem_size_e load_size(logic [2:0] f3);
    case (f3)
      F3_LB:   load_size = MEM_B;
      F3_LH:   load_size = MEM_H;
      F3_LW:   load_size = MEM_W;
      F3_LBU:  load_size = MEM_BU;
      F3_LHU:  load_size = MEM_HU;
      default: load_size = MEM_NONE;
    endcase
  endfunction

  function automatic mem_size_e store_size(logic [2:0] f3);
    case (f3)
      F3_SB:   store_size = MEM_B;
      F3_SH:   store_size = MEM_H;
      F3_SW:   store_size = MEM_W;
      default: store_size = MEM_NONE;
    endcase
  endfunction

  function automatic csr_op_e csr_op_of(logic [2:0] f3);
    case (f3)
      F3_CSRRW, F3_CSRRWI: csr_op_of = CSR_OP_RW;
      F3_CSRRS, F3_CSRRSI: csr_op_of = CSR_OP_RS;
      F3_CSRRC, F3_CSRRCI: csr_op_of = CSR_OP_RC;
      default:             csr_op_of = CSR_OP_NONE;
    endcase
  endfunction

  always_comb begin
    ctrl = CTRL_NOP;

    unique case (opcode)

      OPCODE_OP: begin                 // register-register arithmetic
        ctrl.rf_we    = 1'b1;
        ctrl.uses_rs1 = 1'b1;
        ctrl.uses_rs2 = 1'b1;
        ctrl.op_a_sel = OP_A_RS1;
        ctrl.op_b_sel = OP_B_RS2;
        ctrl.alu_op   = arith_op(funct3, alt, 1'b0);
        ctrl.wb_sel   = WB_ALU;
        ctrl.fu       = FU_ALU;
        if (!( funct7 == F7_BASE ||
              (funct7 == F7_ALT && (funct3 == F3_ADD_SUB ||
                                    funct3 == F3_SRL_SRA)) ))
          ctrl = CTRL_ILLEGAL;
        if (funct7 == F7_MULD) begin
          ctrl          = CTRL_NOP;    // rebuild from clean: arith_op's
          ctrl.rf_we    = 1'b1;        //   verdict above does not apply
          ctrl.uses_rs1 = 1'b1;
          ctrl.uses_rs2 = 1'b1;
          ctrl.op_a_sel = OP_A_RS1;
          ctrl.op_b_sel = OP_B_RS2;
          ctrl.is_m     = 1'b1;
          ctrl.m_op     = m_op_e'(funct3);
          if (!funct3[2]) begin        // mul family
            ctrl.wb_sel      = WB_MUL;
            ctrl.late_result = 1'b1;
          end
        end
      end

      OPCODE_OP_IMM: begin             // register-immediate arithmetic
        ctrl.rf_we    = 1'b1;
        ctrl.uses_rs1 = 1'b1;
        ctrl.op_a_sel = OP_A_RS1;
        ctrl.op_b_sel = OP_B_IMM;
        ctrl.imm_type = IMM_I;
        ctrl.alu_op   = arith_op(funct3, alt, 1'b1);
        ctrl.wb_sel   = WB_ALU;
        ctrl.fu       = FU_ALU;
        if (funct3 == F3_SLL && funct7 != F7_BASE) ctrl = CTRL_ILLEGAL;
        if (funct3 == F3_SRL_SRA && funct7 != F7_BASE && funct7 != F7_ALT)
          ctrl = CTRL_ILLEGAL;
      end

      OPCODE_LUI: begin                // rd = imm << 12
        ctrl.rf_we    = 1'b1;
        ctrl.op_a_sel = OP_A_ZERO;
        ctrl.op_b_sel = OP_B_IMM;
        ctrl.imm_type = IMM_U;
        ctrl.alu_op   = ALU_ADD;
        ctrl.wb_sel   = WB_ALU;
        ctrl.fu       = FU_ALU;
      end

      OPCODE_AUIPC: begin              // rd = pc + (imm << 12)
        ctrl.rf_we    = 1'b1;
        ctrl.op_a_sel = OP_A_PC;
        ctrl.op_b_sel = OP_B_IMM;
        ctrl.imm_type = IMM_U;
        ctrl.alu_op   = ALU_ADD;
        ctrl.wb_sel   = WB_ALU;
        ctrl.fu       = FU_ALU;
      end

      OPCODE_LOAD: begin               // rd = mem[rs1 + imm]
        ctrl.rf_we    = 1'b1;
        ctrl.uses_rs1 = 1'b1;
        ctrl.op_a_sel = OP_A_RS1;
        ctrl.op_b_sel = OP_B_IMM;
        ctrl.imm_type = IMM_I;
        ctrl.alu_op   = ALU_ADD;
        ctrl.mem_re   = 1'b1;
        ctrl.late_result = 1'b1;   // load data arrives in M, latched for W
        ctrl.mem_size = load_size(funct3);
        ctrl.wb_sel   = WB_MEM;
        ctrl.fu       = FU_MEM;
        if (load_size(funct3) == MEM_NONE) ctrl = CTRL_ILLEGAL;
      end

      OPCODE_STORE: begin              // mem[rs1 + imm] = rs2
        ctrl.uses_rs1 = 1'b1;
        ctrl.uses_rs2 = 1'b1;
        ctrl.op_a_sel = OP_A_RS1;
        ctrl.op_b_sel = OP_B_IMM;
        ctrl.imm_type = IMM_S;
        ctrl.alu_op   = ALU_ADD;
        ctrl.mem_we   = 1'b1;
        ctrl.mem_size = store_size(funct3);
        ctrl.fu       = FU_MEM;
        if (store_size(funct3) == MEM_NONE) ctrl = CTRL_ILLEGAL;
      end

      OPCODE_BRANCH: begin             // if (cond) pc += imm
        ctrl.uses_rs1 = 1'b1;
        ctrl.uses_rs2 = 1'b1;
        ctrl.op_a_sel = OP_A_RS1;
        ctrl.op_b_sel = OP_B_RS2;
        ctrl.imm_type = IMM_B;
        ctrl.alu_op   = branch_cond(funct3);
        ctrl.cf_type  = CF_BRANCH;
        ctrl.fu       = FU_ALU;
        if (funct3 == 3'b010 || funct3 == 3'b011) ctrl = CTRL_ILLEGAL;
      end

      OPCODE_JAL: begin                // rd = pc+4; pc += imm
        ctrl.rf_we    = 1'b1;
        ctrl.imm_type = IMM_J;
        ctrl.cf_type  = CF_JAL;
        ctrl.wb_sel   = WB_PC4;
        ctrl.fu       = FU_ALU;
      end

      OPCODE_JALR: begin               // rd = pc+4; pc = (rs1+imm) & ~1
        ctrl.rf_we    = 1'b1;
        ctrl.uses_rs1 = 1'b1;
        ctrl.imm_type = IMM_I;
        ctrl.cf_type  = CF_JALR;
        ctrl.wb_sel   = WB_PC4;
        ctrl.fu       = FU_ALU;
        if (funct3 != 3'b000) ctrl = CTRL_ILLEGAL;
      end

      OPCODE_SYSTEM: begin
        if (funct3 == F3_PRIV) begin   // ecall / ebreak / mret / wfi
          unique case (imm12)          // imm12 selects which
            IMM12_ECALL:  ctrl.is_ecall  = 1'b1;
            IMM12_EBREAK: ctrl.is_ebreak = 1'b1;
            IMM12_MRET:   ctrl.is_mret   = 1'b1;
            IMM12_WFI:    ;            // NOP
            default:      ctrl = CTRL_ILLEGAL;
          endcase
          if (get_rs1(instr) != '0 || get_rd(instr) != '0) ctrl = CTRL_ILLEGAL;
        end else if (csr_op_of(funct3) == CSR_OP_NONE) begin
          ctrl = CTRL_ILLEGAL;
        end else begin                 // csrr*
          ctrl.rf_we      = 1'b1;
          ctrl.uses_rs1   = (funct3 == F3_CSRRW || funct3 == F3_CSRRS ||
                             funct3 == F3_CSRRC);
          ctrl.csr_op     = csr_op_of(funct3);
          ctrl.csr_use_imm= (funct3 == F3_CSRRWI || funct3 == F3_CSRRSI ||
                             funct3 == F3_CSRRCI);
          ctrl.wb_sel     = WB_CSR;
          ctrl.late_result= csr_is_perf(imm12);
          ctrl.fu         = FU_CSR;
        end
      end

      OPCODE_MISC_MEM: begin
        ctrl.is_fence   = (funct3 == 3'b000);
        ctrl.is_fence_i = (funct3 == 3'b001);
        if (funct3 != 3'b000 && funct3 != 3'b001) ctrl = CTRL_ILLEGAL;
      end

      OPCODE_AMO: begin
        if (funct3 != 3'b010) begin
          ctrl = CTRL_ILLEGAL;                  // only .W exists on RV32
        end else begin
          unique case (instr[31:27])
            5'h02: begin                        // LR.W rd, (rs1)
              ctrl           = CTRL_NOP;
              ctrl.is_lr     = 1'b1;
              ctrl.mem_re    = 1'b1;
              ctrl.mem_size  = MEM_W;
              ctrl.fu        = FU_MEM;
              ctrl.op_a_sel  = OP_A_RS1;
              ctrl.op_b_sel  = OP_B_IMM;
              ctrl.imm_type  = IMM_NONE;
              ctrl.alu_op    = ALU_ADD;
              ctrl.uses_rs1  = 1'b1;
              ctrl.uses_rs2  = 1'b0;
              ctrl.rf_we     = 1'b1;
              ctrl.wb_sel    = WB_MEM;
              if (get_rs2(instr) != 5'd0) ctrl = CTRL_ILLEGAL;   // rs2 must be x0 for LR
            end
            5'h03: begin                        // SC.W rd, rs2, (rs1)
              ctrl           = CTRL_NOP;
              ctrl.is_sc     = 1'b1;
              ctrl.mem_we    = 1'b1;
              ctrl.mem_size  = MEM_W;
              ctrl.fu        = FU_MEM;
              ctrl.op_a_sel  = OP_A_RS1;
              ctrl.op_b_sel  = OP_B_IMM;        // see the LR note: IMM_NONE -> 0
              ctrl.imm_type  = IMM_NONE;
              ctrl.alu_op    = ALU_ADD;
              ctrl.uses_rs1  = 1'b1;
              ctrl.uses_rs2  = 1'b1;            // rs2 is the store data
              ctrl.rf_we     = 1'b1;
              ctrl.wb_sel    = WB_MEM;
            end
            default: ctrl = CTRL_ILLEGAL;       // Zaamo AMOs: still deferred
          endcase
        end
      end

      default: ctrl = CTRL_ILLEGAL;            // unknown opcode

    endcase
  end

endmodule
