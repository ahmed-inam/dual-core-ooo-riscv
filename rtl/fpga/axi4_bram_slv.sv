// Synthesizable AXI4 memory slave over an inferred block RAM: one read and one
// write in flight, INCR bursts of 32-bit beats, byte strobes honoured.
module axi4_bram_slv
  import coreaxi_pkg::*;
#(
  parameter int unsigned WORDS = 65536,          // 256 KB
  parameter              INIT_HEX = ""           // optional $readmemh image
) (
  input  logic      clk,
  input  logic      rst_n,
  input  axi_req_t  axi_req,
  output axi_resp_t axi_resp
);

  localparam int unsigned AW = $clog2(WORDS);

  logic [31:0] mem [WORDS];

  if (INIT_HEX != "") begin : g_init
    initial $readmemh(INIT_HEX, mem);
  end

  typedef enum logic [1:0] { R_IDLE, R_READ, R_BEAT } rst_e;
  typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } wst_e;
  rst_e r_st;
  wst_e w_st;

  logic [AW-1:0] r_word, w_word;
  logic [7:0]    r_left;
  logic [3:0]    r_id, w_id;
  logic [31:0]   r_data;
  logic          r_last;

  // Read side: the address is latched, one beat is fetched per cycle.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_st <= R_IDLE; r_word <= '0; r_left <= '0; r_id <= '0; r_data <= '0; r_last <= 1'b0;
    end else begin
      unique case (r_st)
        R_IDLE: if (axi_req.ar_valid) begin
          r_word <= axi_req.ar.addr[AW+1:2];
          r_left <= axi_req.ar.len;
          r_id   <= axi_req.ar.id;
          r_st   <= R_READ;
        end
        R_READ: begin
          r_data <= mem[r_word];
          r_last <= (r_left == 8'd0);
          r_st   <= R_BEAT;
        end
        R_BEAT: if (axi_req.r_ready) begin
          if (r_left == 8'd0) r_st <= R_IDLE;
          else begin
            r_left <= r_left - 8'd1;
            r_word <= r_word + 1'b1;
            r_st   <= R_READ;
          end
        end
        default: r_st <= R_IDLE;
      endcase
    end
  end

  // Write side: each accepted beat lands in the array with its byte strobes.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_st <= W_IDLE; w_word <= '0; w_id <= '0;
    end else begin
      unique case (w_st)
        W_IDLE: if (axi_req.aw_valid) begin
          w_word <= axi_req.aw.addr[AW+1:2];
          w_id   <= axi_req.aw.id;
          w_st   <= W_DATA;
        end
        W_DATA: if (axi_req.w_valid) begin
          w_word <= w_word + 1'b1;
          if (axi_req.w.last) w_st <= W_RESP;
        end
        W_RESP: if (axi_req.b_ready) w_st <= W_IDLE;
        default: w_st <= W_IDLE;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if ((w_st == W_DATA) && axi_req.w_valid)
      for (int b = 0; b < 4; b++)
        if (axi_req.w.strb[b]) mem[w_word][b*8 +: 8] <= axi_req.w.data[b*8 +: 8];
  end

  always_comb begin
    axi_resp          = '0;
    axi_resp.ar_ready = (r_st == R_IDLE);
    axi_resp.r_valid  = (r_st == R_BEAT);
    axi_resp.r.id     = r_id;
    axi_resp.r.data   = r_data;
    axi_resp.r.resp   = RESP_OKAY;
    axi_resp.r.last   = r_last;
    axi_resp.aw_ready = (w_st == W_IDLE);
    axi_resp.w_ready  = (w_st == W_DATA);
    axi_resp.b_valid  = (w_st == W_RESP);
    axi_resp.b.id     = w_id;
    axi_resp.b.resp   = RESP_OKAY;
  end

endmodule
