// Gate for the cross-hart master0 aggregator.
module tb_merge_dcoh
  import rv32i_pkg::*;
  import mem_pkg::*;
  import platform_cfg_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0;
  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  logic  [NUM_HARTS-1:0] h_req, h_gnt, h_we, h_word, h_rvalid;
  word_t                 h_addr  [NUM_HARTS];
  logic  [3:0]           h_wstrb [NUM_HARTS];
  logic [LINE_W-1:0]     h_wdata [NUM_HARTS];
  logic [LINE_W-1:0]     h_rdata;
  logic                  out_req, out_gnt, out_we, out_word, out_rvalid;
  word_t                 out_addr;
  logic [3:0]            out_wstrb;
  logic [LINE_W-1:0]     out_wdata, out_rdata;
  logic  [NUM_HARTS-1:0] ev_starve_d;

  merge_dcoh dut (
    .clk, .rst_n,
    .h_req, .h_gnt, .h_addr, .h_we, .h_word, .h_wstrb, .h_wdata,
    .h_rvalid, .h_rdata,
    .out_req, .out_gnt, .out_addr, .out_we, .out_word, .out_wstrb, .out_wdata,
    .out_rvalid, .out_rdata,
    .ev_starve_d
  );

  logic [NUM_HARTS-1:0] want;
  logic [NUM_HARTS-1:0] want_we, want_word;

  logic [NUM_HARTS-1:0] inflight;
  logic [NUM_HARTS-1:0] stream;

  for (genvar h = 0; h < NUM_HARTS; h++) begin : g_drv
    always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        h_req[h] <= 1'b0; inflight[h] <= 1'b0;
      end else begin
        if (h_gnt[h])         h_req[h] <= 1'b0;  // clears AT its accepting edge
        else if (want[h] && !h_req[h] && (stream[h] || !inflight[h]))
          h_req[h] <= 1'b1;
        if (h_gnt[h])         inflight[h] <= 1'b1;
        else if (h_rvalid[h]) inflight[h] <= 1'b0;
      end
    end
    assign h_we[h]   = want_we[h];      // packed: element binds are fine
    assign h_word[h] = want_word[h];
  end : g_drv


  assign out_gnt = out_req;

  int   mem_lat = 3;
  int   lcnt;
  logic lbusy;
  word_t             saw_addr;
  logic              saw_we, saw_word;
  logic [LINE_W-1:0] saw_wdata;
  logic [3:0]        saw_wstrb;
  logic [LINE_W-1:0] wr_wdata;
  logic [3:0]        wr_wstrb;
  int                n_txn;
  logic              proto_viol;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lbusy <= 1'b0; lcnt <= 0; out_rvalid <= 1'b0; n_txn <= 0; proto_viol <= 1'b0;
      saw_addr <= '0; saw_we <= 1'b0; saw_word <= 1'b0;
      saw_wdata <= '0; saw_wstrb <= '0; wr_wdata <= '0; wr_wstrb <= '0;
    end else begin
      out_rvalid <= 1'b0;
      if (out_req && lbusy) proto_viol <= 1'b1;   // asked while busy
      if (out_req && out_gnt && !lbusy) begin
        lbusy <= 1'b1; lcnt <= mem_lat; n_txn <= n_txn + 1;
        saw_addr <= out_addr; saw_we <= out_we; saw_word <= out_word;
        saw_wdata <= out_wdata; saw_wstrb <= out_wstrb;
        if (out_we) begin wr_wdata <= out_wdata; wr_wstrb <= out_wstrb; end
      end else if (lbusy) begin
        if (lcnt > 0) lcnt <= lcnt - 1;
        else begin lbusy <= 1'b0; out_rvalid <= 1'b1; end
      end
    end
  end
  assign out_rdata = {32'hD0D0_0004, 32'hD0D0_0003, 32'hD0D0_0002, 32'hD0D0_0001};

  int   n_rv [NUM_HARTS];
  int   n_gnt[NUM_HARTS];
  int   n_starve[NUM_HARTS];
  logic multi_gnt, orphan_rsp;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_HARTS; i++) begin
        n_rv[i] <= 0; n_gnt[i] <= 0; n_starve[i] <= 0;
      end
      multi_gnt <= 1'b0; orphan_rsp <= 1'b0;
    end else begin
      for (int i = 0; i < NUM_HARTS; i++) begin
        if (h_rvalid[i])    n_rv[i]     <= n_rv[i] + 1;
        if (h_gnt[i])       n_gnt[i]    <= n_gnt[i] + 1;
        if (ev_starve_d[i]) n_starve[i] <= n_starve[i] + 1;
      end
      if ($countones(h_gnt) > 1)     multi_gnt  <= 1'b1;
      if (out_rvalid && !dut.busy_q) orphan_rsp <= 1'b1;
    end
  end

  localparam word_t A0 = 32'h0000_4000;
  localparam word_t A1 = 32'h0000_8000;
  localparam logic [LINE_W-1:0] W1 = {32'hBB00_0004, 32'hBB00_0003,
                                      32'hBB00_0002, 32'hBB00_0001};

  int guard;

  task automatic setup(input int h, input word_t a, input logic w_,
                       input logic word_, input logic [LINE_W-1:0] d);
    h_addr[h]  = a;
    h_wdata[h] = d;
    h_wstrb[h] = w_ ? 4'hF : 4'h0;
    want_we[h] = w_;  want_word[h] = word_;
  endtask

  task automatic run_one(input int h, output logic completed);
    int pre, preg;
    pre = n_rv[h]; preg = n_gnt[h];
    @(negedge clk); want[h] = 1'b1;
    guard = 0;
    while ((n_gnt[h] == preg) && guard < 300) begin @(negedge clk); guard++; end
    want[h] = 1'b0;
    guard = 0;
    while ((n_rv[h] == pre) && guard < 300) begin @(negedge clk); guard++; end
    completed = (n_rv[h] != pre);
    @(negedge clk);
  endtask

  logic done0, done1;
  int   b0, b1;

  initial begin
    want = '0; stream = '0;
    for (int i = 0; i < NUM_HARTS; i++) setup(i, '0, 1'b0, 1'b0, '0);
    repeat (3) @(negedge clk); rst_n = 1'b1; repeat (2) @(negedge clk);

    $display("=== tb_merge_dcoh ===");

    setup(0, A0, 1'b0, 1'b0, '0);
    run_one(0, done0);
    ck("LIVENESS: a lone requester completes end to end", done0 === 1'b1);
    ck("LIVENESS: the transaction reached memory", n_txn == 1);
    ck("the address reached memory intact", saw_addr === A0);

    setup(1, A1, 1'b1, 1'b0, W1);
    run_one(1, done1);
    ck("lone writer completes", done1 === 1'b1);
    ck("the write payload reached memory intact", wr_wdata === W1);
    ck("the write strobes reached memory intact", wr_wstrb === 4'hF);
    ck("we was carried", saw_we === 1'b1);
    ck("responses go to the OWNER only (hart0 got no extra)", n_rv[0] == 1);

    setup(0, A0, 1'b0, 1'b1, '0);          // MMIO-style word access
    run_one(0, done0);
    ck("LIVENESS: the word access completed", done0 === 1'b1);
    ck("word/line flag reached memory intact", saw_word === 1'b1);

    b0 = n_rv[0]; b1 = n_rv[1];
    setup(0, A0, 1'b0, 1'b0, '0);
    setup(1, A1, 1'b1, 1'b0, W1);
    guard = 0;
    while ((lbusy || dut.busy_q || (|inflight)) && guard < 200) begin
      @(negedge clk); guard++;
    end
    @(negedge clk); want[0] = 1'b1; want[1] = 1'b1;   // raised the same cycle
    guard = 0;
    while (($countones(h_req) < 2) && guard < 100) begin @(negedge clk); guard++; end
    ck("SIMULTANEOUS REQUEST: both harts really are asking at once",
       $countones(h_req) == 2);
    #1;
    ck("SIMULTANEOUS REQUEST: at most one hart granted", $countones(h_gnt) <= 1);
    ck("SIMULTANEOUS REQUEST: one IS granted (not zero -- no deadlock)",
       $countones(h_gnt) == 1);
    guard = 0;
    while ((|(want & ~inflight & ~h_gnt)) && guard < 400) begin
      if (h_gnt[0]) want[0] = 1'b0;
      if (h_gnt[1]) want[1] = 1'b0;
      @(negedge clk); guard++;
      if (want == '0) break;
    end
    want = '0;
    guard = 0;
    while (((n_rv[0] == b0) || (n_rv[1] == b1)) && guard < 400) begin
      @(negedge clk); guard++;
    end
    @(negedge clk);
    ck("SIMULTANEOUS REQUEST: hart0's transaction was NOT dropped",
       n_rv[0] == b0 + 1);
    ck("SIMULTANEOUS REQUEST: hart1's transaction was NOT dropped",
       n_rv[1] == b1 + 1);
    ck("SIMULTANEOUS REQUEST: the writer's payload survived the contention",
       wr_wdata === W1);
    ck("starvation was MEASURED during contention, not assumed",
       (n_starve[0] + n_starve[1]) > 0);

    b0 = n_rv[0]; b1 = n_rv[1];
    setup(0, A0, 1'b0, 1'b0, '0);
    setup(1, A1, 1'b1, 1'b0, W1);
    stream = '1;                            // hold req high on both harts
    want[0] = 1'b1; want[1] = 1'b1;
    repeat (200) @(negedge clk);
    want = '0; stream = '0;
    repeat (30) @(negedge clk);
    ck("FAIRNESS: hart0 made progress under sustained contention", n_rv[0] > b0);
    ck("FAIRNESS: hart1 made progress under sustained contention", n_rv[1] > b1);
    ck("FAIRNESS: neither hart was starved (counts within 2 of each other)",
       (((n_rv[0]-b0) - (n_rv[1]-b1)) <= 2) && (((n_rv[1]-b1) - (n_rv[0]-b0)) <= 2));
    ck("FAIRNESS: both harts got a substantial share (>25% each)",
       ((n_rv[0]-b0) * 4 > ((n_rv[0]-b0) + (n_rv[1]-b1))) &&
       ((n_rv[1]-b1) * 4 > ((n_rv[0]-b0) + (n_rv[1]-b1))));
    ck("the channel lock was HELD -- never asked while the downstream was busy",
       proto_viol === 1'b0);

    ck("never granted two harts in one cycle", multi_gnt === 1'b0);
    ck("never responded with no owner (no transaction lost)", orphan_rsp === 1'b0);
    ck("every granted transaction reached memory",
       n_txn == (n_gnt[0] + n_gnt[1]));

    $display("tb_merge_dcoh: checked=%0d errors=%0d n_txn=%0d h0=%0d h1=%0d starve=%0d/%0d",
             checked, errors, n_txn, n_rv[0], n_rv[1], n_starve[0], n_starve[1]);
    if (errors != 0) $display("tb_merge_dcoh: FAIL");
    else             $display("tb_merge_dcoh: PASS");
    $finish;
  end

  initial begin
    #50000;
    $display("tb_merge_dcoh: WATCHDOG TIMEOUT -- FAIL");
    $finish;
  end

endmodule
