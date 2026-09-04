// An Upgrade that loses its line to a peer GetM while waiting must refetch.
module tb_dcache_upg_race
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

  logic              req, gnt, we, rvalid, rerr, kill, flush, flush_done, is_lr;
  word_t             addr, wdata, rdata;
  logic [3:0]        wstrb;
  logic              line_req, line_gnt, line_we, line_rvalid;
  word_t             line_addr;
  logic [LINE_W-1:0] line_wdata, line_rdata;
  logic              mmio_req, mmio_gnt, mmio_we, mmio_rvalid;
  word_t             mmio_addr, mmio_wdata, mmio_rdata;
  logic [3:0]        mmio_wstrb;
  logic              ev_miss, ev_wb;
  logic              coh_req_valid, coh_req_atomic, coh_gnt, coh_done, coh_shared, coh_installed;
  coh_req_e          coh_req_type;
  word_t             coh_req_addr;
  logic              snp_valid, snp_ack, rsv_clear_o;
  word_t             snp_addr;
  coh_snoop_e        snp_type;
  coh_rsp_e          snp_rsp;

  dcache dut (
    .clk, .rst_n,
    .snp_valid, .snp_addr, .snp_type, .snp_ack, .snp_rsp, .rsv_clear_o,
    .coh_req_valid, .coh_req_atomic, .coh_req_type, .coh_req_addr,
    .coh_gnt, .coh_done, .coh_shared, .coh_installed,
    .req, .gnt, .addr, .we, .is_lr, .wstrb, .wdata, .rvalid, .rdata, .rerr,
    .kill(kill), .flush(flush), .flush_done(flush_done),
    .line_req, .line_gnt, .line_addr, .line_we, .line_wdata,
    .line_rvalid, .line_rdata,
    .mmio_req, .mmio_gnt, .mmio_addr, .mmio_we, .mmio_wstrb, .mmio_wdata,
    .mmio_rvalid, .mmio_rdata,
    .ev_miss, .ev_wb
  );

  // Line memory: one outstanding, fixed delay, the fill data is a TB variable
  // so a refetch can be told apart from the copy the cache already held.
  logic [LINE_W-1:0] fill_pattern;
  int    lcnt;
  logic  lbusy;
  int    n_fill, n_wb;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lbusy <= 1'b0; lcnt <= 0; line_rvalid <= 1'b0; n_fill <= 0; n_wb <= 0;
    end else begin
      line_rvalid <= 1'b0;
      if (line_req && line_gnt) begin
        lbusy <= 1'b1; lcnt <= 2;
        if (line_we) n_wb <= n_wb + 1; else n_fill <= n_fill + 1;
      end else if (lbusy) begin
        if (lcnt > 0) lcnt <= lcnt - 1;
        else begin lbusy <= 1'b0; line_rvalid <= 1'b1; end
      end
    end
  end
  assign line_gnt   = line_req && !lbusy;
  assign line_rdata = fill_pattern;
  assign mmio_gnt   = mmio_req;
  always_ff @(posedge clk) mmio_rvalid <= mmio_req && !mmio_we;
  assign mmio_rdata = 32'h0;

  // The ordering point is driven by hand: coh_gnt and coh_done are TB signals.
  logic shared_bit;
  assign coh_shared = shared_bit;

  localparam word_t A = 32'h8000_1000;
  localparam word_t P1_W0 = 32'h1111_0000, P1_W1 = 32'h1111_0001;
  localparam word_t P2_W0 = 32'h2222_0000, P2_W1 = 32'h2222_0001;
  localparam word_t NEW   = 32'h5150_0BAD;

  int idx, way, guard, before_rv, n_rvalid;
  word_t cap_rdata;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin n_rvalid <= 0; cap_rdata <= '0; end
    else if (rvalid) begin n_rvalid <= n_rvalid + 1; cap_rdata <= rdata; end
  end

  function automatic int way_of(input word_t a);
    int i;
    i = (a >> OFF_W) & (SETS-1);
    return (dut.tag_q[i][0].tag == (a >> (OFF_W+IDX_W))) ? 0 : 1;
  endfunction

  // Present a core access and complete any coherence request it raises, with
  // an optional peer invalidation landing while the request is still waiting.
  task automatic access(input word_t a, input logic w_, input word_t d,
                        input logic invalidate_while_waiting,
                        output logic completed, output int n_coh_seen);
    @(negedge clk); before_rv = n_rvalid; n_coh_seen = 0;
    req=1'b1; addr=a; we=w_; wstrb=w_?4'hF:4'h0; wdata=d;
    guard = 0;
    while ((n_rvalid == before_rv) && guard < 400) begin
      @(negedge clk); guard++;
      // hold the request through the edge that registers the grant, as the LSQ does
      if (gnt) begin @(negedge clk); guard++; req = 1'b0; end
      if (coh_req_valid && !coh_gnt) begin
        if (invalidate_while_waiting && (n_coh_seen == 0)) begin
          // the peer's GetM was ordered first: snoop us before granting
          snp_valid = 1'b1; snp_addr = a; snp_type = SNP_TO_I;
          @(negedge clk); guard++;
          while (!snp_ack && guard < 400) begin @(negedge clk); guard++; end
          @(negedge clk); guard++; snp_valid = 1'b0;
          @(negedge clk); guard++;
        end
        coh_gnt = 1'b1; n_coh_seen++;
        @(negedge clk); guard++; coh_gnt = 1'b0;
        @(negedge clk); guard++; coh_done = 1'b1;
        @(negedge clk); guard++; coh_done = 1'b0;
      end
    end
    completed = (n_rvalid != before_rv);
    req = 1'b0;
    @(negedge clk);
  endtask

  logic done;
  int   ncoh;

  initial begin
    req=0; we=0; addr='0; wstrb='0; wdata='0; kill=0; flush=0; is_lr=0;
    snp_valid=0; snp_addr='0; snp_type=SNP_TO_S;
    coh_gnt=0; coh_done=0; shared_bit=1'b1;
    fill_pattern = {32'h1111_0003, 32'h1111_0002, P1_W1, P1_W0};
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_dcache_upg_race ===");

    // Control: an uncontested Upgrade needs no fill.
    access(A, 1'b0, '0, 1'b0, done, ncoh);
    ck("control: load fills the line", done && (n_fill == 1));
    idx = (A >> OFF_W) & (SETS-1); way = way_of(A);
    ck("control: line installed S (peer shared it)", dut.tag_q[idx][way].state === LINE_S);
    access(A, 1'b1, NEW, 1'b0, done, ncoh);
    ck("control: store completes through an Upgrade", done && (ncoh == 1));
    ck("control: no refetch on an uncontested Upgrade", n_fill == 1);
    ck("control: line is M", dut.tag_q[idx][way].state === LINE_M);

    // Back to S: a peer GetS downgrades us and takes the dirty data.
    snp_valid=1'b1; snp_addr=A; snp_type=SNP_TO_S;
    guard=0; while (!snp_ack && guard<100) begin @(negedge clk); guard++; end
    @(negedge clk); snp_valid=1'b0;
    guard=0; while (dut.snstate_q != dut.SN_IDLE && guard<100) begin @(negedge clk); guard++; end
    repeat (4) @(negedge clk);
    ck("setup: line back to S after a peer GetS", dut.tag_q[idx][way].state === LINE_S);

    // The race: our store's Upgrade waits, the peer's GetM invalidates us first.
    fill_pattern = {32'h2222_0003, 32'h2222_0002, P2_W1, P2_W0};
    shared_bit = 1'b0;
    access(A + 4, 1'b1, NEW, 1'b1, done, ncoh);
    ck("race: the store completed", done);
    ck("race: an invalidated Upgrade refetched the line", n_fill == 2);
    way = way_of(A);
    ck("race: line ends M", dut.tag_q[idx][way].state === LINE_M);
    access(A, 1'b0, '0, 1'b0, done, ncoh);
    ck("race: word 0 is the PEER's data, not the stale copy", cap_rdata === P2_W0);
    access(A + 4, 1'b0, '0, 1'b0, done, ncoh);
    ck("race: word 1 is our store, merged into the refetched line", cap_rdata === NEW);
    ck("race: no extra fills for the readbacks", n_fill == 2);

    $display("tb_dcache_upg_race: checked=%0d errors=%0d", checked, errors);
    if (errors != 0) $display("tb_dcache_upg_race: FAIL");
    else             $display("tb_dcache_upg_race: PASS");
    $finish;
  end

  initial begin
    #500000;
    $display("tb_dcache_upg_race: WATCHDOG TIMEOUT -- FAIL");
    $finish;
  end

endmodule
