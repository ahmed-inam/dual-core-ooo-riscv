// Write side of one slave port.

module slave_wr_port
  import axi4_pkg::*;
(
  input  logic                  aclk,
  input  logic                  arst_n,

  input  logic [1:0]            m_awvalid,    // one bit per master port
  output logic [1:0]            m_awready,
  input  logic [1:0][M_ID_W-1:0]     m_awid,
  input  logic [1:0][ADDR_WIDTH-1:0] m_awaddr,
  input  logic [1:0][7:0]            m_awlen,
  input  logic [1:0][2:0]            m_awsize,
  input  logic [1:0][1:0]            m_awburst,

  input  logic [1:0]            m_wvalid,
  output logic [1:0]            m_wready,
  input  logic [1:0][DATA_WIDTH-1:0] m_wdata,
  input  logic [1:0][STRB_WIDTH-1:0] m_wstrb,
  input  logic [1:0]            m_wlast,

  input  logic [1:0]            arb_req,      // grant requests from the master ports
  input  logic [1:0]            arb_ack,
  output logic [1:0]            arb_gnt,

  output logic                  s_awvalid,    // toward the slave
  input  logic                  s_awready,
  output logic [M_ID_W-1:0]     s_awid,
  output logic [ADDR_WIDTH-1:0] s_awaddr,
  output logic [7:0]            s_awlen,
  output logic [2:0]            s_awsize,
  output logic [1:0]            s_awburst,

  output logic                  s_wvalid,
  input  logic                  s_wready,
  output logic [DATA_WIDTH-1:0] s_wdata,
  output logic [STRB_WIDTH-1:0] s_wstrb,
  output logic                  s_wlast
);

  logic gnt_valid;
  logic gnt_idx;      // 0 = M0, 1 = M1
  logic w_owner;

  rr_arbiter #(.HOLD_IDLE_GRANT(1)) u_arb (
    .aclk      (aclk),
    .arst_n    (arst_n),
    .req       (arb_req),
    .ack       (arb_ack),
    .gnt       (arb_gnt),
    .gnt_valid (gnt_valid)
  );

  assign gnt_idx = arb_gnt[1];

  assign s_awvalid = gnt_valid && m_awvalid[gnt_idx];
  assign s_awid    = m_awid   [gnt_idx];
  assign s_awaddr  = m_awaddr [gnt_idx];
  assign s_awlen   = m_awlen  [gnt_idx];
  assign s_awsize  = m_awsize [gnt_idx];
  assign s_awburst = m_awburst[gnt_idx];

  assign m_awready[0] = gnt_valid && (gnt_idx == 1'b0) && s_awready;
  assign m_awready[1] = gnt_valid && (gnt_idx == 1'b1) && s_awready;

  assign w_owner = gnt_idx;

  assign s_wvalid = gnt_valid && m_wvalid[w_owner];
  assign s_wdata  = m_wdata[w_owner];
  assign s_wstrb  = m_wstrb[w_owner];
  assign s_wlast  = m_wlast[w_owner];

  assign m_wready[0] = gnt_valid && (w_owner == 1'b0) && s_wready;
  assign m_wready[1] = gnt_valid && (w_owner == 1'b1) && s_wready;

  a_aw_one_master: assert property (@(posedge aclk) disable iff (!arst_n)
    $onehot0(m_awready))
    else $error("slave_wr_port: AW accepted from both masters");

  a_w_one_master: assert property (@(posedge aclk) disable iff (!arst_n)
    $onehot0(m_wready))
    else $error("slave_wr_port: W accepted from both masters -- bursts would interleave");

endmodule : slave_wr_port
