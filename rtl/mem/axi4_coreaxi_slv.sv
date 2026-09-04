// Slave-side shim between the AXI4 interface and the core bus.
module axi4_coreaxi_slv
  import coreaxi_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  axi4_if.slv       sif,

  output axi_req_t  mem_req,
  input  axi_resp_t mem_resp
);

  localparam int TAG_W = axi4_pkg::M_ID_W - int'(AXI_ID_W);

  if (AXI_ADDR_W != axi4_pkg::ADDR_WIDTH) begin : g_chk_addr
    $error("axi4_coreaxi_slv: address width mismatch (%0d vs %0d)",
           AXI_ADDR_W, axi4_pkg::ADDR_WIDTH);
  end
  if (AXI_DATA_W != axi4_pkg::DATA_WIDTH) begin : g_chk_data
    $error("axi4_coreaxi_slv: data width mismatch");
  end
  if (axi4_pkg::M_ID_W < int'(AXI_ID_W)) begin : g_chk_id
    $error("axi4_coreaxi_slv: slave-facing id (%0d) narrower than coreaxi id (%0d)",
           axi4_pkg::M_ID_W, AXI_ID_W);
  end

  // The memory behind this shim may pipeline transactions: keep one tag per
  // outstanding read and per outstanding write, returned in order.
  localparam int unsigned OUT_N = 4;
  logic [TAG_W-1:0] rtag_q [OUT_N];
  logic [TAG_W-1:0] wtag_q [OUT_N];
  logic [$clog2(OUT_N)-1:0] rhead_q, rtail_q, whead_q, wtail_q;
  logic [$clog2(OUT_N):0]   rcnt_q, wcnt_q;

  wire ar_hs = sif.arvalid && sif.arready;
  wire aw_hs = sif.awvalid && sif.awready;
  wire r_end = sif.rvalid  && sif.rready && sif.rlast;
  wire b_end = sif.bvalid  && sif.bready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rhead_q <= '0; rtail_q <= '0; rcnt_q <= '0;
      whead_q <= '0; wtail_q <= '0; wcnt_q <= '0;
      for (int i = 0; i < OUT_N; i++) begin rtag_q[i] <= '0; wtag_q[i] <= '0; end
    end else begin
      if (ar_hs) begin rtag_q[rtail_q] <= sif.arid[axi4_pkg::M_ID_W-1 -: TAG_W]; rtail_q <= rtail_q + 1'b1; end
      if (r_end) rhead_q <= rhead_q + 1'b1;
      rcnt_q <= rcnt_q + ($bits(rcnt_q))'(ar_hs) - ($bits(rcnt_q))'(r_end);
      if (aw_hs) begin wtag_q[wtail_q] <= sif.awid[axi4_pkg::M_ID_W-1 -: TAG_W]; wtail_q <= wtail_q + 1'b1; end
      if (b_end) whead_q <= whead_q + 1'b1;
      wcnt_q <= wcnt_q + ($bits(wcnt_q))'(aw_hs) - ($bits(wcnt_q))'(b_end);
    end
  end

  logic rfull, wfull;
  assign rfull = (rcnt_q == ($bits(rcnt_q))'(OUT_N));
  assign wfull = (wcnt_q == ($bits(wcnt_q))'(OUT_N));

  assign mem_req.ar.id    = sif.arid[AXI_ID_W-1:0];
  assign mem_req.ar.addr  = sif.araddr;
  assign mem_req.ar.len   = sif.arlen[AXI_LEN_W-1:0];
  assign mem_req.ar.size  = sif.arsize;
  assign mem_req.ar.burst = axi_burst_e'(sif.arburst);
  assign mem_req.ar_valid = sif.arvalid && !rfull;
  assign mem_req.r_ready  = sif.rready;

  assign mem_req.aw.id    = sif.awid[AXI_ID_W-1:0];
  assign mem_req.aw.addr  = sif.awaddr;
  assign mem_req.aw.len   = sif.awlen[AXI_LEN_W-1:0];
  assign mem_req.aw.size  = sif.awsize;
  assign mem_req.aw.burst = axi_burst_e'(sif.awburst);
  assign mem_req.aw_valid = sif.awvalid && !wfull;

  assign mem_req.w.data   = sif.wdata;
  assign mem_req.w.strb   = sif.wstrb;
  assign mem_req.w.last   = sif.wlast;
  assign mem_req.w_valid  = sif.wvalid;
  assign mem_req.b_ready  = sif.bready;

  assign sif.arready = mem_resp.ar_ready && !rfull;
  assign sif.awready = mem_resp.aw_ready && !wfull;
  assign sif.wready  = mem_resp.w_ready;

  assign sif.rid     = {rtag_q[rhead_q], mem_resp.r.id};
  assign sif.rdata   = mem_resp.r.data;
  assign sif.rresp   = 2'(mem_resp.r.resp);
  assign sif.rlast   = mem_resp.r.last;
  assign sif.rvalid  = mem_resp.r_valid;

  assign sif.bid     = {wtag_q[whead_q], mem_resp.b.id};
  assign sif.bresp   = 2'(mem_resp.b.resp);
  assign sif.bvalid  = mem_resp.b_valid;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (sif.rvalid && (rcnt_q == '0))
      $fatal(1, "axi4_coreaxi_slv: read response with no outstanding read");
    if (sif.bvalid && (wcnt_q == '0))
      $fatal(1, "axi4_coreaxi_slv: write response with no outstanding write");
  end
`endif

endmodule
