// Predicts every machine CSR from the retirement stream and checks the hardware against it.
`uvm_analysis_imp_decl(_csr_rvfi)
`uvm_analysis_imp_decl(_csr_irq)

class sb_csr extends uvm_scoreboard;
  `uvm_component_utils(sb_csr)

  uvm_analysis_imp_csr_rvfi #(rvfi_txn, sb_csr) rvfi_imp;
  uvm_analysis_imp_csr_irq  #(irq_txn,  sb_csr) irq_imp;

  cpu_cfg cfg;
  virtual csr_probe_if probe [];

  typedef struct {
    word_t mstatus, mie, mtvec, mscratch, mepc, mcause, mtval;
    word_t next_pc;          // pc_wdata of the last retirement: mepc for an interrupt
    bit    next_pc_known;
  } csr_state_t;
  csr_state_t st [];

  bit msip_level [];         // interrupt pins as last reported by the CLINT monitor
  bit mtip_level [];
  // An asynchronous interrupt's exact cause and mepc depend on timing the
  // retirement stream does not pin down, so mcause and mepc stop being modelled
  // from the interrupt until the next explicit csrw to them.
  bit mcause_known [];
  bit mepc_known [];

  int unsigned n_csr_insn, n_read_checked, n_read_bad, n_final_checked, n_final_bad;
  int unsigned n_traps, n_irqs, n_mrets;

  localparam word_t MSTATUS_MASK = (32'd1 << MSTATUS_MIE_BIT) | (32'd1 << MSTATUS_MPIE_BIT);
  localparam word_t MSTATUS_MPP  = 32'h0000_1800;
  localparam word_t MIE_MASK     = (32'd1 << IRQ_M_SOFT_BIT) | (32'd1 << IRQ_M_TIMER_BIT)
                                 | (32'd1 << IRQ_M_EXT_BIT);

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rvfi_imp = new("rvfi_imp", this);
    irq_imp  = new("irq_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SB_CSR", "no cpu_cfg")
    st        = new[cfg.num_harts];
    msip_level = new[cfg.num_harts];
    mtip_level = new[cfg.num_harts];
    mcause_known = new[cfg.num_harts];
    mepc_known   = new[cfg.num_harts];
    probe     = new[cfg.num_harts];
    foreach (st[h]) begin
      st[h].mstatus = MSTATUS_MPP;   // machine-only: MPP reads 11 from reset
      st[h].mie = '0; st[h].mtvec = '0; st[h].mscratch = '0;
      st[h].mepc = '0; st[h].mcause = '0; st[h].mtval = '0;
      st[h].next_pc_known = 0;
      mcause_known[h] = 1; mepc_known[h] = 1;
    end
    for (int unsigned h = 0; h < cfg.num_harts; h++)
      if (!uvm_config_db #(virtual csr_probe_if)::get(this, "", $sformatf("csr_probe_vif_%0d", h), probe[h]))
        `uvm_fatal("SB_CSR", $sformatf("no csr_probe_vif_%0d: the final compare has no back door", h))
  endfunction

  function word_t predicted(int unsigned h, logic [11:0] addr);
    case (addr)
      CSR_MSTATUS:  return st[h].mstatus;
      CSR_MIE:      return st[h].mie;
      CSR_MTVEC:    return st[h].mtvec;
      CSR_MSCRATCH: return st[h].mscratch;
      CSR_MEPC:     return st[h].mepc;
      CSR_MCAUSE:   return st[h].mcause;
      CSR_MTVAL:    return st[h].mtval;
      default:      return '0;
    endcase
  endfunction

  function bit modeled(logic [11:0] addr);
    return (addr inside {CSR_MSTATUS, CSR_MIE, CSR_MTVEC, CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL});
  endfunction

  protected function word_t warl(logic [11:0] addr, word_t v);
    case (addr)
      CSR_MSTATUS: return (v & MSTATUS_MASK) | MSTATUS_MPP;
      CSR_MIE:     return v & MIE_MASK;
      CSR_MTVEC:   return {v[31:2], 2'b00};
      CSR_MEPC:    return {v[31:2], 2'b00};
      default:     return v;
    endcase
  endfunction

  protected function void set_csr(int unsigned h, logic [11:0] addr, word_t v);
    case (addr)
      CSR_MSTATUS:  st[h].mstatus  = v;
      CSR_MIE:      st[h].mie      = v;
      CSR_MTVEC:    st[h].mtvec    = v;
      CSR_MSCRATCH: st[h].mscratch = v;
      CSR_MEPC:     st[h].mepc     = v;
      CSR_MCAUSE:   st[h].mcause   = v;
      CSR_MTVAL:    st[h].mtval    = v;
      default: ;
    endcase
  endfunction

  protected function void enter_trap(int unsigned h, word_t epc, word_t cause, word_t tval);
    st[h].mepc  = {epc[31:2], 2'b00};
    st[h].mcause = cause;
    st[h].mtval  = tval;
    st[h].mstatus[MSTATUS_MPIE_BIT] = st[h].mstatus[MSTATUS_MIE_BIT];
    st[h].mstatus[MSTATUS_MIE_BIT]  = 1'b0;
  endfunction

  protected function word_t imm_i(word_t insn);
    return {{20{insn[31]}}, insn[31:20]};
  endfunction
  protected function word_t imm_s(word_t insn);
    return {{20{insn[31]}}, insn[31:25], insn[11:7]};
  endfunction

  protected function bit misaligned(word_t addr, logic [1:0] size);
    case (size)
      2'b01: return addr[0];
      2'b10: return addr[1:0] != 2'b00;
      default: return 0;
    endcase
  endfunction

  // The synchronous cause the DUT must have raised for this retirement record.
  protected function void exception_cause(rvfi_txn t, output word_t cause, output word_t tval);
    logic [6:0] op = t.insn[6:0];
    logic [2:0] f3 = t.insn[14:12];
    word_t addr;
    cause = 32'd2; tval = '0;
    case (op)
      OPCODE_SYSTEM: begin
        if (f3 == 3'b000) begin
          if      (t.insn[31:20] == IMM12_ECALL)  cause = 32'd11;
          else if (t.insn[31:20] == IMM12_EBREAK) cause = 32'd3;
        end
      end
      OPCODE_LOAD: begin
        addr = t.rs1_rdata + imm_i(t.insn);
        if (misaligned(addr, f3[1:0])) begin cause = 32'd4; tval = addr; end
        else begin cause = 32'd5; tval = addr; end
      end
      OPCODE_STORE: begin
        addr = t.rs1_rdata + imm_s(t.insn);
        if (misaligned(addr, f3[1:0])) begin cause = 32'd6; tval = addr; end
      end
      OPCODE_BRANCH, OPCODE_JAL, OPCODE_JALR: begin
        cause = 32'd0; tval = t.pc_wdata;
      end
      default: ;
    endcase
  endfunction

  virtual function void write_csr_irq(irq_txn t);
    if (!t.is_delivery()) return;
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      msip_level[h] = t.msip[h];
      mtip_level[h] = t.mtip[h];
    end
  endfunction

  // The cause the hardware takes: the highest-priority pending AND enabled one.
  protected function word_t irq_cause(int unsigned h);
    bit sw_en = msip_level[h] && st[h].mie[IRQ_M_SOFT_BIT];
    bit tm_en = mtip_level[h] && st[h].mie[IRQ_M_TIMER_BIT];
    if (sw_en) return 32'h8000_0003;
    if (tm_en) return 32'h8000_0007;
    return msip_level[h] ? 32'h8000_0003 : 32'h8000_0007;
  endfunction

  virtual function void write_csr_rvfi(rvfi_txn t);
    int unsigned h = t.hart;
    if (h >= cfg.num_harts) return;

    // An interrupt handler starts: the interrupted pc is what was about to retire.
    if (t.intr && st[h].next_pc_known) begin
      n_irqs++;
      st[h].mstatus[MSTATUS_MPIE_BIT] = st[h].mstatus[MSTATUS_MIE_BIT];
      st[h].mstatus[MSTATUS_MIE_BIT]  = 1'b0;
      mcause_known[h] = 0; mepc_known[h] = 0;   // cause and epc not modelled for an async trap
    end

    if (t.trap) begin
      word_t cause, tval;
      exception_cause(t, cause, tval);
      n_traps++;
      enter_trap(h, t.pc_rdata, cause, tval);
      mcause_known[h] = 1; mepc_known[h] = 1;   // a synchronous cause is exact
    end
    else if (t.insn == 32'h3020_0073) begin   // mret
      n_mrets++;
      st[h].mstatus[MSTATUS_MIE_BIT]  = st[h].mstatus[MSTATUS_MPIE_BIT];
      st[h].mstatus[MSTATUS_MPIE_BIT] = 1'b1;
    end
    else if ((t.insn[6:0] == OPCODE_SYSTEM) && (t.insn[14:12] != 3'b000) && (t.insn[14:12] != 3'b100)) begin
      logic [11:0] addr = t.insn[31:20];
      logic [2:0]  f3   = t.insn[14:12];
      logic [4:0]  rs1  = t.insn[19:15];
      word_t operand = f3[2] ? word_t'(rs1) : t.rs1_rdata;
      word_t old     = predicted(h, addr);
      bit    writes  = (f3[1:0] == 2'b01) || (rs1 != 5'd0);
      n_csr_insn++;
      if (modeled(addr) && (t.rd_addr != 5'd0)
          && !(addr == CSR_MCAUSE && !mcause_known[h])
          && !(addr == CSR_MEPC   && !mepc_known[h])) begin
        n_read_checked++;
        if (t.rd_wdata !== old) begin
          n_read_bad++;
          `uvm_error("SB_CSR", $sformatf(
            "hart %0d #%0d pc=%08h csr 'h%03h read 'h%08h, the retirement stream predicts 'h%08h",
            h, t.order, t.pc_rdata, addr, t.rd_wdata, old))
          old = t.rd_wdata;   // resynchronise so one defect reports once
          set_csr(h, addr, old);
        end
      end
      if (writes && modeled(addr)) begin
        word_t nv;
        case (f3[1:0])
          2'b01:   nv = operand;
          2'b10:   nv = old | operand;
          default: nv = old & ~operand;
        endcase
        set_csr(h, addr, warl(addr, nv));
        if (addr == CSR_MCAUSE) mcause_known[h] = 1;
        if (addr == CSR_MEPC)   mepc_known[h]   = 1;
      end
    end

    st[h].next_pc = t.pc_wdata;
    st[h].next_pc_known = 1;
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      logic [11:0] addrs [$] = '{CSR_MSTATUS, CSR_MIE, CSR_MTVEC, CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL};
      if (probe[h] == null) continue;
      foreach (addrs[i]) begin
        word_t hw;
        if (addrs[i] == CSR_MCAUSE && !mcause_known[h]) continue;
        if (addrs[i] == CSR_MEPC   && !mepc_known[h])   continue;
        hw = probe[h].read_csr(addrs[i]);
        n_final_checked++;
        if (hw !== predicted(h, addrs[i])) begin
          n_final_bad++;
          `uvm_error("SB_CSR", $sformatf(
            "hart %0d csr 'h%03h holds 'h%08h at the end of the run, the retirement stream predicts 'h%08h",
            h, addrs[i], hw, predicted(h, addrs[i])))
        end
      end
    end
    if ((n_csr_insn != 0) && (n_read_checked == 0))
      `uvm_warning("SB_CSR", $sformatf(
        "%0d CSR instructions retired but none read a modelled CSR into a register: the read check never ran",
        n_csr_insn))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SB_CSR", $sformatf(
      "%0d CSR instructions, %0d reads checked (%0d bad), %0d final values checked (%0d bad); %0d traps, %0d interrupts, %0d mrets modelled",
      n_csr_insn, n_read_checked, n_read_bad, n_final_checked, n_final_bad, n_traps, n_irqs, n_mrets), UVM_LOW)
  endfunction

endclass
