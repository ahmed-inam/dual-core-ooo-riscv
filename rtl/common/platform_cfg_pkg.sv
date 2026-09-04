// Platform scale: hart count and memory map, in one place.
package platform_cfg_pkg;

  localparam int unsigned NUM_HARTS = 2;


  localparam int unsigned HART_W = (NUM_HARTS <= 1) ? 1 : $clog2(NUM_HARTS);

  typedef logic [HART_W-1:0] hart_id_t;   // per-hart replication index

endpackage : platform_cfg_pkg
