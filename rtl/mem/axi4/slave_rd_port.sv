// Read side of one slave port.

module slave_rd_port
  import axi4_pkg::*;
(
  input  logic                  aclk,
  input  logic                  arst_n,

  input  logic [1:0]                 m_arvalid,   // one bit per master port
  output logic [1:0]                 m_arready,
  input  logic [1:0][M_ID_W-1:0]     m_arid,
  input  logic [1:0][ADDR_WIDTH-1:0] m_araddr,
  input  logic [1:0][7:0]            m_arlen,
  input  logic [1:0][2:0]            m_arsize,
  input  logic [1:0][1:0]            m_arburst,

  input  logic [1:0]            arb_req,
  input  logic [1:0]            arb_ack,
  output logic [1:0]            arb_gnt,

  output logic                  s_arvalid,
  input  logic                  s_arready,
  output logic [M_ID_W-1:0]     s_arid,
  output logic [ADDR_WIDTH-1:0] s_araddr,
  output logic [7:0]            s_arlen,
  output logic [2:0]            s_arsize,
  output logic [1:0]            s_arburst
);

  logic gnt_valid;
  logic gnt_idx;              // 0 = M0, 1 = M1

  rr_arbiter #(.HOLD_IDLE_GRANT(0)) u_arb (
    .aclk      (aclk),
    .arst_n    (arst_n),
    .req       (arb_req),
    .ack       (arb_ack),
    .gnt       (arb_gnt),
    .gnt_valid (gnt_valid)
  );

  assign gnt_idx = arb_gnt[1];

  assign s_arvalid = gnt_valid && m_arvalid[gnt_idx];
  assign s_arid    = m_arid   [gnt_idx];
  assign s_araddr  = m_araddr [gnt_idx];
  assign s_arlen   = m_arlen  [gnt_idx];
  assign s_arsize  = m_arsize [gnt_idx];
  assign s_arburst = m_arburst[gnt_idx];

  assign m_arready[0] = gnt_valid && (gnt_idx == 1'b0) && s_arready;
  assign m_arready[1] = gnt_valid && (gnt_idx == 1'b1) && s_arready;

  a_ar_one_master: assert property (@(posedge aclk) disable iff (!arst_n)
    $onehot0(m_arready))
    else $error("slave_rd_port: AR accepted from both masters");

endmodule : slave_rd_port
