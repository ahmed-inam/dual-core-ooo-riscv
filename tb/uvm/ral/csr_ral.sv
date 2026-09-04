// [REVIEW3, exercise A] A UVM REGISTER MODEL FOR THE MACHINE CSRs.

class csr_backdoor extends uvm_reg_backdoor;
  `uvm_object_utils(csr_backdoor)

  virtual csr_probe_if probe;
  logic [11:0]         csr_addr;

  function new(string name = "csr_backdoor");
    super.new(name);
  endfunction

  virtual task read(uvm_reg_item rw);
    if (probe == null) begin
      `uvm_error("CSR_RAL", "back door has no csr_probe_if -- the model cannot be read")
      rw.status = UVM_NOT_OK;
      return;
    end
    rw.value    = new[1];
    rw.value[0] = probe.read_csr(csr_addr);
    rw.status   = UVM_IS_OK;
  endtask

  virtual task write(uvm_reg_item rw);
    `uvm_error("CSR_RAL", {"a machine CSR cannot be written through a back door. ",
                           "There is no bus behind these registers -- the only ",
                           "write path is a csrrw instruction in the program."})
    rw.status = UVM_NOT_OK;
  endtask
endclass


virtual class ral_csr_base extends uvm_reg;
  function new(string name, int unsigned n_bits, int has_cover);
    super.new(name, n_bits, has_cover);
  endfunction
  pure virtual function void build();
endclass

class ral_mstatus extends ral_csr_base;
  `uvm_object_utils(ral_mstatus)
  rand uvm_reg_field mie_f, mpie_f, mpp_f;

  function new(string name = "ral_mstatus");
    super.new(name, 32, UVM_NO_COVERAGE);
  endfunction

  virtual function void build();
    mie_f  = uvm_reg_field::type_id::create("mie");
    mpie_f = uvm_reg_field::type_id::create("mpie");
    mpp_f  = uvm_reg_field::type_id::create("mpp");
    mie_f .configure(this, 1,  3, "RW", 0, 1'b0, 1, 1, 0);
    mpie_f.configure(this, 1,  7, "RW", 0, 1'b0, 1, 1, 0);
    mpp_f .configure(this, 2, 11, "RO", 0, 2'b11, 1, 0, 0);
  endfunction
endclass

class ral_mtvec extends ral_csr_base;
  `uvm_object_utils(ral_mtvec)
  rand uvm_reg_field mode_f, base_f;
  function new(string name = "ral_mtvec"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
  virtual function void build();
    mode_f = uvm_reg_field::type_id::create("mode");
    base_f = uvm_reg_field::type_id::create("base");
    mode_f.configure(this,  2, 0, "RW", 0, 2'b0,  1, 1, 0);
    base_f.configure(this, 30, 2, "RW", 0, 30'b0, 1, 1, 0);
  endfunction
endclass

class ral_mcause extends ral_csr_base;
  `uvm_object_utils(ral_mcause)
  rand uvm_reg_field code_f, intr_f;
  function new(string name = "ral_mcause"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
  virtual function void build();
    code_f = uvm_reg_field::type_id::create("code");
    intr_f = uvm_reg_field::type_id::create("interrupt");
    code_f.configure(this, 31,  0, "RW", 0, 31'b0, 1, 1, 0);
    intr_f.configure(this,  1, 31, "RW", 0,  1'b0, 1, 1, 0);
  endfunction
endclass

class ral_word extends ral_csr_base;
  `uvm_object_utils(ral_word)
  rand uvm_reg_field val_f;
  function new(string name = "ral_word"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
  virtual function void build();
    val_f = uvm_reg_field::type_id::create("value");
    val_f.configure(this, 32, 0, "RW", 0, 32'b0, 1, 1, 0);
  endfunction
endclass

class ral_mip extends ral_csr_base;
  `uvm_object_utils(ral_mip)
  uvm_reg_field val_f;
  function new(string name = "ral_mip"); super.new(name, 32, UVM_NO_COVERAGE); endfunction
  virtual function void build();
    val_f = uvm_reg_field::type_id::create("value");
    val_f.configure(this, 32, 0, "RO", 1 /*volatile*/, 32'b0, 0 /*has_reset*/, 0, 0);
  endfunction
endclass


class csr_reg_block extends uvm_reg_block;
  `uvm_object_utils(csr_reg_block)

  rand ral_mstatus mstatus;
  rand ral_word    mie;
  rand ral_mtvec   mtvec;
  rand ral_word    mscratch;
  rand ral_word    mepc;
  rand ral_mcause  mcause;
  rand ral_mip     mip;

  function new(string name = "csr_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  protected function void add_csr(ral_csr_base r, logic [11:0] addr,
                                  virtual csr_probe_if probe, string rights);
    csr_backdoor bd = csr_backdoor::type_id::create($sformatf("bd_%03h", addr));
    bd.probe    = probe;
    bd.csr_addr = addr;
    r.configure(this, null, "");
    r.build();
    default_map.add_reg(r, addr, rights);
    r.set_backdoor(bd);
  endfunction

  virtual function void build_with(virtual csr_probe_if probe);
    default_map = create_map("csr_map", 'h0, 4, UVM_LITTLE_ENDIAN, 0);

    mstatus  = ral_mstatus::type_id::create("mstatus");
    mie      = ral_word   ::type_id::create("mie");
    mtvec    = ral_mtvec  ::type_id::create("mtvec");
    mscratch = ral_word   ::type_id::create("mscratch");
    mepc     = ral_word   ::type_id::create("mepc");
    mcause   = ral_mcause ::type_id::create("mcause");
    mip      = ral_mip    ::type_id::create("mip");

    add_csr(mstatus,  12'h300, probe, "RW");
    add_csr(mie,      12'h304, probe, "RW");
    add_csr(mtvec,    12'h305, probe, "RW");
    add_csr(mscratch, 12'h340, probe, "RW");
    add_csr(mepc,     12'h341, probe, "RW");
    add_csr(mcause,   12'h342, probe, "RW");
    add_csr(mip,      12'h344, probe, "RO");

    lock_model();
  endfunction
endclass
