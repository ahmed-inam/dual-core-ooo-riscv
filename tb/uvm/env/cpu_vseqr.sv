// Virtual sequencer: coordinates the per-interface sequencers.
class cpu_vseqr extends uvm_sequencer;
  `uvm_component_utils(cpu_vseqr)

  cpu_cfg cfg;

  mem_seqr   mem_sq;
  clint_seqr clint_sq;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CPU_VSEQR", "no cpu_cfg")
  endfunction

  function void check_connected();
    if (mem_sq == null)
      `uvm_fatal("CPU_VSEQR", "mem_sq is null: cpu_env did not connect the memory sequencer")
    if (clint_sq == null)
      `uvm_fatal("CPU_VSEQR", "clint_sq is null: cpu_env did not connect the CLINT sequencer")
  endfunction

endclass
