// Two-input round-robin, held until acknowledged.

module rr_arbiter #(
  parameter int HOLD_IDLE_GRANT = 1
) (
  input  logic       aclk,
  input  logic       arst_n,
  input  logic [1:0] req,
  input  logic [1:0] ack,
  output logic [1:0] gnt,
  output logic       gnt_valid
);

  typedef enum logic [1:0] {
    IDLE   = 2'd0,   // no grant outstanding
    GNT_M0 = 2'd1,   // M0 owns the slave
    GNT_M1 = 2'd2    // M1 owns the slave
  } arb_state_e;

  arb_state_e state, next_state;
  logic       last_gnt;          // who won most recently -- the only fairness state
  logic       winner, held;

  always_comb begin
    if (req[0] && req[1]) winner = ~last_gnt;
    else if (req[0])      winner = 1'b0;
    else                  winner = 1'b1;
  end

  assign held = (state != IDLE) && !(|(gnt & ack))
                && (HOLD_IDLE_GRANT || (|(gnt & req)));

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) state <= IDLE;
    else         state <= next_state;
  end

  always_comb begin
    next_state = state;
    if (!held) begin
      if (!(|req))      next_state = IDLE;
      else if (winner)  next_state = GNT_M1;
      else              next_state = GNT_M0;
    end
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n)                     last_gnt <= 1'b0;
    else if (!held && (|req))        last_gnt <= winner;
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      gnt       <= 2'b00;
      gnt_valid <= 1'b0;
    end
    else begin
      case (next_state)
        GNT_M0:  gnt <= 2'b01;
        GNT_M1:  gnt <= 2'b10;
        default: gnt <= 2'b00;
      endcase
      gnt_valid <= (next_state != IDLE);
    end
  end

  if (!HOLD_IDLE_GRANT) begin : g_stale_chk
    a_no_stale_grant: assert property (@(posedge aclk) disable iff (!arst_n)
      (gnt_valid && !(|(gnt & req)) && !(|(gnt & ack))) |=> (!gnt_valid || $changed(gnt)))
      else $error("rr_arbiter: stale grant persisted with no requester");
  end

endmodule : rr_arbiter
