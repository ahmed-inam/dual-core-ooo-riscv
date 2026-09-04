// The testbench package: includes every class in dependency order.
`ifndef CPU_TB_PKG_SV
`define CPU_TB_PKG_SV

package cpu_tb_pkg;

  import rv32i_pkg::*;
  import platform_cfg_pkg::*;   // NUM_HARTS
  import core_cfg_pkg::*;       // COMMIT_W
  import ooo_pkg::*;
  import mem_pkg::*;            // CLINT_BASE, RAM_BASE
  import coreaxi_pkg::*;
  import coherence_pkg::*;      // coh_req_e, coh_snoop_e, coh_rsp_e, coh_trans_e

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "cpu_cfg.sv"

  `include "rvfi_txn.sv"
  `include "mem_txn.sv"
  `include "snoop_txn.sv"
  `include "irq_txn.sv"
  `include "sys_txn.sv"

  `include "ref_model_base.sv"
  `include "ref_spike.sv"

  `include "rvfi_monitor.sv"
  `include "rvfi_agent.sv"

  `include "mem_seqr.sv"
  `include "mem_driver.sv"
  `include "mem_monitor.sv"
  `include "mem_agent.sv"

  `include "snoop_monitor.sv"
  `include "snoop_agent.sv"

  `include "clint_seqr.sv"
  `include "clint_driver.sv"
  `include "clint_monitor.sv"
  `include "clint_agent.sv"

  `include "sys_monitor.sv"
  `include "sys_agent.sv"

  `include "sb_retire.sv"
  `include "sb_coherence.sv"
  `include "sb_csr.sv"

  `include "cov_core.sv"
  `include "cov_coherence.sv"
  `include "cov_lrsc.sv"
  `include "cov_isa.sv"

  `include "cpu_vseqr.sv"
  `include "cpu_env.sv"
  `include "csr_ral.sv"
  `include "cpu_seq_lib.sv"
  `include "cpu_test_lib.sv"

endpackage : cpu_tb_pkg

`endif // CPU_TB_PKG_SV
