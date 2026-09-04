// Gate for ACQUIRE-BEFORE-FILL, install_state,.
module tb_dcache_acquire
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
  logic              coh_req_valid, coh_gnt, coh_done, coh_shared, coh_installed;
  coh_req_e          coh_req_type;
  word_t             coh_req_addr;
  logic              snp_valid, snp_ack;
  word_t             snp_addr;
  coh_snoop_e        snp_type;
  coh_rsp_e          snp_rsp;

  dcache dut (
    .clk, .rst_n,
    .snp_valid, .snp_addr, .snp_type, .snp_ack, .snp_rsp,
    .coh_req_valid, .coh_req_type, .coh_req_addr,
    .coh_gnt, .coh_done, .coh_shared, .coh_installed,
    .req, .gnt, .addr, .we, .wstrb, .wdata, .rvalid, .rdata,
    .kill(kill), .flush(flush), .flush_done(flush_done),
    .line_req, .line_gnt, .line_addr, .line_we, .line_wdata,
    .line_rvalid, .line_rdata,
    .mmio_req, .mmio_gnt, .mmio_addr, .mmio_we, .mmio_wstrb, .mmio_wdata,
    .mmio_rvalid, .mmio_rdata,
    .ev_miss, .ev_wb
  );

  int   mem_delay = 1;
  int   lcnt;
  logic lbusy;
  int   n_line_req;              // counts memory transactions
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lbusy <= 1'b0; lcnt <= 0; line_rvalid <= 1'b0; n_line_req <= 0;
    end else begin
      line_rvalid <= 1'b0;
      if (line_req && line_gnt) begin
        lbusy <= 1'b1; lcnt <= mem_delay; n_line_req <= n_line_req + 1;
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

  int   ord_delay = 4;
  logic shared_ans = 1'b0;
  logic ord_busy;
  int   ord_cnt, n_grants;
  coh_req_e last_req_type;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ord_busy <= 1'b0; ord_cnt <= 0; coh_done <= 1'b0; n_grants <= 0;
      last_req_type <= REQ_GETS;
    end else begin
      coh_done <= 1'b0;
      if (coh_req_valid && coh_gnt) begin
        ord_busy <= 1'b1; ord_cnt <= ord_delay;
        n_grants <= n_grants + 1; last_req_type <= coh_req_type;
      end else if (ord_busy) begin
        if (ord_cnt > 0) ord_cnt <= ord_cnt - 1;
        else begin ord_busy <= 1'b0; coh_done <= 1'b1; end
      end
    end
  end
  assign coh_gnt    = coh_req_valid && !ord_busy;
  assign coh_shared = shared_ans;

  logic acq_open;
  logic mem_before_perm;
  logic install_on_done;         // THE Upgrade-handshake bug, directly
  int   n_installed;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acq_open <= 1'b0; mem_before_perm <= 1'b0;
      install_on_done <= 1'b0; n_installed <= 0;
    end else begin
      if (coh_req_valid && coh_gnt) acq_open <= 1'b1;
      else if (coh_done)            acq_open <= 1'b0;
      if (acq_open && line_req && line_gnt) mem_before_perm <= 1'b1;
      if (coh_done && coh_installed)        install_on_done <= 1'b1;
      if (coh_installed)                    n_installed <= n_installed + 1;
    end
  end

  localparam word_t A = 32'h0000_1000;   // set 0
  localparam word_t B = 32'h0000_1010;   // set 1
  localparam word_t C = 32'h0000_1020;   // set 2

  int idx, way, guard, before_rv, n_rvalid;
  word_t cap_rdata;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin n_rvalid <= 0; cap_rdata <= '0; end
    else if (rvalid) begin n_rvalid <= n_rvalid + 1; cap_rdata <= rdata; end
  end

  function automatic int idx_of(input word_t a);
    return (a >> OFF_W) & (SETS-1);
  endfunction
  function automatic int way_of(input word_t a);
    int i; i = idx_of(a);
    return (dut.tag_q[i][0].tag == (a >> (OFF_W+IDX_W))) ? 0 : 1;
  endfunction

  task automatic access(input word_t a, input logic w_, input word_t d,
                        output logic completed);
    @(negedge clk); before_rv = n_rvalid;
    req=1'b1; addr=a; we=w_; wstrb=w_?4'hF:4'h0; wdata=d;
    guard=0; while (!gnt && guard<300) begin @(negedge clk); guard++; end
    @(negedge clk); req=1'b0;
    guard=0; while ((n_rvalid==before_rv) && guard<400) begin @(negedge clk); guard++; end
    completed = (n_rvalid != before_rv);
    @(negedge clk);
  endtask

  logic done;

  initial begin
    req=0; we=0; addr='0; wstrb='0; wdata='0; kill=0; flush=0;
    snp_valid=0; snp_addr='0; snp_type=SNP_TO_S;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_dcache_acquire ===");

    shared_ans = 1'b0;
    access(A, 1'b0, '0, done);
    ck("LIVENESS: a load miss completes through the acquire path", done === 1'b1);
    ck("LIVENESS: the acquire actually happened (a grant was issued)", n_grants == 1);
    ck("LIVENESS: the fill actually reached memory", n_line_req >= 1);

    ck("load miss requested GetS", last_req_type === REQ_GETS);
    access(B, 1'b1, 32'hFEED_0001, done);
    ck("store miss completes", done === 1'b1);
    ck("store miss requested GetM (we intend to write it)",
       last_req_type === REQ_GETM);

    ck("NO memory traffic was issued before permission was granted",
       mem_before_perm === 1'b0);

    ck("GetS + shared=0 installs EXCLUSIVE",
       dut.tag_q[idx_of(A)][way_of(A)].state === LINE_E);
    ck("GetM installs MODIFIED",
       dut.tag_q[idx_of(B)][way_of(B)].state === LINE_M);

    shared_ans = 1'b1;                       // another hart holds a copy
    access(C, 1'b0, '0, done);
    ck("LIVENESS: the shared load miss completed", done === 1'b1);
    ck("GetS + shared=1 installs SHARED (NOT exclusive -- SWMR)",
       dut.tag_q[idx_of(C)][way_of(C)].state === LINE_S);

    shared_ans = 1'b0;
    n_line_req = 0;
    access(C, 1'b1, 32'hCAFE_0002, done);
    ck("LIVENESS: the store to the SHARED line completed", done === 1'b1);
    ck("store on a SHARED line requested UPGRADE (not a refill)",
       last_req_type === REQ_UPGRADE);
    ck("the Upgrade touched memory ZERO times (permission only)",
       n_line_req == 0);
    ck("after Upgrade the line is MODIFIED",
       dut.tag_q[idx_of(C)][way_of(C)].state === LINE_M);
    ck("coh_installed was reported at least once per transaction",
       n_installed >= n_grants);
    ck("install report lands AFTER the completion, never in the same cycle -- same-cycle means O_HOLD misses the pulse and the cluster deadlocks",
       install_on_done === 1'b0);

    $display("tb_dcache_acquire: checked=%0d errors=%0d", checked, errors);
    if (errors != 0) $display("tb_dcache_acquire: FAIL");
    else             $display("tb_dcache_acquire: PASS");
    $finish;
  end

  initial begin
    #500000;
    $display("tb_dcache_acquire: WATCHDOG TIMEOUT -- FAIL");
    $finish;
  end

endmodule
