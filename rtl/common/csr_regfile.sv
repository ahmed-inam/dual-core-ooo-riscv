// Machine-mode CSRs: read at execute, written only at commit.

module csr_regfile
  import rv32i_pkg::*;
(
  input  logic       clk,
  input  logic       rst_n,

  input  word_t      hart_id_i,

  input  logic [11:0] raddr,
  output word_t       rdata,

  input  logic        commit_valid,     // a real CSR instr is retiring (not flushed/trapped)
  input  csr_op_e     commit_op,        // RW / RS / RC (NONE = not a CSR instr)
  input  logic [11:0] commit_addr,
  input  word_t       commit_operand,   // rs1 value or zero-extended uimm
  output logic        commit_illegal,   // unknown CSR, or write to a read-only CSR

  input  logic       trap_set,
  input  word_t      trap_epc,
  input  word_t      trap_cause,
  input  word_t      trap_val,
  input  logic       mret,

  input  logic       irq_timer,
  input  logic       irq_soft,
  input  logic       irq_ext,

  input  word_t      perf_rdata,        // read data for a perf address
  output logic       perf_commit_we,    // gated commit, forwarded to perf
  output csr_op_e    perf_commit_op,
  output logic[11:0] perf_commit_addr,
  output word_t      perf_commit_operand,

  output word_t      mtvec_o,           // trap vector (trap target)
  output word_t      mepc_o,            // return address (mret target)

  output word_t      mstatus_o,
  output word_t      mie_o,
  output word_t      mip_o
);

  word_t mstatus_q,  mstatus_d;
  word_t mie_q,      mie_d;
  word_t mtvec_q,    mtvec_d;
  word_t mscratch_q, mscratch_d;
  word_t mepc_q,     mepc_d;
  word_t mcause_q,   mcause_d;
  word_t mtval_q,    mtval_d;
  localparam word_t MISA    = 32'h4000_1100;  // MXL=1 (RV32), I and M
  localparam word_t MIE_IMPL = (32'd1 << IRQ_M_SOFT_BIT) | (32'd1 << IRQ_M_TIMER_BIT)
                             | (32'd1 << IRQ_M_EXT_BIT);
  localparam word_t MSTATUS_MPP_M = 32'h0000_1800;   // machine-only: MPP reads 11

  word_t mip_val;
  always_comb begin
    mip_val = '0;
    mip_val[IRQ_M_SOFT_BIT]  = irq_soft;
    mip_val[IRQ_M_TIMER_BIT] = irq_timer;
    mip_val[IRQ_M_EXT_BIT]   = irq_ext;
  end

  function automatic logic addr_known_f(logic [11:0] a);
    return csr_addr_implemented(a);
  endfunction
  function automatic logic addr_writable_f(logic [11:0] a);
    case (a)
      CSR_MSTATUS, CSR_MIE, CSR_MTVEC, CSR_MSCRATCH,
      CSR_MEPC, CSR_MCAUSE, CSR_MTVAL: addr_writable_f = 1'b1;
      default:                         addr_writable_f = 1'b0;  // mip/misa: write ignored
    endcase
  endfunction

  always_comb begin
    case (raddr)
      CSR_MSTATUS:  rdata = mstatus_q;
      CSR_MIE:      rdata = mie_q;
      CSR_MTVEC:    rdata = mtvec_q;
      CSR_MSCRATCH: rdata = mscratch_q;
      CSR_MEPC:     rdata = mepc_q;
      CSR_MCAUSE:   rdata = mcause_q;
      CSR_MTVAL:    rdata = mtval_q;
      CSR_MIP:      rdata = mip_val;
      CSR_MISA:     rdata = MISA;
      CSR_MHARTID:  rdata = hart_id_i;
      CSR_MVENDORID,
      CSR_MARCHID,
      CSR_MIMPID:   rdata = 32'd0;   // required-to-exist IDs; zero is legal
      default:      rdata = csr_is_perf(raddr) ? perf_rdata : 32'd0;
    endcase
  end

  logic commit_is_csr, commit_operand_zero, commit_we;
  assign commit_is_csr       = commit_valid && (commit_op != CSR_OP_NONE);
  assign commit_operand_zero = (commit_operand == '0);
  always_comb begin
    commit_we = commit_is_csr;
    if ((commit_op == CSR_OP_RS || commit_op == CSR_OP_RC) && commit_operand_zero)
      commit_we = 1'b0;               // RS/RC with zero operand: pure read
  end
  assign commit_illegal = commit_is_csr &&
      (!addr_known_f(commit_addr) ||
       (commit_we && (commit_addr[11:10] == 2'b11)));

  assign perf_commit_we      = commit_we && csr_is_perf(commit_addr) && !trap_set;
  assign perf_commit_op      = commit_op;
  assign perf_commit_addr    = commit_addr;
  assign perf_commit_operand = commit_operand;

  function automatic word_t warl_mepc (word_t v); warl_mepc  = {v[31:2], 2'b00}; endfunction
  function automatic word_t warl_mtvec(word_t v); warl_mtvec = {v[31:2], 2'b00}; endfunction
  function automatic word_t warl_mstatus(word_t v);
    word_t m; m = MSTATUS_MPP_M;
    m[MSTATUS_MIE_BIT]  = v[MSTATUS_MIE_BIT];
    m[MSTATUS_MPIE_BIT] = v[MSTATUS_MPIE_BIT];
    warl_mstatus = m;
  endfunction

  always_comb begin
    mstatus_d  = mstatus_q;
    mie_d      = mie_q;
    mtvec_d    = mtvec_q;
    mscratch_d = mscratch_q;
    mepc_d     = mepc_q;
    mcause_d   = mcause_q;
    mtval_d    = mtval_q;

    if (commit_we && addr_writable_f(commit_addr) && !trap_set) begin
      case (commit_addr)
        CSR_MSTATUS:  mstatus_d  = warl_mstatus(csr_next_val(mstatus_q, commit_op, commit_operand));
        CSR_MIE:      mie_d      = csr_next_val(mie_q,      commit_op, commit_operand) & MIE_IMPL;
        CSR_MTVEC:    mtvec_d    = warl_mtvec(csr_next_val(mtvec_q, commit_op, commit_operand));
        CSR_MSCRATCH: mscratch_d = csr_next_val(mscratch_q, commit_op, commit_operand);
        CSR_MEPC:     mepc_d     = warl_mepc (csr_next_val(mepc_q,  commit_op, commit_operand));
        CSR_MCAUSE:   mcause_d   = csr_next_val(mcause_q,   commit_op, commit_operand);
        CSR_MTVAL:    mtval_d    = csr_next_val(mtval_q,    commit_op, commit_operand);
        default: ;
      endcase
    end

    if (trap_set) begin
      mepc_d   = warl_mepc(trap_epc);
      mcause_d = trap_cause;
      mtval_d  = trap_val;
      mstatus_d[MSTATUS_MPIE_BIT] = mstatus_q[MSTATUS_MIE_BIT];
      mstatus_d[MSTATUS_MIE_BIT]  = 1'b0;
    end
    else if (mret) begin
      mstatus_d[MSTATUS_MIE_BIT]  = mstatus_q[MSTATUS_MPIE_BIT];
      mstatus_d[MSTATUS_MPIE_BIT] = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus_q<=MSTATUS_MPP_M; mie_q<='0; mtvec_q<='0; mscratch_q<='0;
      mepc_q<='0; mcause_q<='0; mtval_q<='0;
    end else begin
      mstatus_q<=mstatus_d; mie_q<=mie_d; mtvec_q<=mtvec_d; mscratch_q<=mscratch_d;
      mepc_q<=mepc_d; mcause_q<=mcause_d; mtval_q<=mtval_d;
    end
  end

  assign mtvec_o   = mtvec_q;
  assign mepc_o    = mepc_q;
  assign mstatus_o = mstatus_q;
  assign mie_o     = mie_q;
  assign mip_o     = mip_val;

endmodule
