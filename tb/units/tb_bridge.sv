// Gate for coreaxi_axi4_bridge.
module tb_bridge
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;
  import axi4_pkg::*;
  import axi4_tb_pkg::*;
();

  logic aclk = 1'b0, arst_n = 1'b0;
  always #5 aclk = ~aclk;

  int errors = 0, checked = 0;

  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  axi4_if #(.ID_W(ID_WIDTH)) m0 (.aclk(aclk), .arst_n(arst_n));
  axi4_if #(.ID_W(ID_WIDTH)) m1 (.aclk(aclk), .arst_n(arst_n));
  axi4_if #(.ID_W(M_ID_W))   s0 (.aclk(aclk), .arst_n(arst_n));
  axi4_if #(.ID_W(M_ID_W))   s1 (.aclk(aclk), .arst_n(arst_n));

  logic       req, gnt, we, word_mode, rvalid;
  word_t      addr;
  logic [3:0] wstrb;
  logic [LINE_W-1:0] wdata, rdata;

  axi_req_t  core_req;
  axi_resp_t core_resp;

  axi_adapter u_adp (
    .clk(aclk), .rst_n(arst_n),
    .req, .gnt, .addr, .we, .word_mode, .wstrb, .wdata, .rvalid, .rdata,
    .axi_req(core_req), .axi_resp(core_resp)
  );

  coreaxi_axi4_bridge u_bridge (
    .core_req, .core_resp, .xbar(m0)
  );

  axi4_xbar_top dut (.aclk(aclk), .arst_n(arst_n), .m0(m0), .m1(m1),
                     .s0(s0), .s1(s1));

  assign m1.awvalid = 1'b0; assign m1.wvalid = 1'b0; assign m1.arvalid = 1'b0;
  assign m1.bready  = 1'b1; assign m1.rready = 1'b1;
  assign m1.awid='0; assign m1.awaddr='0; assign m1.awlen='0; assign m1.awsize='0;
  assign m1.awburst='0; assign m1.wdata='0; assign m1.wstrb='0; assign m1.wlast='0;
  assign m1.arid='0; assign m1.araddr='0; assign m1.arlen='0; assign m1.arsize='0;
  assign m1.arburst='0;

  xbar_probe_if pb (.aclk(aclk), .arst_n(arst_n));
  axi4_test_smoke unused_t;
  initial unused_t = new(m0, m1, s0, s1, pb);

  axi4_slv_agent sa0, sa1;

  axi4_assert #(.ID_W(ID_WIDTH)) chk_m0 (
    .aclk(aclk), .arst_n(arst_n), .ext_rst_n(arst_n),
    .awid(m0.awid), .awaddr(m0.awaddr), .awlen(m0.awlen), .awsize(m0.awsize),
    .awburst(m0.awburst), .awvalid(m0.awvalid), .awready(m0.awready),
    .wdata(m0.wdata), .wstrb(m0.wstrb), .wlast(m0.wlast),
    .wvalid(m0.wvalid), .wready(m0.wready),
    .bid(m0.bid), .bresp(m0.bresp), .bvalid(m0.bvalid), .bready(m0.bready),
    .arid(m0.arid), .araddr(m0.araddr), .arlen(m0.arlen), .arsize(m0.arsize),
    .arburst(m0.arburst), .arvalid(m0.arvalid), .arready(m0.arready),
    .rid(m0.rid), .rdata(m0.rdata), .rresp(m0.rresp), .rlast(m0.rlast),
    .rvalid(m0.rvalid), .rready(m0.rready)
  );

  task automatic acc(input word_t a, input logic w_, input logic wordm,
                     input logic [3:0] st, input logic [LINE_W-1:0] wd);
    @(negedge aclk);
    req = 1'b1; addr = a; we = w_; word_mode = wordm; wstrb = st; wdata = wd;
    while (1) begin @(posedge aclk); #1; if (gnt) break; end
    @(negedge aclk); req = 1'b0;
    if (!w_) begin
      automatic int guard = 0;
      while (!rvalid && guard < 2000) begin @(posedge aclk); #1; guard++; end
    end else begin
      automatic int guard = 0;
      while (!rvalid && guard < 2000) begin @(posedge aclk); #1; guard++; end
    end
  endtask

  localparam word_t MEM = S1_BASE;

  logic [LINE_W-1:0] got;

  initial begin
    req=0; we=0; word_mode=0; wstrb='0; wdata='0; addr='0;
    slverr_window = 0;
    sa0 = new(s0, 0); sa1 = new(s1, 1);
    sa0.build(); sa1.build();
    fork sa0.run(); sa1.run(); join_none

    repeat (5) @(negedge aclk); arst_n = 1'b1; repeat (3) @(negedge aclk);

    $display("=== tb_bridge (CPU structs -> bridge -> crossbar -> slave) ===");
    ck("memory addresses decode to S1 after the 1.5 remap",
       MEM[DEC_MSB:DEC_LSB] === S1_PREFIX);

    acc(MEM + 32'h40, 1'b1, 1'b1, 4'hF, {{(LINE_W-32){1'b0}}, 32'hCAFE_F00D});
    acc(MEM + 32'h40, 1'b0, 1'b1, 4'h0, '0);
    got = rdata;
    ck("word write/read round-trips through the bridge",
       got[31:0] === 32'hCAFE_F00D);

    acc(MEM + 32'h80, 1'b1, 1'b0, 4'hF,
        {32'h4444_4444, 32'h3333_3333, 32'h2222_2222, 32'h1111_1111});
    acc(MEM + 32'h80, 1'b0, 1'b0, 4'h0, '0);
    got = rdata;
    ck("line burst beat0", got[31:0]    === 32'h1111_1111);
    ck("line burst beat1", got[63:32]   === 32'h2222_2222);
    ck("line burst beat2", got[95:64]   === 32'h3333_3333);
    ck("line burst beat3", got[127:96]  === 32'h4444_4444);

    acc(MEM + 32'h100, 1'b1, 1'b0, 4'hF,
        {32'hDDDD_DDDD, 32'hCCCC_CCCC, 32'hBBBB_BBBB, 32'hAAAA_AAAA});
    acc(MEM + 32'h80,  1'b0, 1'b0, 4'h0, '0);
    got = rdata;
    ck("earlier line still intact after a second write",
       got[31:0] === 32'h1111_1111 && got[127:96] === 32'h4444_4444);
    acc(MEM + 32'h100, 1'b0, 1'b0, 4'h0, '0);
    got = rdata;
    ck("second line reads back correctly",
       got[31:0] === 32'hAAAA_AAAA && got[127:96] === 32'hDDDD_DDDD);

    $display("=== tb_bridge: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_BRIDGE PASS");
    else             $display("TB_BRIDGE BROKEN");
    $finish;
  end

  initial begin
    #500000; $display("TB_BRIDGE BROKEN (timeout)"); $finish;
  end

endmodule
