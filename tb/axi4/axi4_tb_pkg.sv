// Class-based testbench package.

`timescale 1ns/1ps

package axi4_tb_pkg;

  import axi4_pkg::*;

  int tb_verbosity = 1;
  bit verbose = 0;   // derived: tb_verbosity >= 3 (set in tb_top)

  `define TB_BUILD(CLS, NM) \
    if (tb_verbosity >= 2) \
      $display("[%0t] [BUILD] %-18s %-14s (%s:%0d)", $time, CLS, NM, `__FILE__, `__LINE__)

  int tb_mon_errors = 0;

  bit slverr_window = 0;

  localparam logic [31:0] S0_BASE  = {S0_PREFIX, {DEC_LSB{1'b0}}};
  localparam logic [31:0] S1_BASE  = {S1_PREFIX, {DEC_LSB{1'b0}}};
  localparam logic [31:0] BAD_BASE = 32'hF000_0000;

  typedef enum { WRITE, READ }                    dir_e;
  typedef enum { DEST_S0_T, DEST_S1_T, DEST_BAD } tdest_e;

  `include "axi4_txn.sv"

  `include "axi4_mst_driver.sv"
  `include "axi4_mst_monitor.sv"
  `include "axi4_slv_driver.sv"
  `include "axi4_slv_monitor.sv"

  `include "axi4_seq.sv"

  `include "axi4_ref_model.sv"
  `include "axi4_scoreboard.sv"

  `include "axi4_mst_agent.sv"
  `include "axi4_slv_agent.sv"

  `include "axi4_env.sv"

  `include "axi4_test.sv"

endpackage
