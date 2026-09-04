// Gate for the CLINT-side AXI slave shim.
module tb_axi4_word_slv
  import rv32i_pkg::*;
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

  logic       req, gnt, we, rvalid;
  word_t      addr, wdata, rdata;
  logic [3:0] wstrb;

  axi4_word_slv dut (.clk, .rst_n, .sif(sif.slv),
                     .req, .gnt, .addr, .we, .wstrb, .wdata, .rvalid, .rdata);

  word_t seen_addr, seen_wdata;
  logic  seen_we;
  logic [3:0] seen_wstrb;
  int    n_dev;
  assign gnt = req;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rvalid <= 1'b0; n_dev <= 0; seen_addr <= '0;
                      seen_we <= 1'b0; seen_wdata <= '0; seen_wstrb <= '0; end
    else begin
      rvalid <= req && gnt && !rvalid;
      if (req && gnt && !rvalid) begin
        n_dev <= n_dev + 1; seen_addr <= addr; seen_we <= we;
        seen_wdata <= wdata; seen_wstrb <= wstrb;
      end
    end
  end
  assign rdata = 32'hBEEF_0001;

  int guard;
  logic [axi4_pkg::M_ID_W-1:0] rd_id;

  initial begin
    sif.arvalid=0; sif.awvalid=0; sif.wvalid=0; sif.rready=1; sif.bready=1;
    sif.arid='0; sif.araddr='0; sif.arlen='0; sif.arsize=3'd2; sif.arburst=2'b01;
    sif.awid='0; sif.awaddr='0; sif.awlen='0; sif.awsize=3'd2; sif.awburst=2'b01;
    sif.wdata='0; sif.wstrb='0; sif.wlast=1;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);
    $display("=== tb_axi4_word_slv ===");

    rd_id = {1'b1, 4'h7};
    @(negedge clk); sif.arid=rd_id; sif.araddr=32'h0200_BFF8; sif.arvalid=1'b1;
    guard=0; while (!(sif.arvalid && sif.arready) && guard<50) begin @(negedge clk); guard++; end
    @(negedge clk); sif.arvalid=1'b0;
    guard=0; while (!sif.rvalid && guard<100) begin @(negedge clk); guard++; end
    ck("LIVENESS: the read produced a response", sif.rvalid === 1'b1);
    ck("LIVENESS: the device actually saw the access", n_dev == 1);
    ck("the address reached the device", seen_addr === 32'h0200_BFF8);
    ck("the read data came back", sif.rdata === 32'hBEEF_0001);
    ck("MASTER TAG REPLAYED on the read response", sif.rid === rd_id);
    ck("a read must not raise bvalid", sif.bvalid === 1'b0);
    @(negedge clk);

    @(negedge clk); sif.awid={1'b0,4'h3}; sif.awaddr=32'h0200_0000; sif.awvalid=1'b1;
    sif.wdata=32'h1234_5678; sif.wstrb=4'hF; sif.wvalid=1'b1;
    guard=0; while (!(sif.awvalid && sif.awready) && guard<50) begin @(negedge clk); guard++; end
    @(negedge clk); sif.awvalid=1'b0;
    guard=0; while (!(sif.wvalid && sif.wready) && guard<50) begin @(negedge clk); guard++; end
    @(negedge clk); sif.wvalid=1'b0;
    guard=0; while (!sif.bvalid && guard<100) begin @(negedge clk); guard++; end
    ck("LIVENESS: the write produced a B response", sif.bvalid === 1'b1);
    ck("the write reached the device as a write", seen_we === 1'b1);
    ck("the write data reached the device", seen_wdata === 32'h1234_5678);
    ck("the write strobes reached the device", seen_wstrb === 4'hF);
    ck("MASTER TAG REPLAYED on the write response", sif.bid === {1'b0,4'h3});
    ck("a write must not raise rvalid", sif.rvalid === 1'b0);

    $display("tb_axi4_word_slv: checked=%0d errors=%0d", checked, errors);
    if (errors != 0) $display("tb_axi4_word_slv: FAIL");
    else             $display("tb_axi4_word_slv: PASS");
    $finish;
  end
  initial begin #20000; $display("tb_axi4_word_slv: WATCHDOG TIMEOUT -- FAIL"); $finish; end
endmodule
