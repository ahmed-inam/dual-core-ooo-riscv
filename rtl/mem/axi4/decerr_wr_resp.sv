// Local write responder for an address that decodes nowhere.

module decerr_wr_resp
  import axi4_pkg::*;
(
  input  logic                aclk,
  input  logic                arst_n,

  input  logic                aw_accept,   // AW admitted with dest == DEST_DECERR
  input  logic [ID_WIDTH-1:0] aw_id,

  input  logic                w_beat,      // a W beat is being dropped this cycle
  input  logic                w_last,

  output logic                busy,        // block a second DECERR AW while set

  output logic                b_valid,
  output logic [ID_WIDTH-1:0] b_id,
  output logic [1:0]          b_resp,
  input  logic                b_ready
);

  typedef enum logic [1:0] {
    IDLE       = 2'd0,   // no bad write in flight
    DRAINING   = 2'd1,   // AW accepted, swallowing the burst's beats
    RESPONDING = 2'd2    // beats gone, one B owed
  } state_e;

  state_e state, next_state;

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) state <= IDLE;
    else         state <= next_state;
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE:       if (aw_accept)        next_state = DRAINING;
      DRAINING:   if (w_beat && w_last) next_state = RESPONDING;
      RESPONDING: if (b_ready)          next_state = IDLE;
      default:                          next_state = IDLE;
    endcase
  end

  always_comb begin
    busy   = (state != IDLE);
    b_resp = RESP_DECERR;
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) b_valid <= 1'b0;
    else         b_valid <= (next_state == RESPONDING);
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n)        b_id <= '0;
    else if (aw_accept) b_id <= aw_id;   // echo: the master matches on BID
  end

  a_drain_only_when_owed: assert property (@(posedge aclk) disable iff (!arst_n)
    w_beat |-> (state == DRAINING))
    else $error("decerr_wr_resp: W beat dropped with no burst outstanding");

  a_one_at_a_time: assert property (@(posedge aclk) disable iff (!arst_n)
    aw_accept |-> !busy)
    else $error("decerr_wr_resp: second DECERR AW admitted while busy");

endmodule : decerr_wr_resp
