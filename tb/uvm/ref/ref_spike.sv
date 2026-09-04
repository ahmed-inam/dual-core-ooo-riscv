// Ref_model_base implemented against Spike, via DPI-C.

import "DPI-C" function int      spike_open(input string image_path,
                                            input string isa,
                                            input int    n_harts,
                                            input longint unsigned reset_pc);
import "DPI-C" function void     spike_close();
import "DPI-C" function int      spike_step(input int hart);
import "DPI-C" function longint unsigned spike_get_pc(input int hart);
import "DPI-C" function longint unsigned spike_get_reg(input int hart, input int idx);
import "DPI-C" function longint unsigned spike_get_insn(input int hart);
import "DPI-C" function int      spike_get_rd(input int hart);
import "DPI-C" function int      spike_trapped(input int hart);
import "DPI-C" function void     spike_set_mip(input int hart, input int msip, input int mtip);
import "DPI-C" function void     spike_break_reservation(input int hart);
import "DPI-C" function longint unsigned spike_get_pc_wdata(input int hart);
import "DPI-C" function int      spike_mem_r_valid(input int hart);
import "DPI-C" function longint unsigned spike_mem_r_addr(input int hart);
import "DPI-C" function int      spike_mem_r_len(input int hart);
import "DPI-C" function int      spike_mem_r_data_ok(input int hart);
import "DPI-C" function longint unsigned spike_mem_r_data(input int hart);
import "DPI-C" function int      spike_mem_w_valid(input int hart);
import "DPI-C" function longint unsigned spike_mem_w_addr(input int hart);
import "DPI-C" function int      spike_mem_w_len(input int hart);
import "DPI-C" function longint unsigned spike_mem_w_data(input int hart);
import "DPI-C" function int      spike_mem_extra(input int hart);

import "DPI-C" function void     spike_set_reg(input int hart, input int idx,
                                               input longint unsigned value);

class ref_spike extends ref_model_base;
  `uvm_object_utils(ref_spike)

  protected int unsigned cur_hart;
  protected int unsigned n_harts;
  protected bit          is_open;

  protected logic [63:0] order_q [];

  function new(string name = "ref_spike");
    super.new(name);
  endfunction

  virtual function bit open(string image_path, int unsigned n, word_t reset_pc);
    n_harts = n;
    order_q = new[n];
    foreach (order_q[i]) order_q[i] = '0;

    `uvm_info("REF_SPIKE", $sformatf("opening reference: isa=%s harts=%0d image=%s",
                                     isa, n, image_path), UVM_LOW)
    is_open = (spike_open(image_path, isa, int'(n), {32'b0, reset_pc}) != 0);

    if (!is_open)
      `uvm_error("REF_SPIKE", $sformatf(
        "spike_open failed for '%s' -- check the image exists and spike_dpi.cc is linked",
        image_path))
    return is_open;
  endfunction

  virtual function void close();
    if (is_open) spike_close();
    is_open = 0;
  endfunction

  virtual function void set_hart(int unsigned h);
    if (h >= n_harts)
      `uvm_fatal("REF_SPIKE", $sformatf("set_hart(%0d) with only %0d harts", h, n_harts))
    cur_hart = h;
  endfunction

  virtual function bit step(output rvfi_txn t);
    int retired;

    t = null;
    if (!is_open) begin
      `uvm_error("REF_SPIKE", "step() before a successful open()")
      return 0;
    end

    retired = spike_step(int'(cur_hart));

    if (retired != 1) begin
      `uvm_error("REF_SPIKE", $sformatf(
        "hart %0d did not retire (spike_step returned %0d) at pc=%08h",
        cur_hart, retired, get_pc()))
      return 0;
    end

    t          = rvfi_txn::type_id::create("ref_t");
    t.hart     = cur_hart;
    t.slot     = 0;                    // metadata; never compared
    t.order    = order_q[cur_hart];
    t.pc_rdata = word_t'(spike_get_pc(int'(cur_hart)));
    t.insn     = word_t'(spike_get_insn(int'(cur_hart)));
    t.rd_addr  = regaddr_t'(spike_get_rd(int'(cur_hart)));
    t.rd_wdata = (t.rd_addr == 0) ? '0
                                  : word_t'(spike_get_reg(int'(cur_hart), int'(t.rd_addr)));
    t.trap     = (spike_trapped(int'(cur_hart)) != 0);
    t.cycle    = 0;                    // the reference has no notion of cycles

    t.mode = 2'd3;
    t.ixl  = 2'd1;
    t.halt = 1'b0;

    t.pc_wdata = word_t'(spike_get_pc_wdata(int'(cur_hart)));


    capture_mem(t);

    order_q[cur_hart] = order_q[cur_hart] + 1;
    return 1;
  endfunction

  protected function void capture_mem(rvfi_txn t);
    int unsigned h = cur_hart;
    word_t       a;
    int          len;

    if (spike_mem_extra(int'(h)) != 0)
      `uvm_warning("REF_SPIKE", $sformatf(
        {"hart %0d retired an instruction making %0d memory access(es) beyond ",
         "the first at pc=%08h. RV32IM has no such instruction, so the extra ",
         "entries are NOT in the transaction and this is a finding about the ",
         "reference, not a threshold to raise."},
        h, spike_mem_extra(int'(h)), t.pc_rdata))

    if (spike_mem_r_valid(int'(h)) != 0) begin
      a   = word_t'(spike_mem_r_addr(int'(h)));
      len = spike_mem_r_len(int'(h));
      t.mem_addr  = a;
      t.mem_rmask = lane_mask(len, a[1:0]);
      if (spike_mem_r_data_ok(int'(h)) != 0) begin
        t.mem_rdata       = word_t'(spike_mem_r_data(int'(h)));
        t.mem_rdata_known = 1;
      end
      else begin
        t.mem_rdata_known = 0;
        `uvm_info("REF_SPIKE", $sformatf(
          {"hart %0d load at pc=%08h reads %08h, which is not backed memory in ",
           "the reference (MMIO or unmapped). Its VALUE cannot be checked; the ",
           "address and width still can."}, h, t.pc_rdata, a), UVM_HIGH)
      end
    end
    else begin
      t.mem_rdata_known = 0;
    end

    if (spike_mem_w_valid(int'(h)) != 0) begin
      a   = word_t'(spike_mem_w_addr(int'(h)));
      len = spike_mem_w_len(int'(h));
      t.mem_addr  = a;
      t.mem_wmask = lane_mask(len, a[1:0]);
      t.mem_wdata = word_t'(spike_mem_w_data(int'(h)) << {a[1:0], 3'b000});
    end
  endfunction

  protected function logic [3:0] lane_mask(int len, logic [1:0] lo);
    logic [3:0] m;
    logic [3:0] r;
    case (len)
      1:       m = 4'b0001;
      2:       m = 4'b0011;
      default: m = 4'b1111;
    endcase
    r = m << lo;
    return r;
  endfunction

  virtual function word_t get_pc();
    return word_t'(spike_get_pc(int'(cur_hart)));
  endfunction

  virtual function word_t get_reg(regaddr_t r);
    return (r == 0) ? '0 : word_t'(spike_get_reg(int'(cur_hart), int'(r)));
  endfunction

  virtual function void set_pending_interrupts(int unsigned h, bit msip, bit mtip);
    spike_set_mip(int'(h), int'(msip), int'(mtip));
  endfunction

  virtual function void break_reservation(int unsigned h);
    spike_break_reservation(int'(h));
  endfunction

  virtual function void set_reg(int unsigned h, regaddr_t r, word_t v);
    spike_set_reg(int'(h), int'(r), {32'b0, v});
  endfunction

  virtual function void unwind_order(int unsigned h);
    if (order_q[h] != 0) order_q[h] = order_q[h] - 1;
  endfunction

  virtual function string describe_divergence(rvfi_txn dut, rvfi_txn ref_t);
    string s;
    s = $sformatf("hart %0d diverged at order #%0d\n", dut.hart, dut.order);
    s = {s, $sformatf("  DUT : %s\n", dut.convert2string())};
    s = {s, $sformatf("  REF : %s\n", ref_t.convert2string())};
    s = {s, $sformatf("  first differing field: %s\n", ref_t.diff_field(dut))};
    s = {s, $sformatf("  reference pc now %08h\n", get_pc())};
    if (dut.rd_addr != 0)
      s = {s, $sformatf("  x%0d: DUT %08h  REF %08h\n",
                        dut.rd_addr, dut.rd_wdata, get_reg(dut.rd_addr))};
    return s;
  endfunction

endclass
