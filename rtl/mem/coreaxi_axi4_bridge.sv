// Stateless shim from the core bus to AXI4.
module coreaxi_axi4_bridge
  import coreaxi_pkg::*;
(
  input  axi_req_t  core_req,
  output axi_resp_t core_resp,

  axi4_if.mst       xbar
);

  if (AXI_ID_W   != axi4_pkg::ID_WIDTH) begin : g_chk_id
    $error("bridge: coreaxi AXI_ID_W (%0d) != axi4 ID_WIDTH (%0d)",
           AXI_ID_W, axi4_pkg::ID_WIDTH);
  end
  if (AXI_ADDR_W != axi4_pkg::ADDR_WIDTH) begin : g_chk_addr
    $error("bridge: address width mismatch");
  end
  if (AXI_DATA_W != axi4_pkg::DATA_WIDTH) begin : g_chk_data
    $error("bridge: data width mismatch");
  end

  assign xbar.awid    = core_req.aw.id;
  assign xbar.awaddr  = core_req.aw.addr;
  assign xbar.awlen   = 8'(core_req.aw.len);
  assign xbar.awsize  = core_req.aw.size;
  assign xbar.awburst = 2'(core_req.aw.burst);   // explicit: enum -> plain 2 bits
  assign xbar.awvalid = core_req.aw_valid;

  assign xbar.wdata   = core_req.w.data;
  assign xbar.wstrb   = core_req.w.strb;
  assign xbar.wlast   = core_req.w.last;
  assign xbar.wvalid  = core_req.w_valid;

  assign xbar.bready  = core_req.b_ready;

  assign xbar.arid    = core_req.ar.id;
  assign xbar.araddr  = core_req.ar.addr;
  assign xbar.arlen   = 8'(core_req.ar.len);
  assign xbar.arsize  = core_req.ar.size;
  assign xbar.arburst = 2'(core_req.ar.burst);
  assign xbar.arvalid = core_req.ar_valid;

  assign xbar.rready  = core_req.r_ready;

  assign core_resp.aw_ready = xbar.awready;
  assign core_resp.w_ready  = xbar.wready;
  assign core_resp.ar_ready = xbar.arready;

  assign core_resp.b.id     = xbar.bid;
  assign core_resp.b.resp   = axi_resp_e'(xbar.bresp);
  assign core_resp.b_valid  = xbar.bvalid;

  assign core_resp.r.id     = xbar.rid;
  assign core_resp.r.data   = xbar.rdata;
  assign core_resp.r.resp   = axi_resp_e'(xbar.rresp);
  assign core_resp.r.last   = xbar.rlast;
  assign core_resp.r_valid  = xbar.rvalid;

`ifndef SYNTHESIS
  always_comb begin
    if (xbar.bvalid && (2'(core_resp.b.resp) !== xbar.bresp))
      $fatal(1, "bridge: bresp %b did not round-trip through axi_resp_e", xbar.bresp);
    if (xbar.rvalid && (2'(core_resp.r.resp) !== xbar.rresp))
      $fatal(1, "bridge: rresp %b did not round-trip through axi_resp_e", xbar.rresp);
    if (core_req.aw_valid && (2'(core_req.aw.burst) !== xbar.awburst))
      $fatal(1, "bridge: awburst did not round-trip");
    if (core_req.ar_valid && (2'(core_req.ar.burst) !== xbar.arburst))
      $fatal(1, "bridge: arburst did not round-trip");
    if (AXI_LEN_W > 8)
      $fatal(1, "bridge: coreaxi AXI_LEN_W > 8 would truncate awlen/arlen");
  end
`endif

endmodule
