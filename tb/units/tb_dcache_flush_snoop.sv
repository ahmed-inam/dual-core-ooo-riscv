// A flush writeback must carry its own line even when a dirty snoop lands on the same cycle.
module tb_dcache_flush_snoop
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

  // Line memory: records every writeback by address.
  int    lcnt;
  logic  lbusy;
  int    n_wb;
  word_t wb_word0 [word_t];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lbusy <= 1'b0; lcnt <= 0; line_rvalid <= 1'b0; n_wb <= 0;
    end else begin
      line_rvalid <= 1'b0;
      if (line_req && line_gnt) begin
        lbusy <= 1'b1; lcnt <= 1;
        if (line_we) begin n_wb <= n_wb + 1; wb_word0[line_addr] = line_wdata[31:0]; end
      end else if (lbusy) begin
        if (lcnt > 0) lcnt <= lcnt - 1;
        else begin lbusy <= 1'b0; line_rvalid <= 1'b1; end
      end
    end
  end
  assign line_gnt   = line_req && !lbusy;
  assign line_rdata = {32'h4444_4444, 32'h3333_3333, 32'h2222_2222, 32'h1111_1111};
  assign mmio_gnt   = mmio_req;
  always_ff @(posedge clk) mmio_rvalid <= mmio_req && !mmio_we;
  assign mmio_rdata = 32'h0;

  // Uncontested ordering point: grant at once, complete a cycle later.
  assign coh_gnt    = coh_req_valid;
  assign coh_shared = 1'b0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) coh_done <= 1'b0;
    else        coh_done <= coh_req_valid && coh_gnt;
  end

  localparam word_t A  = 32'h8000_1000;   // set 0
  localparam word_t B  = 32'h8000_1010;   // set 1: a different set, so the scan reaches A first
  localparam word_t VA = 32'hAAAA_0001;
  localparam word_t VB = 32'hBBBB_0002;

  int idxA, wayA, idxB, wayB, guard, before_rv, n_rvalid;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) n_rvalid <= 0;
    else if (rvalid) n_rvalid <= n_rvalid + 1;
  end

  function automatic int way_of(input word_t a);
    int i;
    i = (a >> OFF_W) & (SETS-1);
    return (dut.tag_q[i][0].tag == (a >> (OFF_W+IDX_W))) ? 0 : 1;
  endfunction

  task automatic access(input word_t a, input logic w_, input word_t d,
                        output logic completed);
    @(negedge clk); before_rv = n_rvalid;
    req=1'b1; addr=a; we=w_; wstrb=w_?4'hF:4'h0; wdata=d;
    guard=0; while (!gnt && guard<200) begin @(negedge clk); guard++; end
    @(negedge clk); req=1'b0;
    guard=0; while ((n_rvalid == before_rv) && guard<300) begin @(negedge clk); guard++; end
    completed = (n_rvalid != before_rv);
    @(negedge clk);
  endtask

  logic done;

  initial begin
    req=0; we=0; addr='0; wstrb='0; wdata='0; kill=0; flush=0; is_lr=0;
    snp_valid=0; snp_addr='0; snp_type=SNP_TO_S;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_dcache_flush_snoop ===");

    access(A, 1'b1, VA, done);
    access(B, 1'b1, VB, done);
    idxA = (A >> OFF_W) & (SETS-1); wayA = way_of(A);
    idxB = (B >> OFF_W) & (SETS-1); wayB = way_of(B);
    ck("setup: A is M", dut.tag_q[idxA][wayA].state === LINE_M);
    ck("setup: B is M", dut.tag_q[idxB][wayB].state === LINE_M);
    ck("setup: A and B are in different sets", idxA != idxB);

    // Start a flush, and land a dirty snoop on B in the exact cycle the scan
    // reads A out of the data array for its writeback.
    @(negedge clk); flush = 1'b1;
    guard = 0;
    while (!((dut.dstate_q == dut.D_FLUSH_SCAN)
             && (int'(dut.fl_set_q[IDX_W-1:0]) == idxA)
             && (int'(dut.fl_way_q) == wayA)) && guard < 400) begin
      @(negedge clk); guard++;
    end
    ck("scan reached A's way", guard < 400);
    snp_valid = 1'b1; snp_addr = B; snp_type = SNP_TO_S;
    guard = 0; while (!snp_ack && guard < 200) begin @(negedge clk); guard++; end
    @(negedge clk); snp_valid = 1'b0;
    guard = 0; while (!flush_done && guard < 600) begin @(negedge clk); guard++; end
    @(negedge clk); flush = 1'b0;
    ck("flush finished", guard < 600);
    ck("both lines were written back (a snooped line may go twice)", n_wb >= 2);
    ck("A's writeback carried A's data, not the snooped line's",
       wb_word0.exists(A) && (wb_word0[A] === VA));
    ck("B's writeback carried B's data", wb_word0.exists(B) && (wb_word0[B] === VB));

    $display("tb_dcache_flush_snoop: checked=%0d errors=%0d", checked, errors);
    if (errors != 0) $display("tb_dcache_flush_snoop: FAIL");
    else             $display("tb_dcache_flush_snoop: PASS");
    $finish;
  end

  initial begin
    #500000;
    $display("tb_dcache_flush_snoop: WATCHDOG TIMEOUT -- FAIL");
    $finish;
  end

endmodule
