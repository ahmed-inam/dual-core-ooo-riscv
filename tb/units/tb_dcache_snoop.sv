// Gate for the dcache snoop response path.
module tb_dcache_snoop
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coherence_pkg::*;
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
  logic              coh_req_valid, coh_gnt, coh_done, coh_shared;
  coh_req_e          coh_req_type;
  word_t             coh_req_addr;
  int                n_upg;
  logic              snp_valid, snp_ack;
  word_t             snp_addr;
  coh_snoop_e        snp_type;
  coh_rsp_e          snp_rsp;

  dcache dut (
    .clk, .rst_n,
    .snp_valid, .snp_addr, .snp_type, .snp_ack, .snp_rsp,
    .coh_req_valid, .coh_req_type, .coh_req_addr,
    .coh_gnt, .coh_done, .coh_shared, .coh_installed(),
    .req, .gnt, .addr, .we, .wstrb, .wdata, .rvalid, .rdata,
    .kill(kill), .flush(flush), .flush_done(flush_done),
    .line_req, .line_gnt, .line_addr, .line_we, .line_wdata,
    .line_rvalid, .line_rdata,
    .mmio_req, .mmio_gnt, .mmio_addr, .mmio_we, .mmio_wstrb, .mmio_wdata,
    .mmio_rvalid, .mmio_rdata,
    .ev_miss, .ev_wb
  );

  int  mem_delay = 1;
  int  lcnt;
  logic lbusy;
  word_t last_wb_addr;
  int    n_wb;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lbusy <= 1'b0; lcnt <= 0; line_rvalid <= 1'b0; n_wb <= 0;
    end else begin
      line_rvalid <= 1'b0;
      if (line_req && line_gnt) begin
        lbusy <= 1'b1; lcnt <= mem_delay;
        if (line_we) begin n_wb <= n_wb + 1; last_wb_addr <= line_addr; end
      end else if (lbusy) begin
        if (lcnt > 0) lcnt <= lcnt - 1;
        else begin lbusy <= 1'b0; line_rvalid <= 1'b1; end
      end
    end
  end
  assign line_gnt  = line_req && !lbusy;
  assign line_rdata = {32'h4444_4444, 32'h3333_3333, 32'h2222_2222, 32'h1111_1111};
  assign mmio_gnt  = mmio_req;
  always_ff @(posedge clk) mmio_rvalid <= mmio_req && !mmio_we;
  assign mmio_rdata = 32'h0;

  logic coh_hold = 1'b0;
  assign coh_gnt   = coh_req_valid && !coh_hold;
  assign coh_shared = 1'b0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin coh_done <= 1'b0; n_upg <= 0; end
    else begin
      coh_done <= coh_req_valid && coh_gnt;
      if (coh_req_valid && coh_gnt) n_upg <= n_upg + 1;
    end
  end

  localparam word_t A = 32'h0000_1000;   // cacheable
  localparam word_t B = 32'h0000_2000;   // a different line/set

  int idx, way, guard;

  task automatic access(input word_t a, input logic w_, input word_t d);
    @(negedge clk); req=1'b1; addr=a; we=w_; wstrb=4'hF; wdata=d;
    guard=0; while (!gnt && guard<80) begin @(posedge clk); #1; guard++; end
    @(negedge clk); req=1'b0;
    guard=0; while (!rvalid && guard<120) begin @(posedge clk); #1; guard++; end
  endtask

  task automatic do_snoop(input word_t a, input coh_snoop_e t,
                          output coh_rsp_e r, output int cycles);
    @(negedge clk); snp_valid=1'b1; snp_addr=a; snp_type=t;
    cycles=0; #1;
    while (!snp_ack && cycles<200) begin @(posedge clk); #1; cycles++; end
    r = snp_rsp;
    @(negedge clk); snp_valid=1'b0;
    @(negedge clk);
  endtask

  coh_rsp_e r;
  int       cyc;

  initial begin
    req=0; we=0; addr='0; wstrb='0; wdata='0; kill=0; flush=0;
    snp_valid=0; snp_addr='0; snp_type=SNP_TO_S;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_dcache_snoop ===");

    do_snoop(B, SNP_TO_S, r, cyc);
    ck("snoop miss answers NtoN", r === RSP_NtoN);
    ck("snoop miss answers in ZERO wait cycles (combinational)", cyc == 0);

    access(A, 1'b0, '0);                       // installs E
    idx = (A >> OFF_W) & (SETS-1);
    way = (dut.tag_q[idx][0].tag == (A >> (OFF_W+IDX_W))) ? 0 : 1;
    ck("line installed E", dut.tag_q[idx][way].state === LINE_E);
    n_wb = 0;
    do_snoop(A, SNP_TO_S, r, cyc);
    ck("E + snoop-GetS answers TtoB", r === RSP_TtoB);
    ck("E snoop answers immediately (clean: no array, no bus)", cyc == 0);
    ck("E + snoop-GetS downgrades to S", dut.tag_q[idx][way].state === LINE_S);
    ck("clean downgrade wrote NOTHING back", n_wb == 0);

    n_wb = 0;
    do_snoop(A, SNP_TO_I, r, cyc);
    ck("S + snoop-GetM answers BtoN", r === RSP_BtoN);
    ck("S + snoop-GetM invalidates", dut.tag_q[idx][way].state === LINE_I);
    ck("invalidating a CLEAN line wrote nothing back", n_wb == 0);

    access(A, 1'b1, 32'hDEAD_BEEF);            // store -> M
    way = (dut.tag_q[idx][0].tag == (A >> (OFF_W+IDX_W))) ? 0 : 1;
    ck("store left the line M", dut.tag_q[idx][way].state === LINE_M);
    n_wb = 0;
    do_snoop(A, SNP_TO_S, r, cyc);
    ck("M + snoop-GetS answers TtoB", r === RSP_TtoB);
    ck("M snoop performed a WRITEBACK (B1: through memory)", n_wb == 1);
    ck("the writeback targeted the snooped line",
       last_wb_addr[31:OFF_W] === A[31:OFF_W]);
    ck("dirty snoop takes MORE than zero cycles (array + bus)", cyc > 0);
    ck("M + snoop-GetS ends in S", dut.tag_q[idx][way].state === LINE_S);

    access(A, 1'b1, 32'hCAFE_0000);            // back to M
    way = (dut.tag_q[idx][0].tag == (A >> (OFF_W+IDX_W))) ? 0 : 1;
    n_wb = 0;
    do_snoop(A, SNP_TO_I, r, cyc);
    ck("M + snoop-GetM answers TtoN", r === RSP_TtoN);
    ck("M + snoop-GetM wrote back", n_wb == 1);
    ck("M + snoop-GetM invalidates", dut.tag_q[idx][way].state === LINE_I);

    access(B, 1'b0, '0);                       // bring B in as E
    mem_delay = 40;                            // make the next miss long
    @(negedge clk); req=1'b1; addr=A; we=1'b0; wstrb=4'h0;   // miss on A
    guard=0; while (!gnt && guard<20) begin @(posedge clk); #1; guard++; end
    @(negedge clk); req=1'b0;
    repeat (4) @(negedge clk);
    ck("the cache really is mid-miss", dut.dstate_q !== 4'd0);
    do_snoop(B, SNP_TO_I, r, cyc);
    ck("a CLEAN snoop is answered WHILE a miss is outstanding", cyc == 0);
    ck("...with the right response", r === RSP_TtoN || r === RSP_BtoN);
    mem_delay = 1;
    guard=0; while (!rvalid && guard<200) begin @(posedge clk); #1; guard++; end

    access(A, 1'b0, '0);                        // bring A in as E
    way = (dut.tag_q[idx][0].tag == (A >> (OFF_W+IDX_W))) ? 0 : 1;
    dut.tag_q[idx][way].state = LINE_S;         // force shared
    @(negedge clk);
    n_upg = 0; n_wb = 0;
    access(A, 1'b1, 32'hFEED_BEEF);             // store to the shared line
    ck("store to a SHARED line issued an UPGRADE", n_upg == 1);
    ck("the Upgrade fetched NO data (no line traffic)", n_wb == 0);
    ck("after the Upgrade the line is writable",
       can_write(dut.tag_q[idx][way].state) === 1'b1);
    ck("the store then completed and dirtied it",
       dut.tag_q[idx][way].state === LINE_M);
    ck("the line stayed in the SAME way (no duplicate allocation)",
       dut.tag_q[idx][way].tag === (A >> (OFF_W+IDX_W)));

    dut.tag_q[idx][way].state = LINE_E;
    @(negedge clk); n_upg = 0;
    access(A, 1'b1, 32'h1111_2222);
    ck("store to an EXCLUSIVE line issues NO Upgrade (silent E->M)", n_upg == 0);
    ck("...and the line is M", dut.tag_q[idx][way].state === LINE_M);

    access(A, 1'b1, 32'hD1D1_0007);             // A dirty (M) in this cache
    way = (dut.tag_q[idx][0].tag == (A >> (OFF_W+IDX_W))) ? 0 : 1;
    ck("mid-miss setup: A is dirty", dut.tag_q[idx][way].state === LINE_M);

    coh_hold = 1'b1;                            // park the NEXT miss in D_ACQ_REQ
    @(negedge clk); req=1'b1; addr=B; we=1'b0; wstrb=4'h0;
    guard=0; while (!gnt && guard<40) begin @(negedge clk); guard++; end
    @(negedge clk); req=1'b0;
    guard=0; while ((dut.dstate_q !== dut.D_ACQ_REQ) && guard<60) begin
      @(negedge clk); guard++;
    end
    ck("mid-miss setup: the cache is parked in D_ACQ_REQ",
       dut.dstate_q === dut.D_ACQ_REQ);

    n_wb = 0;
    do_snoop(A, SNP_TO_I, r, cyc);
    ck("DIRTY snoop is ANSWERED while a miss is outstanding (blocker 6.7)",
       cyc < 190);
    ck("...and it wrote the dirty line back", n_wb == 1);
    ck("...with the correct response", r === RSP_TtoN);
    ck("...and invalidated the line", dut.tag_q[idx][way].state === LINE_I);
    coh_hold = 1'b0;
    guard=0; while (!rvalid && guard<300) begin @(negedge clk); guard++; end
    ck("LIVENESS: the parked miss still completes afterwards", rvalid === 1'b1);
    @(negedge clk);

    $display("=== tb_dcache_snoop: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_DCACHE_SNOOP PASS");
    else             $display("TB_DCACHE_SNOOP BROKEN");
    $finish;
  end

  initial begin
    #400000; $display("TB_DCACHE_SNOOP BROKEN (timeout)"); $finish;
  end

endmodule
