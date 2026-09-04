// The sequencer for the reactive memory slave.
class mem_seqr extends uvm_sequencer #(mem_txn);
  `uvm_component_utils(mem_seqr)

  cpu_cfg cfg;

  uvm_tlm_analysis_fifo #(mem_txn) req_fifo;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    req_fifo = new("req_fifo_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("MEM_SEQR", "no cpu_cfg")
  endfunction

endclass
