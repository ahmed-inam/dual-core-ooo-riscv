// TWO KINDS in one class: a CLINT register access, and an.

typedef enum bit [1:0] {
  IRQ_REG_WRITE,   // program wrote a CLINT register through s0_if
  IRQ_REG_READ,    // program read one
  IRQ_DELIVERY     // msip/mtip changed at the pins
} irq_kind_e;

class irq_txn extends uvm_sequence_item;
  `uvm_object_utils(irq_txn)

  rand irq_kind_e kind;

  rand word_t addr;
  rand word_t data;

  int unsigned        hart;
  bit [NUM_HARTS-1:0] msip;         // level, all harts, at this instant
  bit [NUM_HARTS-1:0] mtip;
  bit [NUM_HARTS-1:0] msip_rise;    // edges: what actually became newly pending
  bit [NUM_HARTS-1:0] mtip_rise;
  bit [NUM_HARTS-1:0] msip_fall;    // edges: what stopped being pending
  bit [NUM_HARTS-1:0] mtip_fall;

  logic [63:0] mtime;
  logic [63:0] mtimecmp [NUM_HARTS];

  longint unsigned cycle;

  logic [63:0] retire_order;
  bit          order_known;

  function new(string name = "irq_txn");
    super.new(name);
  endfunction

  function bit is_delivery();
    return (kind == IRQ_DELIVERY) && ((msip_rise != '0) || (mtip_rise != '0)
                                      || (msip_fall != '0) || (mtip_fall != '0));
  endfunction

  virtual function void do_copy(uvm_object rhs);
    irq_txn r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal("IRQ_TXN", "do_copy: type mismatch")
    kind = r.kind; addr = r.addr; data = r.data; hart = r.hart;
    msip = r.msip; mtip = r.mtip; msip_rise = r.msip_rise; mtip_rise = r.mtip_rise;
    msip_fall = r.msip_fall; mtip_fall = r.mtip_fall;
    mtime = r.mtime;
    foreach (r.mtimecmp[i]) mtimecmp[i] = r.mtimecmp[i];
    cycle = r.cycle; retire_order = r.retire_order; order_known = r.order_known;
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    irq_txn r;
    if (!$cast(r, rhs)) return 0;
    if (kind !== r.kind) return 0;
    case (kind)
      IRQ_REG_WRITE, IRQ_REG_READ: return (addr === r.addr) && (data === r.data);
      IRQ_DELIVERY:                return (msip_rise === r.msip_rise) &&
                                          (mtip_rise === r.mtip_rise) &&
                                          (msip_fall === r.msip_fall) &&
                                          (mtip_fall === r.mtip_fall);
      default: return 0;
    endcase
  endfunction

  virtual function string convert2string();
    case (kind)
      IRQ_REG_WRITE: return $sformatf("CLINT WR [%08h] <= %08h", addr, data);
      IRQ_REG_READ:  return $sformatf("CLINT RD [%08h] => %08h", addr, data);
      IRQ_DELIVERY:  return $sformatf(
        "IRQ msip=%b mtip=%b (rise msip=%b mtip=%b fall msip=%b mtip=%b) mtime=%0d%s",
        msip, mtip, msip_rise, mtip_rise, msip_fall, mtip_fall, mtime,
        order_known ? $sformatf(" before order #%0d", retire_order) : "");
      default: return "irq_txn(?)";
    endcase
  endfunction

endclass
