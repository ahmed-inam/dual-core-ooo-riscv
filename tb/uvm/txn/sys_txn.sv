// The D-request surface and starvation events.

typedef enum bit [1:0] {
  SYS_DREQ,     // any D-side request (coverage: access pattern, hart balance)
  SYS_TOHOST,   // the tohost store -- test wants to end
  SYS_STARVE    // ev_starve asserted for a hart
} sys_kind_e;

class sys_txn extends uvm_sequence_item;
  `uvm_object_utils(sys_txn)

  sys_kind_e   kind;
  int unsigned hart;

  bit    we;
  word_t addr;
  word_t wdata;

  bit [NUM_HARTS-1:0] starve_mask;

  longint unsigned cycle;

  function new(string name = "sys_txn");
    super.new(name);
  endfunction

  function bit is_illegal_tohost();
    return (kind == SYS_TOHOST) && (hart != 0);
  endfunction

  function bit is_termination();
    return (kind == SYS_TOHOST) && (wdata != 0);
  endfunction

  function int unsigned exit_code();
    return (wdata >> 1);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    sys_txn r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal("SYS_TXN", "do_copy: type mismatch")
    kind = r.kind; hart = r.hart; we = r.we; addr = r.addr; wdata = r.wdata;
    starve_mask = r.starve_mask; cycle = r.cycle;
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    sys_txn r;
    if (!$cast(r, rhs)) return 0;
    if (kind !== r.kind || hart !== r.hart) return 0;
    case (kind)
      SYS_DREQ, SYS_TOHOST: return (we === r.we) && (addr === r.addr) &&
                                   (!we || (wdata === r.wdata));
      SYS_STARVE:           return (starve_mask === r.starve_mask);
      default: return 0;
    endcase
  endfunction

  virtual function string convert2string();
    case (kind)
      SYS_DREQ:   return $sformatf("h%0d D%s [%08h]%s", hart, we ? "WR" : "RD", addr,
                                   we ? $sformatf(" <= %08h", wdata) : "");
      SYS_TOHOST: return $sformatf("h%0d TOHOST <= %08h (%s, exit=%0d)%s",
                                   hart, wdata, (wdata == 1) ? "PASS" : "FAIL",
                                   exit_code(),
                                   is_illegal_tohost() ? "  ** ILLEGAL: only hart 0 may report **" : "");
      SYS_STARVE: return $sformatf("STARVE mask=%b", starve_mask);
      default:    return "sys_txn(?)";
    endcase
  endfunction

endclass
