// Sequencer for the CLINT agent.
class clint_seqr extends uvm_sequencer #(irq_txn);
  `uvm_component_utils(clint_seqr)

  cpu_cfg cfg;

  uvm_tlm_analysis_fifo #(irq_txn) acc_fifo;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    acc_fifo = new("acc_fifo_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CLINT_SEQR", "no cpu_cfg")
  endfunction

endclass
