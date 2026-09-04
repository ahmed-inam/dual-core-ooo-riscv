// Snoop request, response and grant encodings.
package coherence_pkg;

  import mem_pkg::*;

  typedef enum logic [1:0] {
    REQ_GETS    = 2'd0,   // I -> S      (rocket NtoB)
    REQ_GETM    = 2'd1,   // I -> M      (rocket NtoT)
    REQ_UPGRADE = 2'd2,   // S -> M, no data needed  (rocket BtoT)
    REQ_PUTM    = 2'd3    // M -> I eviction writeback (gem5 PUTX); ORDERED and
  } coh_req_e;

  function automatic logic req_needs_data(input coh_req_e r);
    return (r == REQ_GETS) || (r == REQ_GETM);
  endfunction

  typedef enum logic [0:0] {
    SNP_TO_S = 1'd0,      // "downgrade to at most S"  (rocket toB) <- from GetS
    SNP_TO_I = 1'd1       // "downgrade to I"          (rocket toN) <- from GetM/Upgrade
  } coh_snoop_e;

  function automatic coh_snoop_e snoop_of(input coh_req_e r);
    return (r == REQ_GETS) ? SNP_TO_S : SNP_TO_I;
  endfunction

  typedef enum logic [2:0] {
    RSP_TtoB = 3'd0,      // was E or M, now S   (data attached iff it was M)
    RSP_TtoN = 3'd1,      // was E or M, now I   (data attached iff it was M)
    RSP_BtoN = 3'd2,      // was S,      now I   (never any data)
    RSP_TtoT = 3'd3,      // held E/M, snoop did not require a change
    RSP_BtoB = 3'd4,      // held S, Snoop-GetS: stays S
    RSP_NtoN = 3'd5       // did not have the line at all
  } coh_rsp_e;

  function automatic logic rsp_keeps_copy(input coh_rsp_e r);
    return (r == RSP_TtoB) || (r == RSP_TtoT) || (r == RSP_BtoB);
  endfunction

  function automatic logic rsp_had_copy(input coh_rsp_e r);
    return (r != RSP_NtoN);
  endfunction

  typedef struct packed {
    logic shared;         // another core still holds a copy -> install S, not E
    logic data_dirty;     // a responder had it dirty -> writeback required
  } snoop_agg_t;

  function automatic line_state_t install_state(input coh_req_e r,
                                                input logic     shared);
    if (r == REQ_GETS) return shared ? LINE_S : LINE_E;
    else               return LINE_M;   // GetM / Upgrade
  endfunction

  typedef enum logic [2:0] {
    TR_NONE = 3'd0,       // no coherence transaction outstanding for this line
    TR_IS_D = 3'd1,       // issued GetS,    awaiting data
    TR_IM_D = 3'd2,       // issued GetM,    awaiting data
    TR_SM_A = 3'd3,       // issued Upgrade, awaiting ack. Holds a valid S copy
    TR_MI_A = 3'd4        // issued PutM,    awaiting writeback ack
  } coh_trans_e;

  function automatic logic is_transient(input coh_trans_e t);
    return t != TR_NONE;
  endfunction

  function automatic logic trans_readable(input coh_trans_e t);
    return t == TR_SM_A;
  endfunction

  typedef enum logic [2:0] {
    EV_NONE       = 3'd0,
    EV_LOAD       = 3'd1,   // own-core load to this line
    EV_STORE      = 3'd2,   // own-core store to this line
    EV_EVICT      = 3'd3,   // this line selected for replacement
    EV_SNOOP_GETS = 3'd4,   // remote GetS         (cap toB)
    EV_SNOOP_GETM = 3'd5,   // remote GetM/Upgrade (cap toN) -- identical here
    EV_DATA       = 3'd6    // completion of MY outstanding request
  } coh_event_e;

  function automatic logic ev_is_snoop(input coh_event_e e);
    return (e == EV_SNOOP_GETS) || (e == EV_SNOOP_GETM);
  endfunction

  typedef struct packed {
    logic       hit;          // serve the core locally this cycle
    logic       stall;        // block the core; transient must complete first
    logic       req_valid;    // put req on the coherence bus
    coh_req_e   req;          //   which request
    logic       wb;           // write the line back to memory (B1: through memory)
    logic       inv;          // invalidate the local copy
    logic       silent_drop;  // clean eviction: drop with no bus traffic
    logic       snp_resp;     // drive a snoop response this cycle
    coh_rsp_e   snp_rsp;      //   which response (rocket shrink/report encoding)
    logic       rsv_clear;    // clear an LR reservation on this line
    logic       finish_load;  // completion satisfies a waiting load
    logic       finish_store; // completion satisfies a waiting store
  } coh_act_t;

  localparam int unsigned LRSC_WINDOW_N = 512;   // estimate; validated by use, not derived
  localparam int unsigned LRSC_BACKOFF  = 8;     // post-window re-acquire lockout

  localparam int unsigned LRSC_CNT_W = $clog2(LRSC_WINDOW_N + 1);


endpackage : coherence_pkg
