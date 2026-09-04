// One retired instruction, as reported on the RVFI channel.
class rvfi_txn extends uvm_sequence_item;
  `uvm_object_utils(rvfi_txn)

  int unsigned  hart;      // which hart retired this
  int unsigned  slot;      // commit slot 0..COMMIT_W-1. Metadata, NOT compared.
  logic [63:0]  order;     // RVFI retirement counter, monotonic per hart

  word_t        insn;
  word_t        pc_rdata;

  regaddr_t     rd_addr;
  word_t        rd_wdata;

  bit           trap;

  bit           halt;
  bit           intr;
  logic [1:0]   mode;
  logic [1:0]   ixl;

  regaddr_t     rs1_addr;
  regaddr_t     rs2_addr;
  word_t        rs1_rdata;
  word_t        rs2_rdata;

  word_t        pc_wdata;

  word_t        mem_addr;
  logic [3:0]   mem_rmask;
  logic [3:0]   mem_wmask;
  word_t        mem_rdata;
  word_t        mem_wdata;

  bit           mem_rdata_known;

  longint unsigned cycle;

  function new(string name = "rvfi_txn");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    rvfi_txn r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal("RVFI_TXN", "do_copy: type mismatch")
    hart = r.hart; slot = r.slot; order = r.order;
    insn = r.insn; pc_rdata = r.pc_rdata;
    rd_addr = r.rd_addr; rd_wdata = r.rd_wdata;
    trap = r.trap; cycle = r.cycle;
    halt = r.halt; intr = r.intr; mode = r.mode; ixl = r.ixl;
    rs1_addr = r.rs1_addr; rs2_addr = r.rs2_addr;
    rs1_rdata = r.rs1_rdata; rs2_rdata = r.rs2_rdata;
    pc_wdata = r.pc_wdata;
    mem_addr = r.mem_addr; mem_rmask = r.mem_rmask; mem_wmask = r.mem_wmask;
    mem_rdata = r.mem_rdata; mem_wdata = r.mem_wdata;
    mem_rdata_known = r.mem_rdata_known;
  endfunction

  virtual function bit is_mem_read();  return (mem_rmask != 4'd0); endfunction
  virtual function bit is_mem_write(); return (mem_wmask != 4'd0); endfunction
  virtual function bit touched_mem();  return is_mem_read() || is_mem_write(); endfunction

  protected function word_t byte_expand(logic [3:0] m);
    byte_expand = { {8{m[3]}}, {8{m[2]}}, {8{m[1]}}, {8{m[0]}} };
  endfunction

  virtual function bit load_value_differs(rvfi_txn r);
    if (!is_mem_read() || !r.is_mem_read())  return 0;
    if (!mem_rdata_known || !r.mem_rdata_known) return 0;
    return ((mem_rdata & byte_expand(mem_rmask)) !==
            (r.mem_rdata & byte_expand(r.mem_rmask)));
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    rvfi_txn r;
    if (!$cast(r, rhs)) return 0;
    if (hart     !== r.hart)     return 0;
    if (order    !== r.order)    return 0;
    if (pc_rdata !== r.pc_rdata) return 0;
    if (insn     !== r.insn)     return 0;
    if (trap     !== r.trap)     return 0;
    if (rd_addr  !== r.rd_addr)  return 0;
    if (rd_addr != 0 && rd_wdata !== r.rd_wdata) return 0;
    if (!mem_matches(r)) return 0;
    if (mode     !== r.mode)     return 0;
    if (ixl      !== r.ixl)      return 0;
    if (halt     !== r.halt)     return 0;
    if (pc_wdata !== r.pc_wdata) return 0;
    return 1;
  endfunction

  virtual function bit mem_matches(rvfi_txn r, bit ignore_load_value = 0);
    if (mem_rmask !== r.mem_rmask) return 0;
    if (mem_wmask !== r.mem_wmask) return 0;
    if (touched_mem() && (mem_addr !== r.mem_addr)) return 0;
    if (is_mem_write() &&
        ((mem_wdata & byte_expand(mem_wmask)) !==
         (r.mem_wdata & byte_expand(r.mem_wmask)))) return 0;
    if (!ignore_load_value && load_value_differs(r)) return 0;
    return 1;
  endfunction

  virtual function bit differs_only_in_load_value(rvfi_txn r);
    if (hart     !== r.hart)     return 0;
    if (order    !== r.order)    return 0;
    if (pc_rdata !== r.pc_rdata) return 0;
    if (insn     !== r.insn)     return 0;
    if (trap     !== r.trap)     return 0;
    if (rd_addr  !== r.rd_addr)  return 0;
    if (mode     !== r.mode)     return 0;
    if (ixl      !== r.ixl)      return 0;
    if (halt     !== r.halt)     return 0;
    if (pc_wdata !== r.pc_wdata) return 0;
    if (!mem_matches(r, /*ignore_load_value*/ 1)) return 0;
    return (rd_addr != 0) && (rd_wdata !== r.rd_wdata);
  endfunction


  virtual function string diff_field(rvfi_txn r);
    if (hart     !== r.hart)     return $sformatf("hart %0d vs %0d", hart, r.hart);
    if (order    !== r.order)    return $sformatf("order %0d vs %0d", order, r.order);
    if (pc_rdata !== r.pc_rdata) return $sformatf("pc %08h vs %08h", pc_rdata, r.pc_rdata);
    if (insn     !== r.insn)     return $sformatf("insn %08h vs %08h", insn, r.insn);
    if (trap     !== r.trap)     return $sformatf("trap %0b vs %0b", trap, r.trap);
    if (rd_addr  !== r.rd_addr)  return $sformatf("rd_addr x%0d vs x%0d", rd_addr, r.rd_addr);
    if (rd_addr != 0 && rd_wdata !== r.rd_wdata)
      return $sformatf("rd_wdata x%0d: %08h vs %08h", rd_addr, rd_wdata, r.rd_wdata);
    if (mem_rmask !== r.mem_rmask)
      return $sformatf("mem_rmask %04b vs %04b", mem_rmask, r.mem_rmask);
    if (mem_wmask !== r.mem_wmask)
      return $sformatf("mem_wmask %04b vs %04b", mem_wmask, r.mem_wmask);
    if (touched_mem() && (mem_addr !== r.mem_addr))
      return $sformatf("mem_addr %08h vs %08h", mem_addr, r.mem_addr);
    if (is_mem_write() &&
        ((mem_wdata & byte_expand(mem_wmask)) !==
         (r.mem_wdata & byte_expand(r.mem_wmask))))
      return $sformatf("mem_wdata %08h vs %08h (lane mask %04b)",
                       mem_wdata, r.mem_wdata, mem_wmask);
    if (load_value_differs(r))
      return $sformatf("mem_rdata [%08h] %08h vs %08h (mask %04b)",
                       mem_addr, mem_rdata, r.mem_rdata, mem_rmask);
    if (mode !== r.mode) return $sformatf("mode %0d vs %0d", mode, r.mode);
    if (ixl  !== r.ixl)  return $sformatf("ixl %0d vs %0d", ixl, r.ixl);
    if (halt !== r.halt) return $sformatf("halt %0b vs %0b", halt, r.halt);
    if (pc_wdata !== r.pc_wdata)
      return $sformatf("pc_wdata %08h vs %08h", pc_wdata, r.pc_wdata);
    return "";
  endfunction

  virtual function string convert2string();
    return $sformatf("h%0d[s%0d] #%0d pc=%08h insn=%08h %s%s%s%s%s",
                     hart, slot, order, pc_rdata, insn,
                     (rd_addr == 0) ? "" : $sformatf("x%0d<=%08h ", rd_addr, rd_wdata),
                     mem_string(),
                     trap ? "TRAP" : "",
                     intr ? " INTR" : "",
                     (cycle != 0) ? $sformatf(" @cyc=%0d", cycle) : "");
  endfunction

  virtual function string mem_string();
    if (is_mem_write())
      return $sformatf("[%08h] <= %08h/%04b ", mem_addr, mem_wdata, mem_wmask);
    if (is_mem_read())
      return $sformatf("[%08h] => %08h/%04b ", mem_addr, mem_rdata, mem_rmask);
    return "";
  endfunction

endclass
