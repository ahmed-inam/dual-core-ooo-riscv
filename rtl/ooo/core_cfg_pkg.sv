// Every out-of-order structure size, in one place.
package core_cfg_pkg;

  localparam int unsigned WIDTH  = 2;   // pipeline width: 1 (Gate A) / 2 (Gate B)

  localparam int unsigned ROB_N  = 32;  // reorder buffer entries
  localparam int unsigned PRF_N  = 64;  // physical registers (see header)
  localparam int unsigned IQ_N   = 16;  // issue queue entries
  localparam int unsigned LQ_N   = 8;   // load queue entries
  localparam int unsigned SQ_N   = 8;   // store queue entries
  localparam int unsigned SNAP_N = 4;   // branch snapshots. DELIBERATELY under-

  localparam int unsigned DECODE_W   = WIDTH;
  localparam int unsigned RENAME_W   = WIDTH;
  localparam int unsigned DISPATCH_W = WIDTH;
  localparam int unsigned COMMIT_W   = WIDTH;
  localparam int unsigned WAKEUP_W   = WIDTH + 1;  // result buses per cycle:
  localparam int unsigned WAKEUP_IQ_W = WAKEUP_W + WIDTH;  // plus one select-time wakeup per issue port


  localparam int unsigned PREG_W = $clog2(PRF_N);
  localparam int unsigned ROB_W  = $clog2(ROB_N);
  localparam int unsigned IQ_W   = $clog2(IQ_N);
  localparam int unsigned LQ_W   = $clog2(LQ_N);
  localparam int unsigned SQ_W   = $clog2(SQ_N);
  localparam int unsigned SNAP_W = $clog2(SNAP_N);

  typedef logic [PREG_W-1:0] preg_t;      // physical register name
  typedef logic [ROB_W-1:0]  rob_ptr_t;   // ROB index (wrap bit added by the
  typedef logic [IQ_W-1:0]   iq_ptr_t;
  typedef logic [LQ_W-1:0]   lq_ptr_t;
  typedef logic [SQ_W-1:0]   sq_ptr_t;
  typedef logic [SNAP_W-1:0] snap_ptr_t;

endpackage : core_cfg_pkg
