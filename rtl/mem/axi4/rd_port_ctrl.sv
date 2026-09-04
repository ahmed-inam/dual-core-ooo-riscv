// Read path control for one master port.

module rd_port_ctrl
  import axi4_pkg::*;
#(
  parameter int unsigned MASTER_IDX = 0
) (
  input  logic                aclk,
  input  logic                arst_n,

  input  logic                ar_valid,       // from the master-facing AR skid
  output logic                ar_ready,
  input  logic [ID_WIDTH-1:0] ar_id,
  input  dest_e               ar_dest,        // from addr_decoder

  input  logic                thr_ok,         // thread_tracker query result
  output logic                thr_alloc,

  output logic [1:0]          s_arvalid,      // toward the two slave ports
  input  logic [1:0]          s_arready,
  output logic [M_ID_W-1:0]   s_arid,

  output logic [1:0]          arb_req,        // slave-side arbiters
  output logic [1:0]          arb_ack,

  input  logic                decerr_busy,    // local error responder
  output logic                decerr_ar_accept,

  input  logic                cpl_valid       // from resp_return_mux, fires on RLAST
);

  logic [CNT_W-1:0] ar_pending;
  logic             ar_go, ar_admit, ar_full, dn_arready;

  assign ar_full = (ar_pending >= MAX_OUT_Q) && !cpl_valid;

  assign ar_go = ar_valid && thr_ok && !ar_full &&
                 ((ar_dest == DEST_DECERR) ? !decerr_busy : 1'b1);

  assign s_arvalid[0] = ar_go && (ar_dest == DEST_S0);
  assign s_arvalid[1] = ar_go && (ar_dest == DEST_S1);
  assign s_arid       = tag_id(ar_id, MASTER_IDX);

  always_comb begin
    case (ar_dest)
      DEST_S0: dn_arready = s_arready[0];
      DEST_S1: dn_arready = s_arready[1];
      default: dn_arready = 1'b1;          // DECERR reserves no slave
    endcase
  end

  assign ar_ready = ar_go && dn_arready;

  assign ar_admit         = ar_valid && ar_ready;
  assign thr_alloc        = ar_admit;
  assign decerr_ar_accept = ar_admit && (ar_dest == DEST_DECERR);

  assign arb_req = s_arvalid;
  assign arb_ack = s_arvalid & s_arready;

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      ar_pending <= '0;
    end
    else begin
      if      ( ar_admit && !cpl_valid) ar_pending <= ar_pending + 1'b1;
      else if (!ar_admit &&  cpl_valid) ar_pending <= ar_pending - 1'b1;
    end
  end

  a_ar_routed_once: assert property (@(posedge aclk) disable iff (!arst_n)
    $onehot0(s_arvalid))
    else $error("rd_port_ctrl: AR forwarded to more than one slave");

  a_cpl_owed: assert property (@(posedge aclk) disable iff (!arst_n)
    cpl_valid |-> (ar_pending != '0))
    else $error("rd_port_ctrl: completion with nothing outstanding");

  a_req_held: assert property (@(posedge aclk) disable iff (!arst_n)
    (|arb_req && !(|arb_ack)) |=> |arb_req)
    else $error("rd_port_ctrl: AR request withdrawn before its handshake");

endmodule : rd_port_ctrl
