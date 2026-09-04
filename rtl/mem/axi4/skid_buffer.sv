// Two-register skid buffer with registered outputs.

module skid_buffer #(
  parameter int W = 8
) (
  input  logic         aclk,
  input  logic         arst_n,

  input  logic         s_valid,
  output logic         s_ready,
  input  logic [W-1:0] s_data,

  output logic         m_valid,
  input  logic         m_ready,
  output logic [W-1:0] m_data
);

  typedef enum logic [1:0] {
    EMPTY = 2'd0,   // nothing held
    ONE   = 2'd1,   // output slot occupied
    FULL  = 2'd2    // output + catch slot occupied
  } skid_state_e;

  skid_state_e  state, next_state;
  logic [W-1:0] temp_data;

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) state <= EMPTY;
    else         state <= next_state;
  end

  always_comb begin
    next_state = state;
    case (state)
      EMPTY:   if (s_valid)                  next_state = ONE;    // first transfer arrives
      ONE:     if (s_valid && !m_ready)      next_state = FULL;   // arrival with the output stalled -- the skid
               else if (!s_valid && m_ready) next_state = EMPTY;  // output taken, nothing behind it
      FULL:    if (m_ready)                  next_state = ONE;    // one beat leaves; s_ready is low so none arrives
      default:                               next_state = FULL;   // illegal encoding: drain out, do not drop
    endcase
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) m_valid <= 1'b0;
    else         m_valid <= (next_state != EMPTY);
  end
  assign s_ready = (state != FULL) && arst_n;

  always_ff @(posedge aclk) begin
    case (state)
      EMPTY:   if (s_valid) m_data <= s_data;
      ONE:     if (s_valid) begin
                 if (m_ready) m_data    <= s_data;
                 else         temp_data <= s_data;
               end
      FULL:    if (m_ready) m_data <= temp_data;
      default: ;
    endcase
  end

endmodule : skid_buffer
