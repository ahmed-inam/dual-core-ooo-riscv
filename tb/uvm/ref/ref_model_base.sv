// What sb_retire is allowed to know about a reference.
virtual class ref_model_base extends uvm_object;

  string isa = "rv32im_zicsr";

  function new(string name = "ref_model_base");
    super.new(name);
  endfunction

  pure virtual function bit  open(string image_path, int unsigned n_harts, word_t reset_pc);
  pure virtual function void close();

  pure virtual function void set_hart(int unsigned h);

  pure virtual function bit step(output rvfi_txn t);

  pure virtual function word_t get_pc();
  pure virtual function word_t get_reg(regaddr_t r);

  pure virtual function void set_pending_interrupts(int unsigned h, bit msip, bit mtip);

  virtual function void break_reservation(int unsigned h);
  endfunction

  virtual function void set_reg(int unsigned h, regaddr_t r, word_t v);
  endfunction

  virtual function void unwind_order(int unsigned h);
  endfunction

  virtual function string describe_divergence(rvfi_txn dut, rvfi_txn ref_t);
    return "";
  endfunction

endclass
