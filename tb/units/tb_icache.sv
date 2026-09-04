// Directed unit test for the I-cache.
`timescale 1ns/1ps
module tb_icache;
  import rv32i_pkg::*;
  import mem_pkg::*;

  localparam int unsigned LATENCY = 10;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic  req, gnt, rvalid, flush;
  word_t addr, rdata;
  logic [3:0][31:0] rdata_line;
  logic [1:0]       rdata_woff;
  logic [3:0]       rdata_wmask;
  logic  line_req, line_gnt, line_rvalid;
  word_t line_addr;
  logic [LINE_W-1:0] line_rdata;
  logic  ev_access, ev_miss;

  icache u_ic (
    .clk, .rst_n,
    .req, .gnt, .addr, .rvalid, .rdata,
    .rdata_line, .rdata_woff, .rdata_wmask,
    .flush,
    .line_req, .line_gnt, .line_addr, .line_rvalid, .line_rdata,
    .ev_access, .ev_miss
  );

  stub_linemem #(.LATENCY(LATENCY), .WORDS(4096)) u_mem (
    .clk, .rst_n,
    .req(line_req), .gnt(line_gnt), .addr(line_addr),
    .rvalid(line_rvalid), .rdata(line_rdata)
  );

  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;

  int n_miss = 0;
  always_ff @(posedge clk) if (rst_n && ev_miss) n_miss <= n_miss + 1;

  logic count_en = 0;
  int   n_gnt = 0, n_rvalid = 0;
  always_ff @(posedge clk) if (rst_n && count_en) begin
    if (gnt)    n_gnt    <= n_gnt + 1;
    if (rvalid) n_rvalid <= n_rvalid + 1;
  end

  int errors = 0;
  task chk(input string n, input int g, input int e);
    if (g !== e) begin $display("  FAIL %s = %0d (exp %0d)", n, g, e); errors++; end
    else $display("  ok   %s = %0d", n, g);
  endtask

  task automatic fetch(input word_t a, output word_t d, output int cycles);
    int t0;
    req = 1'b1; addr = a;
    @(posedge clk); while (!gnt) @(posedge clk);
    t0 = cyc;
    @(negedge clk); req = 1'b0;
    @(posedge clk); while (!rvalid) @(posedge clk);
    d = rdata; cycles = cyc - t0;
    if (rdata !== rdata_line[rdata_woff]) begin
      $display("  FAIL whole-line: rdata=%h != line[woff=%0d]=%h",
               rdata, rdata_woff, rdata_line[rdata_woff]); errors++;
    end
    if (rdata_woff !== a[3:2]) begin
      $display("  FAIL woff: got %0d exp %0d (addr %h)", rdata_woff, a[3:2], a);
      errors++;
    end
    for (int w = 0; w < 4; w++)
      if (rdata_wmask[w] !== (2'(w) >= rdata_woff)) begin
        $display("  FAIL wmask[%0d]=%b exp %b (woff=%0d)",
                 w, rdata_wmask[w], (2'(w) >= rdata_woff), rdata_woff); errors++;
      end
    @(negedge clk);
  endtask

  word_t d;
  int    t, m0;

  initial begin
    req = 0; addr = '0; flush = 0;
    for (int i = 0; i < 4096; i++) u_mem.mem[i] = 32'hC0DE_0000 + 32'(i);
    repeat (3) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    $display("=== icache: 1 KB, 2-way, 16 B lines, LATENCY=%0d ===", LATENCY);

    fetch(32'h0000_0040, d, t);
    if (d === 32'hC0DE_0010) $display("  ok   cold miss returns correct word");
    else begin $display("  FAIL cold miss data = %08h", d); errors++; end
    chk("cold miss cycles", t, LATENCY + 3);

    fetch(32'h0000_0040, d, t);
    chk("hit cycles (1 = flop tags, combinational compare)", t, 1);
    if (d !== 32'hC0DE_0010) begin $display("  FAIL hit data"); errors++; end

    m0 = n_miss;
    fetch(32'h0000_0044, d, t);
    if (d !== 32'hC0DE_0011) begin $display("  FAIL word 1 data = %08h", d); errors++; end
    fetch(32'h0000_0048, d, t);
    fetch(32'h0000_004C, d, t);
    chk("misses while walking the rest of the line", n_miss - m0, 0);

    fetch(32'h0000_0240, d, t);
    chk("second tag in same set: miss cost", t, LATENCY + 3);
    m0 = n_miss;
    fetch(32'h0000_0040, d, t);
    chk("first line still resident (2-way)", n_miss - m0, 0);

    fetch(32'h0000_0440, d, t);   // third tag, same set -> evicts LRU
    m0 = n_miss;
    fetch(32'h0000_0040, d, t);   // the hit-protected line must SURVIVE
    chk("hit-protected line survived eviction", n_miss - m0, 0);
    m0 = n_miss;
    fetch(32'h0000_0240, d, t);   // the LRU line must be GONE
    chk("LRU victim was evicted", n_miss - m0, 1);

    @(negedge clk); flush = 1'b1;
    @(negedge clk); flush = 1'b0;
    m0 = n_miss;
    fetch(32'h0000_0040, d, t);
    chk("post-fence.i access misses", n_miss - m0, 1);
    chk("fence.i cost (flash, not a walk)", t, LATENCY + 3);

    begin
      n_gnt = 0; n_rvalid = 0; count_en = 1'b1;
      req = 1'b1;
      for (int i = 0; i < 8; i++) begin
        addr = 32'h0000_0040 + 32'((i % 4) * 4);
        @(negedge clk);
      end
      req = 1'b0;
      @(negedge clk); count_en = 1'b0;
      chk("accepts while req held 8 cycles (1/cycle = full fetch bandwidth)", n_gnt, 8);
      chk("responses delivered", n_rvalid, 8);
    end

    begin
      word_t dd;
      int    tt;
      req = 1'b1; addr = 32'h0000_0640;
      @(posedge clk); while (!gnt) @(posedge clk);
      @(negedge clk); req = 1'b0;
      repeat (4) @(negedge clk);          // fill is in M_REQ/M_WAIT
      flush = 1'b1; @(negedge clk); flush = 1'b0;
      @(posedge clk); while (!rvalid) @(posedge clk);
      if (rdata === 32'hC0DE_0190) $display("  ok   killed fill still delivers its word");
      else begin $display("  FAIL fill data = %08h", rdata); errors++; end
      @(negedge clk);
      m0 = n_miss;
      fetch(32'h0000_0640, dd, tt);
      chk("fill killed by fence.i was NOT installed", n_miss - m0, 1);
    end

    if (errors == 0) $display("ICACHE PASS misses=%0d", n_miss);
    else             $display("ICACHE FAIL: %0d", errors);
    $finish;
  end
endmodule
