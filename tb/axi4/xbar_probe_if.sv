// Carries DUT internals into the class world.

interface xbar_probe_if (input logic aclk, input logic arst_n);

  logic [2:0] p0_aw_pending, p0_w_pending, p0_tenure_cnt;
  logic [2:0] p1_aw_pending, p1_w_pending, p1_tenure_cnt;

  logic       p0_mw_grant, p0_mw_full, p0_aw_admit, p0_mw_release, p0_thr_ok;
  logic       p1_mw_grant, p1_mw_full, p1_aw_admit, p1_mw_release, p1_thr_ok;

  logic [1:0] p0_mw_dest, p0_aw_dest, p0_arb_req;
  logic [1:0] p1_mw_dest, p1_aw_dest, p1_arb_req;

  logic [1:0] s0w_arb_gnt, s1w_arb_gnt;
  logic       s0w_gnt_valid, s1w_gnt_valid;

  int rst_req    = 0;
  int rst_settle = 5;   // posedges tb_top waits after release before clearing rst_req

endinterface
