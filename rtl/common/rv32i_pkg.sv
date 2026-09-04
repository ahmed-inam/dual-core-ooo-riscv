// Shared types, opcodes and encodings for the core.
`timescale 1ns/1ps

package rv32i_pkg;

  localparam int unsigned XLEN       = 32;
  localparam int unsigned REG_ADDR_W = 5;
  localparam int unsigned NUM_REGS   = 32;

  localparam logic [31:0] RESET_PC = 32'h0000_0000;

  localparam logic [31:0] POISON = 32'hBAD1_BAD1;

  typedef logic [XLEN-1:0]       word_t;
  typedef logic [REG_ADDR_W-1:0] regaddr_t;

  typedef enum logic [6:0] {
    OPCODE_LOAD     = 7'h03,
    OPCODE_MISC_MEM = 7'h0F,  // fence: NOP in a single-hart in-order core
    OPCODE_OP_IMM   = 7'h13,
    OPCODE_AUIPC    = 7'h17,
    OPCODE_AMO      = 7'h2F,  // A-ext: present ONLY to be trapped [S6]
    OPCODE_STORE    = 7'h23,
    OPCODE_OP       = 7'h33,
    OPCODE_LUI      = 7'h37,
    OPCODE_BRANCH   = 7'h63,
    OPCODE_JALR     = 7'h67,
    OPCODE_JAL      = 7'h6F,
    OPCODE_SYSTEM   = 7'h73
  } opcode_e;

  localparam logic [2:0] F3_LB  = 3'b000, F3_LH  = 3'b001, F3_LW = 3'b010,
                         F3_LBU = 3'b100, F3_LHU = 3'b101;
  localparam logic [2:0] F3_SB = 3'b000, F3_SH = 3'b001, F3_SW = 3'b010;

  localparam logic [2:0] F3_ADD_SUB = 3'b000,   // OP-IMM: addi (no sub form)
                         F3_SLL     = 3'b001,
                         F3_SLT     = 3'b010,
                         F3_SLTU    = 3'b011,
                         F3_XOR     = 3'b100,
                         F3_SRL_SRA = 3'b101,
                         F3_OR      = 3'b110,
                         F3_AND     = 3'b111;

  localparam logic [6:0] F7_BASE = 7'b000_0000,  // add, srl, srli
                         F7_ALT  = 7'b010_0000,  // sub, sra, srai
                         F7_MULD = 7'b000_0001;  // mul/div family

  localparam int unsigned ALT_OP_BIT = 30;

  localparam logic [2:0] F3_BEQ  = 3'b000, F3_BNE  = 3'b001,
                         F3_BLT  = 3'b100, F3_BGE  = 3'b101,
                         F3_BLTU = 3'b110, F3_BGEU = 3'b111;

  localparam logic [2:0] F3_PRIV   = 3'b000,
                         F3_CSRRW  = 3'b001, F3_CSRRS  = 3'b010, F3_CSRRC  = 3'b011,
                         F3_CSRRWI = 3'b101, F3_CSRRSI = 3'b110, F3_CSRRCI = 3'b111;

  localparam logic [11:0] IMM12_ECALL  = 12'h000,
                          IMM12_EBREAK = 12'h001,
                          IMM12_MRET   = 12'h302,
                          IMM12_WFI    = 12'h105;  // decode as NOP [S2]

  localparam logic [2:0] F3_FENCE = 3'b000, F3_FENCE_I = 3'b001;

  typedef enum logic [3:0] {
    ALU_ADD  = 4'd0,
    ALU_SUB  = 4'd1,
    ALU_SLL  = 4'd2,
    ALU_SLT  = 4'd3,   // signed compare   -> result 0/1
    ALU_SLTU = 4'd4,   // unsigned compare -> result 0/1
    ALU_XOR  = 4'd5,
    ALU_SRL  = 4'd6,
    ALU_SRA  = 4'd7,
    ALU_OR   = 4'd8,
    ALU_AND  = 4'd9,
    ALU_EQ   = 4'd10,  // beq
    ALU_NE   = 4'd11,  // bne
    ALU_LT   = 4'd12,  // blt   signed
    ALU_GE   = 4'd13,  // bge   signed
    ALU_LTU  = 4'd14,  // bltu  unsigned
    ALU_GEU  = 4'd15   // bgeu  unsigned
  } alu_op_e;

  typedef enum logic [1:0] {
    OP_A_RS1  = 2'd0,
    OP_A_PC   = 2'd1,   // auipc, and branch/jal target computation
    OP_A_ZERO = 2'd2    // lui  (0 + immU)
  } op_a_sel_e;

  typedef enum logic {
    OP_B_RS2 = 1'b0,
    OP_B_IMM = 1'b1
  } op_b_sel_e;

  typedef enum logic [2:0] {
    IMM_NONE = 3'd0,    // R-type consumes no immediate
    IMM_I    = 3'd1,
    IMM_S    = 3'd2,
    IMM_B    = 3'd3,
    IMM_U    = 3'd4,
    IMM_J    = 3'd5
  } imm_type_e;

  typedef enum logic [2:0] {
    WB_ALU = 3'd0,
    WB_MEM = 3'd1,
    WB_PC4 = 3'd2,      // jal / jalr link value
    WB_CSR = 3'd3,      // csrr* old value
    WB_MUL = 3'd4       // mul-family result. The multiplier is a
  } wb_sel_e;

  typedef enum logic [2:0] {
    M_MUL    = 3'b000,  // low 32 of a*b       (sign bits: don't care)
    M_MULH   = 3'b001,  // high 32, signed x signed
    M_MULHSU = 3'b010,  // high 32, signed x unsigned
    M_MULHU  = 3'b011,  // high 32, unsigned x unsigned
    M_DIV    = 3'b100,
    M_DIVU   = 3'b101,
    M_REM    = 3'b110,
    M_REMU   = 3'b111
  } m_op_e;

  typedef enum logic [2:0] {
    MEM_B    = 3'd0,
    MEM_H    = 3'd1,
    MEM_W    = 3'd2,
    MEM_BU   = 3'd3,
    MEM_HU   = 3'd4,
    MEM_NONE = 3'd7
  } mem_size_e;

  typedef enum logic [1:0] {
    FWD_NONE  = 2'd0,   // register-file read (no hazard)
    FWD_EXMEM = 2'd1,   // bypass EX/MEM (younger producer)
    FWD_MEMWB = 2'd2    // bypass MEM/WB (older producer)
  } fwd_sel_e;

  typedef enum logic [1:0] {
    CF_NONE   = 2'd0,
    CF_BRANCH = 2'd1,   // conditional, target = PC + immB
    CF_JAL    = 2'd2,   // unconditional, target = PC + immJ
    CF_JALR   = 2'd3    // unconditional, target = (rs1 + immI) & ~32'h1
  } cf_type_e;

  typedef enum logic [1:0] {
    RDR_SEQ     = 2'd0,  // PC + 4
    RDR_PREDICT = 2'd1,  // [S3] speculative target from bp_top
    RDR_RESOLVE = 2'd2,  // branch/jump resolution, or mispredict repair
    RDR_TRAP    = 2'd3   // highest: mtvec entry, or mepc on mret
  } redirect_src_e;

  typedef struct packed {
    logic          valid;
    redirect_src_e src;
    word_t         target;
  } redirect_t;

  typedef enum logic [1:0] {
    CSR_OP_NONE = 2'd0,
    CSR_OP_RW   = 2'd1,
    CSR_OP_RS   = 2'd2,
    CSR_OP_RC   = 2'd3
  } csr_op_e;

  typedef enum logic [11:0] {
    CSR_MSTATUS  = 12'h300,
    CSR_MISA     = 12'h301,
    CSR_MENVCFG  = 12'h30A,   // read-only zero
    CSR_MSTATUSH = 12'h310,   // read-only zero
    CSR_MENVCFGH = 12'h31A,   // read-only zero
    CSR_MCOUNTINHIBIT = 12'h320,   // read-only zero: counters always run
    CSR_MIE      = 12'h304,
    CSR_MTVEC    = 12'h305,
    CSR_MSCRATCH = 12'h340,
    CSR_MEPC     = 12'h341,
    CSR_MCAUSE   = 12'h342,
    CSR_MTVAL    = 12'h343,
    CSR_MIP      = 12'h344,
    CSR_MCYCLE    = 12'hB00,  // cycles (free-running)
    CSR_MINSTRET  = 12'hB02,  // instructions retired
    CSR_MHPM3     = 12'hB03,  // branches resolved
    CSR_MHPM4     = 12'hB04,  // branch mispredicts
    CSR_MHPM5     = 12'hB05,  // stall cycles
    CSR_MHPM6     = 12'hB06,  // flush cycles
    CSR_MHPM7     = 12'hB07,  // I-cache misses
    CSR_MHPM8     = 12'hB08,  // D-cache misses
    CSR_MHPM9     = 12'hB09,  // D-cache writebacks
    CSR_MHPM10    = 12'hB0A,  // memory stall cycles
    CSR_MCYCLEH   = 12'hB80,
    CSR_MINSTRETH = 12'hB82,
    CSR_MHPM3H    = 12'hB83,
    CSR_MHPM4H    = 12'hB84,
    CSR_MHPM5H    = 12'hB85,
    CSR_MHPM6H    = 12'hB86,
    CSR_MHPM7H    = 12'hB87,
    CSR_MHPM8H    = 12'hB88,
    CSR_MHPM9H    = 12'hB89,
    CSR_MHPM10H   = 12'hB8A,
    CSR_CYCLE     = 12'hC00,
    CSR_TIME      = 12'hC01,  // no mtime reaches the core: reads mcycle
    CSR_INSTRET   = 12'hC02,
    CSR_CYCLEH    = 12'hC80,
    CSR_TIMEH     = 12'hC81,
    CSR_INSTRETH  = 12'hC82,
    CSR_MVENDORID= 12'hF11,   // required to exist; 0 = non-commercial
    CSR_MARCHID  = 12'hF12,   // 0 = not registered
    CSR_MIMPID   = 12'hF13,   // 0 = not versioned
    CSR_MHARTID  = 12'hF14,   // [S6] core id within the cluster
    CSR_MCONFIGPTR = 12'hF15  // required to exist, reads 0
  } csr_addr_e;

  localparam int unsigned MSTATUS_MIE_BIT  = 3;
  localparam int unsigned MSTATUS_MPIE_BIT = 7;

  localparam int unsigned IRQ_M_SOFT_BIT  = 3;
  localparam int unsigned IRQ_M_TIMER_BIT = 7;
  localparam int unsigned IRQ_M_EXT_BIT   = 11;

  typedef enum logic [4:0] {
    EXC_INSTR_MISALIGNED = 5'd0,
    EXC_INSTR_FAULT      = 5'd1,
    EXC_ILLEGAL_INSTR    = 5'd2,
    EXC_BREAKPOINT       = 5'd3,
    EXC_LOAD_MISALIGNED  = 5'd4,
    EXC_LOAD_FAULT       = 5'd5,
    EXC_STORE_MISALIGNED = 5'd6,
    EXC_STORE_FAULT      = 5'd7,
    EXC_ECALL_U          = 5'd8,
    EXC_ECALL_M          = 5'd11
  } exc_cause_e;

  typedef enum logic [4:0] {
    IRQ_M_SOFT  = 5'd3,
    IRQ_M_TIMER = 5'd7,
    IRQ_M_EXT   = 5'd11
  } irq_cause_e;

  localparam int unsigned MCAUSE_IRQ_BIT = XLEN-1;

  typedef enum logic [1:0] {
    FU_ALU = 2'd0,
    FU_MEM = 2'd1,
    FU_CSR = 2'd2,
    FU_MUL = 2'd3    // M-ext hook [optional]
  } fu_e;

  typedef struct packed {
    alu_op_e    alu_op;
    op_a_sel_e  op_a_sel;
    op_b_sel_e  op_b_sel;
    imm_type_e  imm_type;
    fu_e        fu;          // [S5] dispatch target

    logic       rf_we;
    logic       uses_rs1;    // operand liveness: hazard/forward [S2], rename [S5]
    logic       uses_rs2;

    logic       mem_re;
    logic       mem_we;
    mem_size_e  mem_size;

    cf_type_e   cf_type;

    wb_sel_e    wb_sel;

    csr_op_e    csr_op;
    logic       csr_use_imm; // csrr*i forms use zero-extended uimm[4:0]
    logic       is_ecall;
    logic       is_ebreak;
    logic       is_mret;
    logic       is_lr;
    logic       is_sc;
    logic       is_fence;    // FENCE: writeback every dirty D line
    logic       is_fence_i;  // FENCE.I: invalidate the whole I-cache

    logic       late_result;

    logic       is_m;
    m_op_e      m_op;

    logic       illegal;
  } ctrl_t;

  localparam ctrl_t CTRL_NOP = '{
    alu_op:      ALU_ADD,
    op_a_sel:    OP_A_RS1,
    op_b_sel:    OP_B_IMM,
    imm_type:    IMM_NONE,
    fu:          FU_ALU,
    rf_we:       1'b0,
    uses_rs1:    1'b0,
    uses_rs2:    1'b0,
    mem_re:      1'b0,
    mem_we:      1'b0,
    mem_size:    MEM_NONE,
    cf_type:     CF_NONE,
    wb_sel:      WB_ALU,
    csr_op:      CSR_OP_NONE,
    csr_use_imm: 1'b0,
    is_ecall:    1'b0,
    is_ebreak:   1'b0,
    is_mret:     1'b0,
    is_lr: 1'b0, is_sc: 1'b0, is_fence:    1'b0,
    is_fence_i:  1'b0,
    late_result: 1'b0,
    is_m:        1'b0,
    m_op:        M_MUL,
    illegal:     1'b0
  };

  localparam ctrl_t CTRL_ILLEGAL = '{
    alu_op:      ALU_ADD,
    op_a_sel:    OP_A_RS1,
    op_b_sel:    OP_B_IMM,
    imm_type:    IMM_NONE,
    fu:          FU_ALU,
    rf_we:       1'b0,
    uses_rs1:    1'b0,
    uses_rs2:    1'b0,
    mem_re:      1'b0,
    mem_we:      1'b0,
    mem_size:    MEM_NONE,
    cf_type:     CF_NONE,
    wb_sel:      WB_ALU,
    csr_op:      CSR_OP_NONE,
    csr_use_imm: 1'b0,
    is_ecall:    1'b0,
    is_ebreak:   1'b0,
    is_mret:     1'b0,
    is_lr: 1'b0, is_sc: 1'b0, is_fence:    1'b0,
    is_fence_i:  1'b0,
    late_result: 1'b0,
    is_m:        1'b0,
    m_op:        M_MUL,
    illegal:     1'b1
  };


  typedef struct packed {          // I-type: addi, lw, jalr, csrr*
    logic [11:0] imm;              // imm[11:0]
    regaddr_t    rs1;
    logic [2:0]  funct3;
    regaddr_t    rd;
    logic [6:0]  opcode;
  } instr_i_t;





  function automatic logic [6:0]  get_opcode (word_t i); return i[6:0];         endfunction
  function automatic regaddr_t    get_rd     (word_t i); return i[11:7];        endfunction
  function automatic logic [2:0]  get_funct3 (word_t i); return i[14:12];       endfunction
  function automatic regaddr_t    get_rs1    (word_t i); return i[19:15];       endfunction
  function automatic regaddr_t    get_rs2    (word_t i); return i[24:20];       endfunction
  function automatic logic [6:0]  get_funct7 (word_t i); return i[31:25];       endfunction
  function automatic logic [11:0] get_imm12  (word_t i); return i[31:20];       endfunction
  function automatic logic [4:0]  get_shamt  (word_t i); return i[24:20];       endfunction
  function automatic logic [4:0]  get_uimm   (word_t i); return i[19:15];       endfunction
  function automatic logic        get_alt_op (word_t i); return i[ALT_OP_BIT];  endfunction

  localparam int unsigned GHR_W       = 10;              // global history bits
  localparam int unsigned PHT_ENTRIES = 1 << GHR_W;      // 1024 x 2-bit counters
  localparam int unsigned BTB_IDX_W   = 6;               // 64-entry direct-mapped
  localparam int unsigned BTB_ENTRIES = 1 << BTB_IDX_W;
  localparam int unsigned RAS_DEPTH   = 8;
  localparam int unsigned RAS_IDX_W   = 3;               // == $clog2(RAS_DEPTH)
  localparam int unsigned RAS_PTR_W   = 4;               // count 0..8
  localparam int unsigned RAS_OVF_W   = 6;

  typedef logic [GHR_W-1:0]     ghr_t;
  typedef logic [RAS_PTR_W-1:0] ras_ptr_t;   // occupancy count; index = [RAS_IDX_W-1:0]
  typedef logic [RAS_OVF_W-1:0] ras_ovf_t;

  localparam int unsigned BTB_TAG_W = XLEN - 2 - BTB_IDX_W;
  typedef logic [BTB_TAG_W-1:0] btb_tag_t;

  typedef enum logic [1:0] {
    BTB_BRANCH = 2'd0,   // conditional: direction from gshare, target from BTB
    BTB_JAL    = 2'd1,   // unconditional: always taken, target from BTB
    BTB_JALR   = 2'd2,   // unconditional, non-return: taken, LAST target from
    BTB_RET    = 2'd3    // unconditional: taken, target from RAS top
  } btb_class_e;

  function automatic logic bp_is_link (regaddr_t r);
    return (r == 5'd1) || (r == 5'd5);
  endfunction
  function automatic logic bp_is_call (cf_type_e cf, regaddr_t rd);
    return (cf == CF_JAL || cf == CF_JALR) && bp_is_link(rd);
  endfunction
  function automatic logic bp_is_ret (cf_type_e cf, regaddr_t rd, regaddr_t rs1);
    return (cf == CF_JALR) && bp_is_link(rs1) && (rd != rs1);
  endfunction

  typedef struct packed {
    ghr_t     ghr;
    ras_ptr_t ras_tos;
    ras_ovf_t ras_ovf;
    logic [1:0] pht_ctr;
  } bp_snapshot_t;

  typedef struct packed {
    logic         taken;      // redirect fetch to `target` this cycle
    word_t        target;     // predicted target (RAS top for BTB_RET)
    logic         btb_hit;    // a BTB entry claimed this PC is a CF
    btb_class_e   btb_class;  // what kind, if btb_hit
    logic         dir_taken;  // gshare's raw direction (train even on miss)
    bp_snapshot_t snapshot;   // pre-mutation checkpoint, rides to E
  } bp_pred_t;

  localparam bp_pred_t BP_PRED_NONE = '{
    taken:     1'b0,
    target:    '0,
    btb_hit:   1'b0,
    btb_class: BTB_BRANCH,
    dir_taken: 1'b0,
    snapshot:  '0
  };

  typedef struct packed {
    logic         valid;       // a real CF instruction resolved in E
    word_t        pc;          // its PC (indexes every table)
    cf_type_e     cf_type;     // BRANCH / JAL / JALR
    logic         call;        // bp_is_call() of its register fields
    logic         ret;         // bp_is_ret()  of its register fields
    logic         taken;       // ACTUAL direction (1 for jal/jalr always)
    word_t        target;      // ACTUAL target
    logic         mispredict;  // direction or target differed from prediction
    bp_pred_t     pred;        // what F predicted for this instruction
  } bp_update_t;

  localparam bp_update_t BP_UPDATE_NONE = '{
    valid:      1'b0,
    pc:         '0,
    cf_type:    CF_NONE,
    call:       1'b0,
    ret:        1'b0,
    taken:      1'b0,
    target:     '0,
    mispredict: 1'b0,
    pred:       BP_PRED_NONE
  };



  typedef struct packed {
    logic  valid;      // 0 = bubble (flush injects a zeroed payload); trap commit [S2]
    word_t pc;         // auipc/branch base (E) AND WB_PC4 link via pc+4 (W); rides all four
    word_t instr;      // consumed in D (decode/slices/imm_gen); stops here
    bp_pred_t bp;
  } if_id_t;

  typedef struct packed {
    logic        valid;     // 0 = bubble; propagated from if_id [S2]
    word_t       pc;        // auipc/branch base (E) AND WB_PC4 link via pc+4 (W); to W
    word_t       instr;     // raw instruction word, pure payload:
    word_t       rs1_data;  // op_a / branch reg / csr operand; last used at E
    word_t       rs2_data;  // op_b (E) AND store data (M); rides to M
    word_t       imm;       // op_b / target adder; last used at E
    regaddr_t    rd_addr;   // regfile write target; rides to W
    regaddr_t    rs1_addr;  // forwarding compare key [S2]; last used at E
    regaddr_t    rs2_addr;  // forwarding compare key [S2]; last used at E
    logic [11:0] csr_addr;  // CSR read (E) + write (W) target; rides to W
    bp_pred_t    bp;        // [S3] prediction from F; CONSUMED AT E, where
    ctrl_t       ctrl;      // full bundle; fields peel off as consumed
  } id_ex_t;

  typedef struct packed {
    logic        valid;      // 0 = bubble; propagated from id_ex [S2]
    word_t       instr;      // payload only; rides to W for the trace
    word_t       alu_result; // WB_ALU + dmem address (M) + forward source; to W
    word_t       csr_rdata;  // WB_CSR old value; to W
    word_t       csr_wdata;  // precomputed CSR write payload; to W
    word_t       pc;         // carried for the WB_PC4 link (pc+4 formed in W); to W
    word_t       rs2_data;   // store data; last used at M
    regaddr_t    rs2_addr;   // store-data forward key: M-stage bypass compares
    regaddr_t    rd_addr;    // regfile write target; to W
    logic [11:0] csr_addr;   // CSR write target; to W
    logic        exc_instr_mis; // taken CF target not 4-aligned (born in E,
    bp_snapshot_t snapshot;  // [S3] frontend state before THIS instruction
    ctrl_t       ctrl;       // mem_* consumed at M; wb_sel/rf_we/csr_op ride to W
  } ex_mem_t;

  typedef struct packed {
    logic        valid;      // 0 = bubble; commit_valid for trap/retire [S2]
    word_t       instr;      // payload only; reported as rvfi_insn
    word_t       alu_result; // WB_ALU
    word_t       csr_rdata;  // WB_CSR
    word_t       csr_wdata;  // CSR write payload (committed here)
    word_t       load_data;  // WB_MEM
    word_t       pc;         // WB_PC4 link = pc + 4, formed by the writeback mux here in W
    regaddr_t    rd_addr;    // regfile write target
    logic [11:0] csr_addr;   // CSR write target
    logic        exc_instr_mis;  // born in E (branch_unit), rode through EX/MEM
    logic        exc_load_mis;   // born in M (lsu)
    logic        exc_store_mis;  // born in M (lsu); the store's dmem write was
    bp_snapshot_t snapshot;  // [S3] see ex_mem_t: consumed by bp_top on a trap
    ctrl_t       ctrl;       // wb_sel picks the source; rf_we/csr_op gate commit
  } mem_wb_t;


  function automatic logic csr_is_perf (logic [11:0] a);
    case (a)
      CSR_MCYCLE,  CSR_MINSTRET,  CSR_MHPM3,  CSR_MHPM4,  CSR_MHPM5,  CSR_MHPM6,
      CSR_MCYCLEH, CSR_MINSTRETH, CSR_MHPM3H, CSR_MHPM4H, CSR_MHPM5H, CSR_MHPM6H,
      CSR_MHPM7,   CSR_MHPM8,     CSR_MHPM9,  CSR_MHPM10,
      CSR_MHPM7H,  CSR_MHPM8H,    CSR_MHPM9H, CSR_MHPM10H,
      CSR_CYCLE,   CSR_INSTRET,   CSR_CYCLEH, CSR_INSTRETH,
      CSR_TIME,    CSR_TIMEH:
        csr_is_perf = 1'b1;
      default:
        csr_is_perf = 1'b0;
    endcase
  endfunction

  // CSRs the spec requires to exist that this core implements as read-only zero:
  // mhpmevent3-31, mhpmcounter11-31 with their high halves, and the four above.
  function automatic logic csr_is_zero_stub (logic [11:0] a);
    case (a)
      CSR_MENVCFG, CSR_MSTATUSH, CSR_MENVCFGH, CSR_MCOUNTINHIBIT, CSR_MCONFIGPTR:
        csr_is_zero_stub = 1'b1;
      default:
        csr_is_zero_stub = (a >= 12'h323 && a <= 12'h33F)
                        || (a >= 12'hB0B && a <= 12'hB1F)
                        || (a >= 12'hB8B && a <= 12'hB9F);
    endcase
  endfunction

  function automatic logic csr_addr_implemented (logic [11:0] a);
    case (a)
      CSR_MSTATUS, CSR_MISA, CSR_MIE, CSR_MTVEC, CSR_MSCRATCH, CSR_MEPC,
      CSR_MCAUSE, CSR_MTVAL, CSR_MIP, CSR_MHARTID,
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID: csr_addr_implemented = 1'b1;
      default: csr_addr_implemented = csr_is_perf(a) || csr_is_zero_stub(a);
    endcase
  endfunction

  function automatic word_t csr_next_val (word_t old, csr_op_e op, word_t operand);
    case (op)
      CSR_OP_RW: csr_next_val = operand;
      CSR_OP_RS: csr_next_val = old |  operand;
      CSR_OP_RC: csr_next_val = old & ~operand;
      default:   csr_next_val = old;
    endcase
  endfunction

endpackage : rv32i_pkg
