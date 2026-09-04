// Elaboration-time assertions on the out-of-order structure sizes.
module core_cfg_check;
  import core_cfg_pkg::*;

  if (PRF_N < 32 + WIDTH)
    $fatal(1, "core_cfg R-PRF-FLOOR: PRF_N(%0d) < 32 + WIDTH(%0d): rename deadlocks",
           PRF_N, WIDTH);

  if (PRF_N < 32 + ROB_N)
    $fatal(1, "core_cfg R-PRF-INTENT: PRF_N(%0d) < 32 + ROB_N(%0d): free list would bind before the ROB; waiving this requires demoting the check AND journaling why",
           PRF_N, ROB_N);

  if ((ROB_N % WIDTH) != 0)
    $fatal(1, "core_cfg R-ROB-ALIGN: ROB_N(%0d) %% WIDTH(%0d) != 0: banked alloc/commit breaks",
           ROB_N, WIDTH);

  if (IQ_N > ROB_N || IQ_N < WIDTH)
    $fatal(1, "core_cfg R-IQ-CAP: IQ_N(%0d) outside [WIDTH(%0d), ROB_N(%0d)]",
           IQ_N, WIDTH, ROB_N);

  if (LQ_N > ROB_N)
    $fatal(1, "core_cfg R-LQ-CAP: LQ_N(%0d) > ROB_N(%0d): loads leave at commit, occupancy cannot exceed in-flight",
           LQ_N, ROB_N);

  if (SQ_N > ROB_N)
    $fatal(1, "core_cfg R-SQ-CAP: SQ_N(%0d) > ROB_N(%0d): depth past the ROB buys nothing against a blocking cache (sizing sanity, see pkg)",
           SQ_N, ROB_N);

  if (SNAP_N < 1)
    $fatal(1, "core_cfg R-SNAP-MIN: SNAP_N(%0d) < 1", SNAP_N);

  if (!(WIDTH == 1 || WIDTH == 2))
    $fatal(1, "core_cfg R-WIDTH-SET: WIDTH(%0d) not in {1,2}", WIDTH);

  if ((ROB_N & (ROB_N-1)) != 0 || (PRF_N & (PRF_N-1)) != 0 ||
      (IQ_N  & (IQ_N -1)) != 0 || (LQ_N  & (LQ_N -1)) != 0 ||
      (SQ_N  & (SQ_N -1)) != 0 || (SNAP_N & (SNAP_N-1)) != 0)
    $fatal(1, "core_cfg R-POW2: a size is not a power of two (ROB=%0d PRF=%0d IQ=%0d LQ=%0d SQ=%0d SNAP=%0d): ring wrap and tag widths assume it",
           ROB_N, PRF_N, IQ_N, LQ_N, SQ_N, SNAP_N);

endmodule
