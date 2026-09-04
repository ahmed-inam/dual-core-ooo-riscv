// Behavioural memory with configurable latency and inter-beat delay.

module sim_mem
  import coreaxi_pkg::*;
#(
  parameter int unsigned WORDS       = 16384,        // 64 KB
  parameter logic [31:0] POISON_WORD = 32'hBAD1_BAD1
) (
  input  logic      clk,
  input  logic      rst_n,

  input  int unsigned cfg_delay,        // extra cycles before the first beat
  input  int unsigned cfg_beat_delay,   // extra cycles between later beats

  input  axi_req_t  axi_req,
  output axi_resp_t axi_resp,

  input  logic [31:0] dbg_addr,
  output logic [31:0] dbg_data,

  output logic        err_overlap,   // read and write bursts overlapped
  output logic        err_range      // an access fell outside the array
);

  localparam int unsigned AW = (WORDS > 1) ? $clog2(WORDS) : 1;

  logic [31:0] mem [WORDS];

  initial for (int i = 0; i < WORDS; i++) mem[i] = POISON_WORD;

  function automatic logic in_range(input logic [31:0] byte_addr);
    return ({2'b0, byte_addr[31:2]} < 32'(WORDS));
  endfunction

  assign dbg_data = in_range(dbg_addr) ? mem[dbg_addr[AW+1:2]] : POISON_WORD;

  typedef enum logic [1:0] { R_IDLE, R_WAIT, R_BEAT, R_GAP } rstate_e;
  rstate_e             r_state, r_state_d;
  logic [31:0]         r_addr, r_addr_d;
  logic [AXI_LEN_W-1:0] r_left, r_left_d;
  logic [AXI_ID_W-1:0] r_id, r_id_d;
  logic [15:0]         r_cnt, r_cnt_d;
  logic                r_fixed, r_bad, r_fixed_d, r_bad_d;
  int unsigned         r_dly, r_bdly, r_dly_d, r_bdly_d;

  logic [31:0] r_word;
  assign r_word = in_range(r_addr) ? mem[r_addr[AW+1:2]] : POISON_WORD;

  always_comb begin
    r_state_d = r_state;
    r_addr_d  = r_addr;  r_left_d = r_left;  r_id_d = r_id;  r_cnt_d = r_cnt;
    r_dly_d   = r_dly;   r_bdly_d = r_bdly;
    r_fixed_d = r_fixed; r_bad_d  = r_bad;
    case (r_state)
      R_IDLE: if (axi_req.ar_valid) begin
          r_addr_d = axi_req.ar.addr;
          r_left_d = axi_req.ar.len;
          r_id_d = axi_req.ar.id;
          r_fixed_d = (axi_req.ar.burst == BURST_FIXED);
          r_bad_d = (axi_req.ar.burst == BURST_WRAP)
                     || !in_range(axi_req.ar.addr);
          r_cnt_d = '0;
          r_dly_d = cfg_delay;
          r_bdly_d = cfg_beat_delay;
          r_state_d = (cfg_delay == 0) ? R_BEAT : R_WAIT;
        end
        R_WAIT: if (r_cnt >= 16'(r_dly) - 16'd1) begin
          r_cnt_d = '0;
          r_state_d = R_BEAT;
        end else r_cnt_d = r_cnt + 16'd1;
        R_BEAT: if (axi_req.r_ready) begin
          if (r_left == '0) begin
            r_state_d = R_IDLE;
          end else begin
            r_left_d = r_left - 1'b1;
            if (!r_fixed) r_addr_d = r_addr + 32'd4;
            r_cnt_d = '0;
            r_state_d = (r_bdly == 0) ? R_BEAT : R_GAP;
          end
        end
        R_GAP: if (r_cnt >= 16'(r_bdly) - 16'd1) begin
          r_cnt_d = '0;
          r_state_d = R_BEAT;
        end else r_cnt_d = r_cnt + 16'd1;
        default: r_state_d = R_IDLE;
      endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_state <= R_IDLE;
      r_addr  <= '0; r_left <= '0; r_id <= '0; r_cnt <= '0;
      r_dly   <= '0; r_bdly <= '0;
      r_fixed <= 1'b0; r_bad <= 1'b0;
    end else begin
      r_state <= r_state_d; r_addr <= r_addr_d; r_left <= r_left_d;
      r_id    <= r_id_d;    r_cnt  <= r_cnt_d;  r_dly  <= r_dly_d;
      r_bdly  <= r_bdly_d;  r_fixed<= r_fixed_d; r_bad <= r_bad_d;
    end
  end

  typedef enum logic [2:0] { W_IDLE, W_DATA, W_BGAP, W_GAP, W_RESP } wstate_e;
  wstate_e             w_state, w_state_d;
  logic [31:0]         w_addr, w_addr_d;
  logic [AXI_ID_W-1:0] w_id, w_id_d;
  logic [15:0]         w_cnt, w_cnt_d;
  logic                w_fixed, w_bad, w_fixed_d, w_bad_d;
  int unsigned         w_dly, w_bdly, w_dly_d, w_bdly_d;

  always_comb begin
    w_state_d = w_state;
    w_addr_d  = w_addr;  w_id_d   = w_id;   w_cnt_d = w_cnt;
    w_dly_d   = w_dly;   w_bdly_d = w_bdly;
    w_fixed_d = w_fixed; w_bad_d  = w_bad;
      case (w_state)
        W_IDLE: if (axi_req.aw_valid) begin
          w_addr_d = axi_req.aw.addr;
          w_id_d = axi_req.aw.id;
          w_fixed_d = (axi_req.aw.burst == BURST_FIXED);
          w_dly_d = cfg_delay;
          w_bdly_d = cfg_beat_delay;
          w_bad_d = (axi_req.aw.burst == BURST_WRAP)
                     || !in_range(axi_req.aw.addr);
          w_cnt_d = '0;
          w_state_d = W_DATA;
        end
        W_DATA: if (axi_req.w_valid) begin
          if (axi_req.w.last) begin
            w_cnt_d = '0;
            w_state_d = (w_dly == 0) ? W_RESP : W_GAP;
          end else begin
            if (!w_fixed) w_addr_d = w_addr + 32'd4;
            w_cnt_d = '0;
            if (w_bdly != 0) w_state_d = W_BGAP;   // back to W_DATA, not W_RESP
          end
        end
        W_BGAP: if (w_cnt >= 16'(w_bdly) - 16'd1) begin
          w_cnt_d = '0;
          w_state_d = W_DATA;
        end else w_cnt_d = w_cnt + 16'd1;
        W_GAP: if (w_cnt >= 16'(w_dly) - 16'd1) begin
          w_cnt_d = '0;
          w_state_d = W_RESP;
        end else w_cnt_d = w_cnt + 16'd1;
        W_RESP: if (axi_req.b_ready) w_state_d = W_IDLE;
        default: w_state_d = W_IDLE;
      endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_state <= W_IDLE;
      w_addr  <= '0; w_id <= '0; w_cnt <= '0;
      w_dly   <= '0; w_bdly <= '0;
      w_fixed <= 1'b0; w_bad <= 1'b0;
    end else begin
      w_state <= w_state_d; w_addr <= w_addr_d; w_id <= w_id_d;
      w_cnt   <= w_cnt_d;   w_dly  <= w_dly_d;  w_bdly <= w_bdly_d;
      w_fixed <= w_fixed_d; w_bad  <= w_bad_d;
      if ((w_state == W_DATA) && axi_req.w_valid && in_range(w_addr))
        for (int b = 0; b < AXI_STRB_W; b++)
          if (axi_req.w.strb[b])
            mem[w_addr[AW+1:2]][b*8 +: 8] <= axi_req.w.data[b*8 +: 8];
    end
  end

  always_comb begin
    axi_resp          = '0;
    axi_resp.ar_ready = (r_state == R_IDLE);
    axi_resp.r_valid  = (r_state == R_BEAT);
    axi_resp.r.id     = r_id;
    axi_resp.r.data   = r_bad ? POISON_WORD : r_word;
    axi_resp.r.resp   = r_bad ? RESP_SLVERR : RESP_OKAY;
    axi_resp.r.last   = (r_state == R_BEAT) && (r_left == '0);

    axi_resp.aw_ready = (w_state == W_IDLE);
    axi_resp.w_ready  = (w_state == W_DATA);
    axi_resp.b_valid  = (w_state == W_RESP);
    axi_resp.b.id     = w_id;
    axi_resp.b.resp   = w_bad ? RESP_SLVERR : RESP_OKAY;
  end

  assign err_range   = (r_state != R_IDLE && r_bad) || (w_state != W_IDLE && w_bad);
  assign err_overlap = (r_state != R_IDLE) && (w_state != W_IDLE)
                    && (r_addr[AW+1:2] == w_addr[AW+1:2]);

  always_ff @(posedge clk) if (rst_n) begin
    if (err_overlap)
      $display("[sim_mem] ERROR: read and write hit the SAME WORD in one cycle (r=%08h w=%08h) -- the fabric provided no ordering", r_addr, w_addr);
    if (r_state != R_IDLE && r_bad)
      $display("[sim_mem] ERROR: bad read transaction (WRAP burst or address %08h out of range)", r_addr);
    if (w_state != W_IDLE && w_bad)
      $display("[sim_mem] ERROR: bad write transaction (WRAP burst or address %08h out of range)", w_addr);
  end

endmodule
