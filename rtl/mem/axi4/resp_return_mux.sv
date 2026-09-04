// Returns responses from either slave or the local error responder.

module resp_return_mux
  import axi4_pkg::*;
#(
  parameter int  PAYLOAD_W    = 2,       // B: {resp}. R: {data, resp}
  parameter bit  BURST_ATOMIC = 1'b0,    // R: hold the selection until RLAST
  parameter bit  MY_TAG       = 1'b0     // 0 = M0, 1 = M1
) (
  input  logic                        aclk,
  input  logic                        arst_n,

  input  logic [1:0]                  s_valid,
  input  logic [1:0][M_ID_W-1:0]      s_id,
  input  logic [1:0][PAYLOAD_W-1:0]   s_payload,
  input  logic [1:0]                  s_last,
  output logic [1:0]                  s_ready,

  input  logic                        d_valid,
  input  logic [ID_WIDTH-1:0]         d_id,
  input  logic [PAYLOAD_W-1:0]        d_payload,
  input  logic                        d_last,
  output logic                        d_ready,

  output logic                        m_valid,
  output logic [ID_WIDTH-1:0]         m_id,
  output logic [PAYLOAD_W-1:0]        m_payload,
  output logic                        m_last,
  input  logic                        m_ready,

  output logic                        cpl_valid,
  output logic [ID_WIDTH-1:0]         cpl_id
);

  localparam logic [1:0] SEL_S0 = 2'd0;
  localparam logic [1:0] SEL_S1 = 2'd1;
  localparam logic [1:0] SEL_DE = 2'd2;

  logic [2:0] req;
  assign req[0] = s_valid[0] && (s_id[0][ID_WIDTH] == MY_TAG);
  assign req[1] = s_valid[1] && (s_id[1][ID_WIDTH] == MY_TAG);
  assign req[2] = d_valid;

  logic [1:0] sel, last_sel, next_sel;
  logic       sel_valid, next_found, held, done;
  logic       mid_burst;
  logic [1:0] ord [3];

  assign done = m_valid && m_ready && (BURST_ATOMIC ? m_last : 1'b1);

  assign held = sel_valid && !done && (mid_burst || req[sel]);

  always_comb begin
    case (last_sel)
      SEL_S0:  begin ord[0] = SEL_S1; ord[1] = SEL_DE; ord[2] = SEL_S0; end
      SEL_S1:  begin ord[0] = SEL_DE; ord[1] = SEL_S0; ord[2] = SEL_S1; end
      SEL_DE:  begin ord[0] = SEL_S0; ord[1] = SEL_S1; ord[2] = SEL_DE; end
      default: begin ord[0] = SEL_S0; ord[1] = SEL_S1; ord[2] = SEL_DE; end
    endcase
  end

  always_comb begin
    next_sel   = SEL_S0;
    next_found = 1'b0;
    for (int k = 0; k < 3; k++) begin
      if (!next_found && req[ord[k]]) begin
        next_sel   = ord[k];
        next_found = 1'b1;
      end
    end
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) mid_burst <= 1'b0;
    else if (BURST_ATOMIC && m_valid && m_ready && !m_last) mid_burst <= 1'b1;
    else if (done)                                          mid_burst <= 1'b0;
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      sel       <= SEL_S0;
      sel_valid <= 1'b0;
      last_sel  <= SEL_S0;
    end
    else if (!held) begin
      sel_valid <= next_found;
      if (next_found) begin
        sel      <= next_sel;
        last_sel <= next_sel;
      end
    end
  end

  always_comb begin
    case (sel)
      SEL_S0:  begin m_id = s_id[0][ID_WIDTH-1:0]; m_payload = s_payload[0]; m_last = s_last[0]; end
      SEL_S1:  begin m_id = s_id[1][ID_WIDTH-1:0]; m_payload = s_payload[1]; m_last = s_last[1]; end
      default: begin m_id = d_id;                  m_payload = d_payload;    m_last = d_last;    end
    endcase
  end

  assign m_valid    = sel_valid && req[sel];
  assign s_ready[0] = m_valid && (sel == SEL_S0) && m_ready;
  assign s_ready[1] = m_valid && (sel == SEL_S1) && m_ready;
  assign d_ready    = m_valid && (sel == SEL_DE) && m_ready;

  assign cpl_valid = done;
  assign cpl_id    = m_id;

  if (BURST_ATOMIC) begin : g_atomic_chk
    a_burst_atomic: assert property (@(posedge aclk) disable iff (!arst_n)
      (mid_burst && !done) |=> $stable(sel))
      else $error("resp_return_mux: selection moved mid-burst");
  end

  a_no_phantom: assert property (@(posedge aclk) disable iff (!arst_n)
    m_valid |-> req[sel])
    else $error("resp_return_mux: valid asserted with no source request");

  a_sready0_implies_req: assert property (@(posedge aclk) disable iff (!arst_n)
    s_ready[0] |-> req[0])
    else $error("resp_return_mux: s_ready[0] without a matching request");
  a_sready1_implies_req: assert property (@(posedge aclk) disable iff (!arst_n)
    s_ready[1] |-> req[1])
    else $error("resp_return_mux: s_ready[1] without a matching request");
  a_dready_implies_req: assert property (@(posedge aclk) disable iff (!arst_n)
    d_ready |-> req[2])
    else $error("resp_return_mux: d_ready without decerr valid");

endmodule : resp_return_mux
