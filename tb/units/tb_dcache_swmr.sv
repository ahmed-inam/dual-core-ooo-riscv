// Gate for the store-hit permission rule.
module tb_dcache_swmr
  import rv32i_pkg::*;
  import mem_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0;
  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  logic              req, gnt, we, rvalid, kill, flush, flush_done;
  word_t             addr, wdata, rdata;
  logic [3:0]        wstrb;
  logic              line_req, line_gnt, line_we, line_rvalid;
  word_t             line_addr;
  logic [LINE_W-1:0] line_wdata, line_rdata;
  logic              mmio_req, mmio_gnt, mmio_we, mmio_rvalid;
  word_t             mmio_addr, mmio_wdata, mmio_rdata;
  logic [3:0]        mmio_wstrb;
  logic              ev_miss, ev_wb;

  dcache dut (
    .clk, .rst_n,
    .snp_valid(1'b0), .snp_addr('0), .snp_type(SNP_TO_S),
    .snp_ack(), .snp_rsp(),
    .coh_req_valid(), .coh_req_type(), .coh_req_addr(),
    .coh_gnt(1'b1), .coh_done(1'b1), .coh_shared(1'b0),
    .coh_installed(),
    .req, .gnt, .addr, .we, .wstrb, .wdata, .rvalid, .rdata,
    .kill(kill), .flush(flush), .flush_done(flush_done),
    .line_req, .line_gnt, .line_addr, .line_we, .line_wdata,
    .line_rvalid, .line_rdata,
    .mmio_req, .mmio_gnt, .mmio_addr, .mmio_we, .mmio_wstrb, .mmio_wdata,
    .mmio_rvalid, .mmio_rdata,
    .ev_miss, .ev_wb
  );

  logic lpend;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin lpend <= 1'b0; line_rvalid <= 1'b0; line_rdata <= '0; end
    else begin
      line_rvalid <= 1'b0;
      if (line_req && line_gnt) lpend <= 1'b1;
      else if (lpend) begin
        lpend <= 1'b0; line_rvalid <= 1'b1;
        line_rdata <= {32'h4444_4444, 32'h3333_3333, 32'h2222_2222, 32'h1111_1111};
      end
    end
  end
  assign line_gnt = line_req;
  assign mmio_gnt = mmio_req;
  always_ff @(posedge clk) mmio_rvalid <= mmio_req && !mmio_we;
  assign mmio_rdata = 32'hDEAD_0000;

  localparam word_t A = 32'h0000_1000;    // cacheable (bit 31 low)

  int    guard;
  int    idx, way;
  int    misses_before, misses_after;

  task automatic access(input word_t a, input logic w_, input word_t d);
    @(negedge clk);
    req=1'b1; addr=a; we=w_; wstrb=4'hF; wdata=d;
    guard=0; while (!gnt && guard<50) begin @(posedge clk); #1; guard++; end
    @(negedge clk); req=1'b0;
    guard=0; while (!rvalid && guard<80) begin @(posedge clk); #1; guard++; end
  endtask

  initial begin
    req=0; we=0; addr='0; wstrb='0; wdata='0; kill=0; flush=0;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_dcache_swmr ===");

    access(A, 1'b0, '0);
    idx = (A >> OFF_W) & (SETS-1);
    way = dut.tag_q[idx][0].tag == (A >> (OFF_W+IDX_W)) ? 0 : 1;
    ck("a normal load installs an EXCLUSIVE line",
       dut.tag_q[idx][way].state === LINE_E);

    dut.tag_q[idx][way].state = LINE_S;
    @(negedge clk);
    ck("line is now SHARED", dut.tag_q[idx][way].state === LINE_S);

    misses_before = 0;
    @(negedge clk); req=1'b1; addr=A; we=1'b0; wstrb=4'h0; #1;
    ck("a LOAD still HITS on a shared line", dut.s0_hit === 1'b1);
    @(negedge clk); req=1'b0;

    @(negedge clk); req=1'b1; addr=A; we=1'b1; wstrb=4'hF; wdata=32'hBEEF; #1;
    ck("a STORE does NOT hit on a shared line (no silent seizure)",
       dut.s0_hit === 1'b0);
    @(negedge clk); req=1'b0;

    ck("the shared line was NOT bumped to M by the attempt",
       dut.tag_q[idx][way].state === LINE_S);

    access(A, 1'b1, 32'hBEEF);
    ck("after the store completes the line has WRITE PERMISSION",
       can_write(dut.tag_q[idx][way].state) === 1'b1);
    ck("...specifically M (a store dirties it)",
       dut.tag_q[idx][way].state === LINE_M);

    ck("the set does NOT hold two copies of the same tag",
       !(dut.tag_q[idx][0].tag == dut.tag_q[idx][1].tag
         && is_valid(dut.tag_q[idx][0].state)
         && is_valid(dut.tag_q[idx][1].state)));

    @(negedge clk); req=1'b1; addr=A; we=1'b1; wstrb=4'hF; wdata=32'hF00D; #1;
    ck("a STORE still hits on M (unchanged)", dut.s0_hit === 1'b1);
    @(negedge clk); req=1'b0;

    dut.tag_q[idx][way].state = LINE_E;
    @(negedge clk); req=1'b1; addr=A; we=1'b1; wstrb=4'hF; wdata=32'h1234; #1;
    ck("a STORE still hits on E (S6-C3 silent E->M)", dut.s0_hit === 1'b1);
    @(negedge clk); req=1'b0;

    ck("can_write(E) = 1", can_write(LINE_E) === 1'b1);
    ck("can_write(M) = 1", can_write(LINE_M) === 1'b1);
    ck("can_write(S) = 0 -- the whole point", can_write(LINE_S) === 1'b0);
    ck("can_write(I) = 0", can_write(LINE_I) === 1'b0);

    $display("=== tb_dcache_swmr: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_DCACHE_SWMR PASS");
    else             $display("TB_DCACHE_SWMR BROKEN");
    $finish;
  end

  initial begin
    #200000; $display("TB_DCACHE_SWMR BROKEN (timeout)"); $finish;
  end

endmodule
