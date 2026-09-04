// Turns one cache-line fill into an AXI4 burst of four beats.

module axi_adapter
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic              req,
  output logic              gnt,
  input  word_t             addr,
  input  logic              we,
  input  logic              word_mode,   // 1 = single word, 0 = whole line
  input  logic [3:0]        wstrb,
  input  logic [LINE_W-1:0] wdata,
  output logic              rvalid,
  output logic [LINE_W-1:0] rdata,
  output logic              rerr,        // with rvalid: SLVERR or DECERR seen

  output axi_req_t  axi_req,
  input  axi_resp_t axi_resp
);

  localparam int unsigned BEATS = BEATS_PER_LINE;

  typedef enum logic [2:0] {
    A_IDLE,
    A_AR,        // present the read address
    A_R,         // collect beats
    A_AW,        // present the write address
    A_W,         // stream beats
    A_B,         // await the write response
    A_DONE       // one cycle of rvalid upstream
  } astate_e;

  astate_e astate_q, astate_d;

  word_t             addr_q,  addr_d;
  logic              we_q,    we_d;
  logic              word_q,  word_d;
  logic [3:0]        wstrb_q, wstrb_d;
  logic [LINE_W-1:0] buf_q,   buf_d;
  logic [2:0]        beat_q,  beat_d;
  logic              err_q,   err_d;

  logic [7:0] axlen;
  assign axlen = word_q ? 8'd0 : 8'(BEATS - 1);

  assign gnt = req && (astate_q == A_IDLE);

  always_comb begin
    astate_d = astate_q;
    addr_d   = addr_q;
    we_d     = we_q;
    word_d   = word_q;
    wstrb_d  = wstrb_q;
    buf_d    = buf_q;
    beat_d   = beat_q;
    err_d    = err_q;

    case (astate_q)
      A_IDLE: if (req) begin
        addr_d  = {addr[31:2], 2'b00};
        we_d    = we;
        word_d  = word_mode;
        wstrb_d = wstrb;
        buf_d   = wdata;
        beat_d  = '0;
        err_d   = 1'b0;
        astate_d = we ? A_AW : A_AR;
      end

      A_AR: if (axi_resp.ar_ready) astate_d = A_R;

      A_R: if (axi_resp.r_valid) begin
        buf_d[beat_q*32 +: 32] = axi_resp.r.data;
        if (axi_resp.r.resp[1]) err_d = 1'b1;
        if (axi_resp.r.last) astate_d = A_DONE;
        else                 beat_d   = beat_q + 3'd1;
      end

      A_AW: if (axi_resp.aw_ready) astate_d = A_W;

      A_W: if (axi_resp.w_ready) begin
        if (beat_q == (word_q ? 3'd0 : 3'(BEATS - 1))) astate_d = A_B;
        else                                           beat_d   = beat_q + 3'd1;
      end

      A_B: if (axi_resp.b_valid) begin
        if (axi_resp.b.resp[1]) err_d = 1'b1;
        astate_d = A_DONE;
      end

      A_DONE: astate_d = A_IDLE;

      default: astate_d = A_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      astate_q <= A_IDLE;
      addr_q <= '0; we_q <= 1'b0; word_q <= 1'b0; wstrb_q <= '0;
      buf_q  <= '0; beat_q <= '0; err_q <= 1'b0;
    end else begin
      astate_q <= astate_d;
      addr_q <= addr_d; we_q <= we_d; word_q <= word_d; wstrb_q <= wstrb_d;
      buf_q  <= buf_d;  beat_q <= beat_d; err_q <= err_d;
    end
  end

  always_comb begin
    axi_req = AXI_REQ_NONE;

    axi_req.ar = '{ id: 4'h0, addr: addr_q, len: axlen,
                    size: AXI_SIZE_4B, burst: BURST_INCR };
    axi_req.ar_valid = (astate_q == A_AR);
    axi_req.r_ready  = (astate_q == A_R);

    axi_req.aw = '{ id: 4'h0, addr: addr_q, len: axlen,
                    size: AXI_SIZE_4B, burst: BURST_INCR };
    axi_req.aw_valid = (astate_q == A_AW);

    axi_req.w = '{ data: buf_q[beat_q*32 +: 32],
                   strb: word_q ? wstrb_q : 4'hF,
                   last: (beat_q == (word_q ? 3'd0 : 3'(BEATS - 1))) };
    axi_req.w_valid = (astate_q == A_W);

    axi_req.b_ready = (astate_q == A_B);
  end

  assign rvalid = (astate_q == A_DONE);
  assign rdata  = buf_q;
  assign rerr   = err_q;

`ifdef AXI_CHECK
  axi4_assert #(.ID_W(AXI_ID_W)) u_chk (
    .aclk(clk), .arst_n(rst_n), .ext_rst_n(rst_n),
    .awid(axi_req.aw.id), .awaddr(axi_req.aw.addr), .awlen(axi_req.aw.len),
    .awsize(axi_req.aw.size), .awburst(axi_req.aw.burst),
    .awvalid(axi_req.aw_valid), .awready(axi_resp.aw_ready),
    .wdata(axi_req.w.data), .wstrb(axi_req.w.strb), .wlast(axi_req.w.last),
    .wvalid(axi_req.w_valid), .wready(axi_resp.w_ready),
    .bid(axi_resp.b.id), .bresp(axi_resp.b.resp),
    .bvalid(axi_resp.b_valid), .bready(axi_req.b_ready),
    .arid(axi_req.ar.id), .araddr(axi_req.ar.addr), .arlen(axi_req.ar.len),
    .arsize(axi_req.ar.size), .arburst(axi_req.ar.burst),
    .arvalid(axi_req.ar_valid), .arready(axi_resp.ar_ready),
    .rid(axi_resp.r.id), .rdata(axi_resp.r.data), .rresp(axi_resp.r.resp),
    .rlast(axi_resp.r.last), .rvalid(axi_resp.r_valid), .rready(axi_req.r_ready)
  );
`endif

endmodule
