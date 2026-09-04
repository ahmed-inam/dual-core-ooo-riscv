// Gate for the slave-side shim.
module tb_axi4_coreaxi_slv
  import coreaxi_pkg::*;
();
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0;
  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  axi4_if #(.ID_W(axi4_pkg::M_ID_W)) sif (.aclk(clk), .arst_n(rst_n));

  axi_req_t  mem_req;
  axi_resp_t mem_resp;

  axi4_coreaxi_slv dut (.clk, .rst_n, .sif(sif.slv), .mem_req, .mem_resp);

  logic [AXI_ID_W-1:0] rid_q;
  logic                rpend_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rpend_q <= 1'b0; rid_q <= '0; end
    else begin
      if (mem_req.ar_valid && mem_resp.ar_ready) begin
        rpend_q <= 1'b1; rid_q <= mem_req.ar.id;
      end else if (mem_resp.r_valid && mem_req.r_ready) rpend_q <= 1'b0;
    end
  end
  always_comb begin
    mem_resp          = '0;
    mem_resp.ar_ready = !rpend_q;
    mem_resp.aw_ready = 1'b1;
    mem_resp.w_ready  = 1'b1;
    mem_resp.r_valid  = rpend_q;
    mem_resp.r.id     = rid_q;
    mem_resp.r.data   = 32'hC0FF_EE00;
    mem_resp.r.resp   = RESP_OKAY;
    mem_resp.r.last   = 1'b1;
  end

  localparam int TAG_W = axi4_pkg::M_ID_W - int'(AXI_ID_W);
  logic [axi4_pkg::M_ID_W-1:0] issued_id;
  int guard;

  task automatic do_read(input logic [axi4_pkg::M_ID_W-1:0] id, input logic [31:0] a);
    @(negedge clk);
    sif.arid = id; sif.araddr = a; sif.arlen = '0; sif.arsize = 3'd2;
    sif.arburst = 2'b01; sif.arvalid = 1'b1; sif.rready = 1'b1;
    guard = 0;
    while (!(sif.arvalid && sif.arready) && guard < 100) begin @(negedge clk); guard++; end
    @(negedge clk); sif.arvalid = 1'b0;
    guard = 0;
    while (!sif.rvalid && guard < 200) begin @(negedge clk); guard++; end
  endtask

  initial begin
    sif.arvalid = 0; sif.awvalid = 0; sif.wvalid = 0;
    sif.rready = 0; sif.bready = 1; sif.arid = '0; sif.araddr = '0;
    sif.arlen = '0; sif.arsize = '0; sif.arburst = 2'b01;
    sif.awid = '0; sif.awaddr = '0; sif.awlen = '0; sif.awsize = '0;
    sif.awburst = 2'b01; sif.wdata = '0; sif.wstrb = '0; sif.wlast = 0;
    repeat (3) @(negedge clk); rst_n = 1'b1; repeat (2) @(negedge clk);

    $display("=== tb_axi4_coreaxi_slv ===");
    ck("the slave-facing id really is wider than coreaxi's (else this gate is vacuous)",
       TAG_W > 0);

    do_read({TAG_W'(0), 4'h5}, 32'h0000_1000);
    ck("LIVENESS: a read reaches the memory side", mem_req.ar.addr === 32'h0000_1000);
    ck("LIVENESS: a response comes back", sif.rvalid === 1'b1);
    ck("the data is passed through", sif.rdata === 32'hC0FF_EE00);
    ck("the low id bits survive", sif.rid[AXI_ID_W-1:0] === 4'h5);
    @(negedge clk); sif.rready = 1'b0; @(negedge clk);

    ck("the memory side sees a TRUNCATED id (coreaxi is only AXI_ID_W wide)",
       $bits(mem_req.ar.id) == int'(AXI_ID_W));

    issued_id = {TAG_W'(1), 4'hA};        // master-tag bit SET
    do_read(issued_id, 32'h0000_2000);
    ck("LIVENESS: the tagged read got a response", sif.rvalid === 1'b1);
    ck("MASTER TAG REATTACHED -- response routes to the issuing master",
       sif.rid === issued_id);
    ck("  (and specifically the tag bit is not lost)",
       sif.rid[axi4_pkg::M_ID_W-1 -: TAG_W] === TAG_W'(1));
    @(negedge clk); sif.rready = 1'b0; @(negedge clk);

    $display("tb_axi4_coreaxi_slv: checked=%0d errors=%0d", checked, errors);
    if (errors != 0) $display("tb_axi4_coreaxi_slv: FAIL");
    else             $display("tb_axi4_coreaxi_slv: PASS");
    $finish;
  end

  initial begin
    #20000; $display("tb_axi4_coreaxi_slv: WATCHDOG TIMEOUT -- FAIL"); $finish;
  end
endmodule
