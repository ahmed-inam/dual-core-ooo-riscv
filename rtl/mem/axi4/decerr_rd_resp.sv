// Local read responder for an address that decodes nowhere.

module decerr_rd_resp
  import axi4_pkg::*;
(
  input  logic                  aclk,
  input  logic                  arst_n,

  input  logic                  ar_accept,   // AR admitted with dest == DEST_DECERR
  input  logic [ID_WIDTH-1:0]   ar_id,
  input  logic [7:0]            ar_len,

  output logic                  busy,        // block a second DECERR AR while set

  output logic                  r_valid,
  output logic [ID_WIDTH-1:0]   r_id,
  output logic [DATA_WIDTH-1:0] r_data,
  output logic [1:0]            r_resp,
  output logic                  r_last,
  input  logic                  r_ready
);

  localparam logic [DATA_WIDTH-1:0] ERR_DATA = 32'hDECE_DECE;

  typedef enum logic [1:0] {
    IDLE      = 2'd0,   // no error read in flight
    STREAMING = 2'd1,   // emitting beats, more than one still owed
    LAST_BEAT = 2'd2    // emitting the final beat, RLAST high
  } state_e;

  state_e     state, next_state;
  logic [7:0] beats_left;

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) state <= IDLE;
    else         state <= next_state;
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE:      if (ar_accept) next_state = (ar_len == 8'd0) ? LAST_BEAT : STREAMING;
      STREAMING: if (r_ready)   next_state = (beats_left == 8'd1) ? LAST_BEAT : STREAMING;
      LAST_BEAT: if (r_ready)   next_state = IDLE;
      default:                  next_state = IDLE;
    endcase
  end

  always_comb begin
    busy   = (state != IDLE);
    r_resp = RESP_DECERR;
    r_data = ERR_DATA;
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      r_valid <= 1'b0;
      r_last  <= 1'b0;
    end
    else begin
      r_valid <= (next_state != IDLE);
      r_last  <= (next_state == LAST_BEAT);
    end
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      beats_left <= '0;
      r_id       <= '0;
    end
    else if (ar_accept) begin
      beats_left <= ar_len;
      r_id       <= ar_id;                    // echo: master matches on RID
    end
    else if (r_valid && r_ready && (beats_left != '0)) begin
      beats_left <= beats_left - 8'd1;
    end
  end

  a_one_at_a_time: assert property (@(posedge aclk) disable iff (!arst_n)
    ar_accept |-> !busy)
    else $error("decerr_rd_resp: second DECERR AR admitted while busy");

  a_last_is_last: assert property (@(posedge aclk) disable iff (!arst_n)
    (state == LAST_BEAT) |-> (beats_left == '0))
    else $error("decerr_rd_resp: RLAST asserted with beats still owed");

endmodule : decerr_rd_resp
