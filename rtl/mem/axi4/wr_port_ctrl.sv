// Write path control for one master port.

module wr_port_ctrl
  import axi4_pkg::*;
#(
  parameter int unsigned MASTER_IDX = 0
) (
  input  logic                aclk,
  input  logic                arst_n,

  input  logic                aw_valid,       // from the master-facing AW skid
  output logic                aw_ready,
  input  logic [ID_WIDTH-1:0] aw_id,
  input  dest_e               aw_dest,        // from addr_decoder

  input  logic                thr_ok,         // thread_tracker query result
  output logic                thr_alloc,

  input  logic                w_valid,        // from the master-facing W skid
  output logic                w_ready,
  input  logic                w_last,

  output logic [1:0]          s_awvalid,      // toward the two slave ports
  input  logic [1:0]          s_awready,
  output logic [M_ID_W-1:0]   s_awid,
  output logic [1:0]          s_wvalid,
  input  logic [1:0]          s_wready,

  output logic [1:0]          arb_req,        // slave-side arbiters
  input  logic [1:0]          arb_gnt,
  output logic [1:0]          arb_ack,

  input  logic                decerr_busy,    // local error responder
  output logic                decerr_aw_accept,
  output logic                decerr_w_beat,
  output logic                decerr_w_last,

  input  logic                other_aw_valid, // sibling port, for contested
  input  dest_e               other_aw_dest,

  input  logic                cpl_valid,      // from resp_return_mux

  output logic                mw_grant,
  output dest_e               mw_dest
);

  logic [CNT_W-1:0]    aw_pending, w_pending;
  logic [TENURE_W-1:0] tenure_cnt;

  logic mw_full, contested, close_admission;
  logic dn_awready, dn_wready;
  logic aw_committed;            // an AW is on the wire, awaiting AWREADY
  logic same_dest, needs_diff, dest_free;
  logic aw_go, aw_admit, grant_taken, mw_release;
  logic w_beat_ok, w_drop, w_last_beat;
  logic w_ahead;                 // a burst finished before its AW was admitted

  assign mw_full = (aw_pending >= MAX_OUT_Q) && !cpl_valid;

  assign same_dest = (aw_dest == mw_dest);
  assign dest_free = (w_pending == '0);          // mw_dest may only change with no beats owed
  assign needs_diff = aw_valid && !same_dest;

  assign contested = mw_grant && other_aw_valid && (other_aw_dest == mw_dest);

  assign close_admission = contested && (tenure_cnt >= TENURE_Q) && !aw_committed;

  assign aw_go = aw_valid && thr_ok && !mw_full &&
                 ((aw_dest == DEST_DECERR) ? (!decerr_busy && !mw_grant && dest_free)
                                           : (mw_grant && same_dest && !close_admission));

  assign s_awvalid[0] = aw_go && (aw_dest == DEST_S0);
  assign s_awvalid[1] = aw_go && (aw_dest == DEST_S1);
  assign s_awid       = tag_id(aw_id, MASTER_IDX);

  always_comb begin
    case (aw_dest)
      DEST_S0: dn_awready = s_awready[0];
      DEST_S1: dn_awready = s_awready[1];
      default: dn_awready = 1'b1;          // DECERR reserves no slave
    endcase
  end

  assign aw_ready = aw_go && dn_awready;
  assign aw_admit  = aw_valid && aw_ready;
  assign thr_alloc = aw_admit;
  assign decerr_aw_accept = aw_admit && (aw_dest == DEST_DECERR);

  assign arb_req[0] = !mw_grant && aw_valid && thr_ok && !mw_full && dest_free
                      && (aw_dest == DEST_S0);
  assign arb_req[1] = !mw_grant && aw_valid && thr_ok && !mw_full && dest_free
                      && (aw_dest == DEST_S1);

  assign grant_taken = |arb_gnt && !mw_grant;

  assign mw_release  = mw_grant && dest_free && !aw_admit && !(|s_awvalid)
                       && (needs_diff || contested);
  assign arb_ack[0]  = mw_release && (mw_dest == DEST_S0);
  assign arb_ack[1]  = mw_release && (mw_dest == DEST_S1);

  assign w_beat_ok   = (w_pending != '0) || (|s_awvalid && !w_ahead);   // A3.3.1: W must not wait for AWREADY
  assign w_drop      = w_beat_ok && (mw_dest == DEST_DECERR);
  assign s_wvalid[0] = w_valid && w_beat_ok && mw_grant && (mw_dest == DEST_S0);
  assign s_wvalid[1] = w_valid && w_beat_ok && mw_grant && (mw_dest == DEST_S1);

  always_comb begin
    case (mw_dest)
      DEST_S0: dn_wready = s_wready[0];
      DEST_S1: dn_wready = s_wready[1];
      default: dn_wready = 1'b1;
    endcase
  end

  assign w_ready = w_drop ? 1'b1 : (w_beat_ok && mw_grant && dn_wready);
  assign w_last_beat   = w_valid && w_ready && w_last;
  assign decerr_w_beat = w_valid && w_ready && w_drop;
  assign decerr_w_last = w_last;

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      mw_grant     <= 1'b0;
      mw_dest      <= DEST_S0;
      aw_committed <= 1'b0;
      aw_pending <= '0;
      w_pending  <= '0;
      w_ahead    <= 1'b0;
      tenure_cnt <= '0;
    end
    else begin
      if (grant_taken) begin
        mw_grant <= 1'b1;
        mw_dest  <= arb_gnt[0] ? DEST_S0 : DEST_S1;
      end
      else if (mw_release) begin
        mw_grant <= 1'b0;
      end
      else if (aw_admit && (aw_dest == DEST_DECERR)) begin
        mw_dest <= DEST_DECERR;              // DECERR locks the W path without a grant
      end

      if (grant_taken)                                        tenure_cnt <= '0;
      else if (aw_admit && (tenure_cnt < TENURE_Q))
                                                              tenure_cnt <= tenure_cnt + 1'b1;

      if      (aw_admit)         aw_committed <= 1'b0;
      else if (|s_awvalid)       aw_committed <= 1'b1;

      if      ( aw_admit && !cpl_valid) aw_pending <= aw_pending + 1'b1;
      else if (!aw_admit &&  cpl_valid) aw_pending <= aw_pending - 1'b1;

      if (w_ahead) begin
        if (aw_admit)                     w_ahead <= 1'b0;   // the AW this burst ran ahead of
      end
      else if ( aw_admit && !w_last_beat) w_pending <= w_pending + 1'b1;
      else if (!aw_admit &&  w_last_beat) begin
        if (w_pending == '0)              w_ahead   <= 1'b1;
        else                              w_pending <= w_pending - 1'b1;
      end
    end
  end

  a_no_grant_when_full: assert property (@(posedge aclk) disable iff (!arst_n)
    |arb_req |-> !mw_full)
    else $error("wr_port_ctrl: requested a grant while full");

  a_w_routed_once: assert property (@(posedge aclk) disable iff (!arst_n)
    $onehot0({s_wvalid, w_drop}))
    else $error("wr_port_ctrl: W beat routed to more than one destination");

  a_dest_stable: assert property (@(posedge aclk) disable iff (!arst_n)
    (w_pending != '0) |=> $stable(mw_dest))
    else $error("wr_port_ctrl: mw_dest changed with beats owed");

  a_aw_held: assert property (@(posedge aclk) disable iff (!arst_n)
    (|s_awvalid && !aw_admit) |=> |s_awvalid)
    else $error("wr_port_ctrl: AWVALID deasserted without a handshake");

  a_no_release_while_presenting: assert property (@(posedge aclk) disable iff (!arst_n)
    |s_awvalid |-> !mw_release)
    else $error("wr_port_ctrl: grant released with an AW on the wire");

endmodule : wr_port_ctrl
