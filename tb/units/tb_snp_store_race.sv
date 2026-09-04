// Gate for the SNOOP / CORE-ACCESS COLLISION.
module tb_snp_store_race
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
  int                n_coh;
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

  int    mem_delay = 1;
  int    lcnt;
  logic  lbusy;
  word_t last_wb_addr;
  logic [LINE_W-1:0] last_wb_data;
  int    n_wb;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lbusy <= 1'b0; lcnt <= 0; line_rvalid <= 1'b0; n_wb <= 0;
    end else begin
      line_rvalid <= 1'b0;
      if (line_req && line_gnt) begin
        lbusy <= 1'b1; lcnt <= mem_delay;
        if (line_we) begin
          n_wb <= n_wb + 1; last_wb_addr <= line_addr; last_wb_data <= line_wdata;
        end
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

  assign coh_gnt    = coh_req_valid;
  assign coh_shared = 1'b0;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin coh_done <= 1'b0; n_coh <= 0; end
    else begin
      coh_done <= coh_req_valid && coh_gnt;
      if (coh_req_valid && coh_gnt) n_coh <= n_coh + 1;
    end
  end

  localparam word_t A = 32'h0000_1000;
  localparam word_t B = 32'h0000_2000;   // different tag, same set -> different way

  localparam word_t VA  = 32'hAAAA_0001;
  localparam word_t VB  = 32'hBBBB_0002;
  localparam word_t NEW = 32'h5150_0BAD;

  int idx, wayA, wayB, guard, before_rv;
  localparam int n_collisions = 3;   // tests 1, 2 and 3 each drive one

  int    n_rvalid;
  word_t cap_rdata;
  int    n_ack, n_snp_started;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin n_rvalid <= 0; cap_rdata <= '0; n_ack <= 0; end
    else begin
      if (rvalid)  begin n_rvalid <= n_rvalid + 1; cap_rdata <= rdata; end
      if (snp_ack) n_ack <= n_ack + 1;
    end
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

  task automatic collide(input word_t a_core, input logic w_, input word_t d,
                         input word_t a_snp,  input coh_snoop_e t,
                         output logic gnt_in_collision,
                         output logic completed);
    @(negedge clk);
    req=1'b1; addr=a_core; we=w_; wstrb=w_?4'hF:4'h0; wdata=d;
    snp_valid=1'b1; snp_addr=a_snp; snp_type=t;
    #1;                                  // settle combinationally, pre-posedge
    gnt_in_collision = gnt;
    before_rv = n_rvalid;
    n_snp_started = n_snp_started + 1;
    fork
      begin : core_side
        int g;
        g=0; while (!gnt && g<300) begin @(negedge clk); g++; end
        @(negedge clk); req=1'b0;
      end
      begin : snoop_side
        int g;
        g=0; while (!snp_ack && g<300) begin @(negedge clk); g++; end
        @(negedge clk); snp_valid=1'b0;
      end
    join
    guard=0; while ((n_rvalid == before_rv) && guard<300) begin @(negedge clk); guard++; end
    completed = (n_rvalid != before_rv);
    @(negedge clk); @(negedge clk);
  endtask

  logic done, gcol;
  word_t got;

  initial begin
    req=0; we=0; addr='0; wstrb='0; wdata='0; kill=0; flush=0;
    snp_valid=0; snp_addr='0; snp_type=SNP_TO_S; n_snp_started=0;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_snp_store_race ===");

    access(A, 1'b1, VA, done);
    ck("LIVENESS: an uncontended store completes", done === 1'b1);
    idx  = (A >> OFF_W) & (SETS-1);
    wayA = way_of(A);
    ck("LIVENESS: that store left the line M", dut.tag_q[idx][wayA].state === LINE_M);
    access(A, 1'b0, '0, done);
    ck("LIVENESS: an uncontended load completes", done === 1'b1);
    ck("LIVENESS: and reads back what was stored", cap_rdata === VA);

    n_wb = 0;
    collide(A, 1'b1, NEW, A, SNP_TO_S, gcol, done);
    ck("store+snoop collision: grant WITHHELD in the collision cycle",
       gcol === 1'b0);
    ck("store+snoop collision: the store still completes afterwards",
       done === 1'b1);
    ck("store+snoop collision: the dirty snoop DID write back", n_wb >= 1);
    ck("store+snoop collision: writeback carried the pre-store value",
       last_wb_data[0 +: 32] === VA);
    ck("store+snoop collision: the retry acquired permission (Upgrade)",
       n_coh >= 1);
    wayA = way_of(A);
    ck("store+snoop collision: line ends writable (M)",
       dut.tag_q[idx][wayA].state === LINE_M);
    access(A, 1'b0, '0, done);
    ck("store+snoop collision: LIVENESS -- the readback completed",
       done === 1'b1);
    ck("STORE SURVIVED THE COLLISION -- pre-fix this read back as the old value and the flag store was lost forever", cap_rdata === NEW);

    access(A, 1'b0, '0, done);                 // make sure A is present, clean-ish
    n_wb = 0;
    collide(A, 1'b1, VB, A, SNP_TO_I, gcol, done);
    ck("store+INVALIDATING snoop: grant WITHHELD in the collision cycle",
       gcol === 1'b0);
    ck("store+INVALIDATING snoop: the store still completes", done === 1'b1);
    access(A, 1'b0, '0, done);
    ck("store+INVALIDATING snoop: LIVENESS -- readback completed",
       done === 1'b1);
    ck("store+INVALIDATING snoop: the store survived", cap_rdata === VB);

    access(A, 1'b1, VA, done);                 // A dirty, holds VA
    access(B, 1'b1, VB, done);                 // B dirty, holds VB
    idx  = (A >> OFF_W) & (SETS-1);
    wayA = way_of(A);
    wayB = way_of(B);
    ck("load-vs-snoop setup: A and B occupy different ways", wayA != wayB);
    ck("load-vs-snoop setup: A is M", dut.tag_q[idx][wayA].state === LINE_M);
    ck("load-vs-snoop setup: B is M", dut.tag_q[idx][wayB].state === LINE_M);

    collide(A, 1'b0, '0, B, SNP_TO_S, gcol, done);
    got = cap_rdata;
    ck("load+snoop(other line): grant WITHHELD in the collision cycle",
       gcol === 1'b0);
    ck("load+snoop(other line): LIVENESS -- the load completed", done === 1'b1);
    ck("LOAD DID NOT RETURN THE SNOOP VICTIM'S LINE -- would read VB from B's way while asking for A", got !== VB);
    ck("load+snoop(other line): the load returned A's real data", got === VA);

    ck("all collision snoops were acknowledged (ordering point never stalled)",
       n_snp_started == n_collisions && n_ack >= n_collisions);
    $display("  (collisions driven=%0d, snoop-ack cycles=%0d)", n_snp_started, n_ack);

    $display("tb_snp_store_race: checked=%0d errors=%0d", checked, errors);
    if (errors != 0) $display("tb_snp_store_race: FAIL");
    else             $display("tb_snp_store_race: PASS");
    $finish;
  end

  initial begin
    #500000;
    $display("tb_snp_store_race: WATCHDOG TIMEOUT -- FAIL");
    $finish;
  end

endmodule
