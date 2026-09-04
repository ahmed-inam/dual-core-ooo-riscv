// The DUT-facing interfaces for the cluster UVM environment.

interface rvfi_if
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
(
  input logic clk,
  input logic rst_n,
  input logic     [COMMIT_W-1:0]       valid,
  input logic     [COMMIT_W-1:0][63:0] order,
  input word_t    [COMMIT_W-1:0]       insn,
  input word_t    [COMMIT_W-1:0]       pc_rdata,
  input word_t    [COMMIT_W-1:0]       rd_wdata,
  input regaddr_t [COMMIT_W-1:0]       rd_addr,
  input logic     [COMMIT_W-1:0]       trap,

  input logic     [COMMIT_W-1:0]       halt,
  input logic     [COMMIT_W-1:0]       intr,
  input logic     [COMMIT_W-1:0][1:0]  mode,
  input logic     [COMMIT_W-1:0][1:0]  ixl,

  input regaddr_t [COMMIT_W-1:0]       rs1_addr,
  input regaddr_t [COMMIT_W-1:0]       rs2_addr,
  input word_t    [COMMIT_W-1:0]       rs1_rdata,
  input word_t    [COMMIT_W-1:0]       rs2_rdata,

  input word_t    [COMMIT_W-1:0]       pc_wdata,

  input word_t    [COMMIT_W-1:0]       mem_addr,
  input logic     [COMMIT_W-1:0][3:0]  mem_rmask,
  input logic     [COMMIT_W-1:0][3:0]  mem_wmask,
  input word_t    [COMMIT_W-1:0]       mem_rdata,
  input word_t    [COMMIT_W-1:0]       mem_wdata
);

  modport mon (
    input clk, rst_n,
    input valid, order, insn, pc_rdata, rd_wdata, rd_addr, trap,
    input halt, intr, mode, ixl,
    input rs1_addr, rs2_addr, rs1_rdata, rs2_rdata,
    input pc_wdata,
    input mem_addr, mem_rmask, mem_wmask, mem_rdata, mem_wdata
  );

endinterface


interface sys_if
  import rv32i_pkg::*;
  import platform_cfg_pkg::*;
(
  input logic clk,
  input logic rst_n,
  input logic  [NUM_HARTS-1:0] dreq,
  input logic  [NUM_HARTS-1:0] dwe,
  input word_t [NUM_HARTS-1:0] daddr,
  input word_t [NUM_HARTS-1:0] dwdata,
  input logic  [NUM_HARTS-1:0] ev_starve
);

  modport mon (
    input clk, rst_n,
    input dreq, dwe, daddr, dwdata, ev_starve
  );

endinterface


interface irq_if
  import platform_cfg_pkg::*;
(
  input logic clk,
  input logic rst_n
);

  logic [NUM_HARTS-1:0] msip;   // machine software interrupt pending, per hart
  logic [NUM_HARTS-1:0] mtip;   // machine timer    interrupt pending, per hart

  modport drv ( input clk, rst_n, output msip, mtip );
  modport mon ( input clk, rst_n, input  msip, mtip );

endinterface


interface snoop_if
  import rv32i_pkg::*;
  import platform_cfg_pkg::*;
  import coherence_pkg::*;
(
  input logic clk,
  input logic rst_n,

  input logic     [NUM_HARTS-1:0] req_valid,
  input coh_req_e                 req_type  [NUM_HARTS],   // GETS/GETM/UPGRADE/PUTM
  input word_t                    req_addr  [NUM_HARTS],
  input logic     [NUM_HARTS-1:0] req_gnt,
  input logic     [NUM_HARTS-1:0] req_atomic,

  input logic       [NUM_HARTS-1:0] snp_valid,
  input word_t                      snp_addr,
  input coh_snoop_e                 snp_type,              // SNP_TO_S / SNP_TO_I
  input logic       [NUM_HARTS-1:0] snp_ack,
  input coh_rsp_e                   snp_rsp   [NUM_HARTS], // TtoB/TtoN/BtoN/TtoT/BtoB/NtoN

  input logic [NUM_HARTS-1:0] cmp_valid,
  input logic                 cmp_shared,
  input logic                 cmp_dirty,
  input logic [NUM_HARTS-1:0] installed,

  input logic prot_deferred,
  input logic ord_violation,

  input logic  [NUM_HARTS-1:0] lr_valid,
  input logic  [NUM_HARTS-1:0] sc_valid,
  input logic  [NUM_HARTS-1:0] sc_success,
  input logic  [NUM_HARTS-1:0] rsv_valid,
  input logic  [NUM_HARTS-1:0] backing_off,  // the 6.9 livelock escape (rocket lrscBackingOff)
  input logic  [NUM_HARTS-1:0] snoop_clear,  // snoop killed a reservation
  input logic  [NUM_HARTS-1:0] trap_clear,   // a trap killed a reservation
  input word_t                 acc_addr [NUM_HARTS],
  input word_t                 prot_addr [NUM_HARTS]
);

  modport mon (
    input clk, rst_n,
    input req_valid, req_type, req_addr, req_gnt, req_atomic,
    input snp_valid, snp_addr, snp_type, snp_ack, snp_rsp,
    input cmp_valid, cmp_shared, cmp_dirty, installed,
    input prot_deferred, ord_violation,
    input lr_valid, sc_valid, sc_success, rsv_valid, backing_off,
    input snoop_clear, trap_clear, acc_addr, prot_addr
  );

endinterface


interface cache_probe_if
  import rv32i_pkg::*;
  import mem_pkg::*;
(
  input logic  clk,
  input logic  rst_n,
  input dtag_t tag [SETS][WAYS],
  input logic  wi,          // mshr_wi_q -- write intent (a store, or an LR)
  input logic  we           // mshr_we_q -- a real store, as opposed to an LR
);

  function automatic logic [IDX_W-1:0] idx_of(input word_t a);
    return a[OFF_W +: IDX_W];
  endfunction

  function automatic logic [TAG_W-1:0] tag_of(input word_t a);
    return a[31 -: TAG_W];
  endfunction

  function automatic line_state_t state_of(input word_t a);
    logic [IDX_W-1:0] i = idx_of(a);
    logic [TAG_W-1:0] t = tag_of(a);
    for (int w = 0; w < WAYS; w++)
      if (is_valid(tag[i][w].state) && (tag[i][w].tag == t)) return tag[i][w].state;
    return LINE_I;
  endfunction

  modport mon (
    input clk, rst_n, tag,
    import idx_of, import tag_of, import state_of
  );

endinterface


interface core_probe_if
  import rv32i_pkg::*;
  import ooo_pkg::*;
  import core_cfg_pkg::*;
(
  input logic clk,
  input logic rst_n,

  input logic [ROB_W:0] rob_count,
  input logic [SQ_W:0]  sq_cnt,
  input logic [LQ_W:0]  lq_cnt,

  input logic recovery_idle,
  input logic mispredict_ex,
  input logic trig_viol,

  input logic [2:0] rq_state,      // core.sv rq_q; R_IDLE is the 0 encoding
  input logic r_is_bpr_q,          // branch mispredict
  input logic r_is_viol_q,         // memory-ordering violation
  input logic r_is_irq_q,          // asynchronous interrupt
  input logic r_is_exc_q,          // synchronous exception
  input logic r_is_mret_q,         // actor: mret
  input logic r_is_fence_q,        // actor: fence
  input logic r_is_fencei_q,       // actor: fence.i

  input word_t trap_cause,
  input word_t mstatus,            // mie[3], mpie[7], mpp[12:11]

  input logic     bp_mispredict,
  input cf_type_e bp_cf_type,
  input logic     bp_call,
  input logic     bp_ret,

  input rob_ptr_t rob_head_id,
  input logic     rob_viol [ROB_N],

  input logic [SNAP_W:0] snap_cnt,

  input logic     trap_taken
);

  function automatic bit recovering();
    return !recovery_idle;
  endfunction

  localparam int unsigned REC_NONE        = 0;  // not recovering, or not yet classified
  localparam int unsigned REC_MISPREDICT  = 1;
  localparam int unsigned REC_VIOLATION   = 2;
  localparam int unsigned REC_TRAP        = 3;  // interrupt or exception
  localparam int unsigned REC_ACTOR_FENCE = 4;  // fence / fence.i -- the D_FLUSH_SCAN path
  localparam int unsigned REC_ACTOR_OTHER = 5;  // mret, or an SC at the head

  localparam logic [2:0] RQ_IDLE = 3'd0;        // core.sv rec_e: R_IDLE is first

  function automatic int unsigned rec_cause();
    if (rq_state == RQ_IDLE)              return REC_NONE;
    if (r_is_irq_q || r_is_exc_q)         return REC_TRAP;
    if (r_is_viol_q)                      return REC_VIOLATION;
    if (r_is_bpr_q)                       return REC_MISPREDICT;
    if (r_is_fence_q || r_is_fencei_q)    return REC_ACTOR_FENCE;
    return REC_ACTOR_OTHER;
  endfunction

  function automatic int unsigned bucket4(input int unsigned v,
                                          input int unsigned cap,
                                          input int unsigned alloc_max);
    if (v == 0)           return 0;                   // empty
    if (v * 4 <  cap)     return 1;                   // light
    if (v     <= alloc_max) return 2;                 // busy, still accepting
    return 3;                                         // full: allocation stalled
  endfunction

  modport mon (
    input clk, rst_n, rob_count, sq_cnt, lq_cnt, recovery_idle, mispredict_ex,
    input trig_viol,
    input rq_state, r_is_bpr_q, r_is_viol_q, r_is_irq_q, r_is_exc_q,
    input r_is_mret_q, r_is_fence_q, r_is_fencei_q,
    input trap_cause, mstatus,
    input bp_mispredict, bp_cf_type, bp_call, bp_ret,
    input rob_head_id, rob_viol, snap_cnt, trap_taken,
    import recovering, import bucket4, import rec_cause
  );

endinterface

// public (`--public-flat-rw` or a `/*verilator public*/` mark), i.e. it requires
interface csr_probe_if
  import rv32i_pkg::*;
(
  input logic  clk,
  input logic  rst_n,
  input word_t mstatus,
  input word_t mie,
  input word_t mtvec,
  input word_t mscratch,
  input word_t mepc,
  input word_t mcause,
  input word_t mtval,
  input word_t mip
);

  function automatic word_t read_csr(input logic [11:0] addr);
    case (addr)
      12'h300: return mstatus;
      12'h304: return mie;
      12'h305: return mtvec;
      12'h340: return mscratch;
      12'h341: return mepc;
      12'h342: return mcause;
      12'h343: return mtval;
      12'h344: return mip;
      default: return '0;
    endcase
  endfunction

  modport mon (input clk, rst_n, mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip,
               import read_csr);

endinterface
