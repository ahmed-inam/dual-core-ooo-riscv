// Shared types for the out-of-order machine.
package ooo_pkg;
  import rv32i_pkg::*;
  import core_cfg_pkg::*;

  typedef struct packed {
    logic        valid;
    word_t       pc;
    word_t       instr;       // RVFI payload, rides to commit
    ctrl_t       ctrl;
    word_t       imm;
    logic [4:0]  lrs1, lrs2, lrd;
    preg_t       prs1, prs2;
    preg_t       pdst;        // new physical destination (if ctrl.rf_we)
    preg_t       stale_pdst;  // previous mapping of lrd; commit frees it
    rob_ptr_t    rob_id;      // filled at ROB allocation
    bp_pred_t    pred;        // the prediction this op was FETCHED
    snap_ptr_t   snap_id;     // cf ops only: the snapshot slot this
  } uop_t;

  typedef struct packed {
    logic        valid;
    logic        done;        // completed; head may retire it
    word_t       pc;
    word_t       instr;
    logic [4:0]  lrd;
    logic [4:0]  lrs1, lrs2;
    logic        rf_we;       // writes a register (lrd != 0 and ctrl.rf_we)
    preg_t       pdst;
    preg_t       stale_pdst;
    logic        is_store;
    logic        is_mem;      // load or store: the mem-at-head sequencer's
    logic        is_branch;
    logic        is_csr;      // executes at head via the CSR sequencer
    logic        is_fence;    // acts at retirement: D-cache writeback walk
    logic        is_fence_i;  // acts at retirement: redirect pc+4 (refetch)
    logic        is_mret;
    bp_snapshot_t bsnap;      // fetch-time predictor snapshot: the
    word_t       wdata;       // class-owned: result value / store data
    logic        exc_valid;   // exception raised pre-commit; acts at head (4c-6)
    logic [3:0]  exc_cause;
    word_t       exc_tval;
  } rob_entry_t;

  typedef struct packed {
    logic        valid;
    word_t       pc;
    word_t       instr;
    logic [4:0]  lrd;
    logic [4:0]  lrs1, lrs2;   // RVFI rs1_addr / rs2_addr
    logic        rf_we;
    preg_t       pdst;
    preg_t       stale_pdst;
    logic        is_store;
    logic        is_branch;   // RVFI pc_wdata: control flow takes the
    logic        is_mret;     // ...except mret, whose next pc is mepc.
    logic        is_mem;      // loads = is_mem && !is_store; the
    word_t       wdata;
  } commit_t;

endpackage : ooo_pkg
