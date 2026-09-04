// Directed unit test for the D-cache.
`timescale 1ns/1ps
module tb_dcache;
  import rv32i_pkg::*;
  import mem_pkg::*;

  localparam int unsigned LATENCY = 8;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic       req, gnt, we, rvalid, kill, flush, flush_done;
  logic [3:0] wstrb;
  word_t      addr, wdata, rdata;

  logic              line_req, line_gnt, line_we, line_rvalid;
  word_t             line_addr;
  logic [LINE_W-1:0] line_wdata, line_rdata;

  logic       mmio_req, mmio_gnt, mmio_we, mmio_rvalid;
  logic [3:0] mmio_wstrb;
  word_t      mmio_addr, mmio_wdata, mmio_rdata;

  logic ev_access, ev_miss, ev_wb;

  dcache dut (
    .clk, .rst_n,
    .snp_valid(1'b0), .snp_addr('0), .snp_type(coherence_pkg::SNP_TO_S),
    .snp_ack(), .snp_rsp(),
    .coh_req_valid(), .coh_req_type(), .coh_req_addr(),
    .coh_gnt(1'b1), .coh_done(1'b1), .coh_shared(1'b0),
    .coh_installed(),
    .req, .gnt, .addr, .we, .wstrb, .wdata, .rvalid, .rdata,
    .kill, .flush, .flush_done,
    .line_req, .line_gnt, .line_addr, .line_we, .line_wdata,
    .line_rvalid, .line_rdata,
    .mmio_req, .mmio_gnt, .mmio_addr, .mmio_we, .mmio_wstrb, .mmio_wdata,
    .mmio_rvalid, .mmio_rdata,
    .ev_access, .ev_miss, .ev_wb
  );

  stub_linemem #(.LATENCY(LATENCY), .WORDS(8192)) u_mem (
    .clk, .rst_n,
    .req(line_req), .gnt(line_gnt), .addr(line_addr),
    .we(line_we), .wdata(line_wdata),
    .rvalid(line_rvalid), .rdata(line_rdata)
  );

  word_t mmio_cell;
  logic  mmio_v_q;
  assign mmio_gnt = mmio_req && !mmio_v_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin mmio_v_q <= 1'b0; mmio_cell <= 32'hFACE_0000; end
    else begin
      mmio_v_q <= mmio_req && mmio_gnt;
      if (mmio_req && mmio_gnt && mmio_we) mmio_cell <= mmio_wdata;
    end
  end
  assign mmio_rvalid = mmio_v_q;
  assign mmio_rdata  = mmio_cell;

  int n_miss = 0, n_wb = 0;
  always_ff @(posedge clk) if (rst_n) begin
    if (ev_miss) n_miss <= n_miss + 1;
    if (ev_wb)   n_wb   <= n_wb + 1;
  end

  always_ff @(posedge clk) if (rst_n)
    for (int s = 0; s < SETS; s++)
      for (int w = 0; w < WAYS; w++)
        if (dut.tag_q[s][w].state == LINE_S || dut.tag_q[s][w].state == LINE_O)
          $display("  FAIL unreachable MOESI state at set %0d way %0d", s, w);

  int errors = 0;
  task chk(input string n, input int g, input int e);
    if (g !== e) begin $display("  FAIL %s = %0d (exp %0d)", n, g, e); errors++; end
    else $display("  ok   %s = %0d", n, g);
  endtask
  task chkw(input string n, input word_t g, input word_t e);
    if (g !== e) begin $display("  FAIL %s = %08h (exp %08h)", n, g, e); errors++; end
    else $display("  ok   %s = %08h", n, g);
  endtask

  task automatic dacc(input word_t a, input logic w_, input logic [3:0] st,
                      input word_t wd, input logic k, output word_t d);
    req = 1'b1; addr = a; we = w_; wstrb = st; wdata = wd;
    @(posedge clk); while (!gnt) @(posedge clk);
    @(negedge clk); req = 1'b0; we = 1'b0;
    if (k) begin kill = 1'b1; @(negedge clk); kill = 1'b0; end
    @(posedge clk); while (!rvalid) @(posedge clk);
    d = rdata;
    @(negedge clk);
  endtask

  word_t d;
  int    m0;

  initial begin
    req=0; addr='0; we=0; wstrb='0; wdata='0; kill=0; flush=0;
    for (int i = 0; i < 8192; i++) u_mem.mem[i] = 32'hD000_0000 + 32'(i);
    repeat (3) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    $display("=== dcache: 1 KB, 2-way, write-back write-allocate ===");

    dacc(32'h0000_0080, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("load miss data", d, 32'hD000_0020);
    m0 = n_miss;
    dacc(32'h0000_0084, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("load hit, same line", d, 32'hD000_0021);
    chk("no miss on same-line access", n_miss - m0, 0);

    dacc(32'h0000_0080, 1'b1, 4'hF, 32'hAAAA_0001, 1'b0, d);
    dacc(32'h0000_0080, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("store hit readback", d, 32'hAAAA_0001);
    chkw("memory NOT updated (write-back)", u_mem.mem[32], 32'hD000_0020);
    if (dut.tag_q[8][dut.lru_q[8]].state == LINE_M)
      $display("  ok   line is LINE_M after store");
    else begin $display("  FAIL line not dirty after store"); errors++; end

    dacc(32'h0000_0300, 1'b1, 4'hF, 32'hBBBB_0002, 1'b0, d);
    dacc(32'h0000_0300, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("store miss merged into fill", d, 32'hBBBB_0002);
    dacc(32'h0000_0304, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("rest of allocated line intact", d, 32'hD000_00C1);

    dacc(32'h0000_0308, 1'b1, 4'h1, 32'h0000_0055, 1'b0, d);
    dacc(32'h0000_0308, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("byte store merged, other bytes intact", d, 32'hD000_00C2 & 32'hFFFF_FF00 | 32'h55);

    dacc(32'h0000_0280, 1'b0, 4'h0, '0, 1'b0, d);   // fills way 1
    m0 = n_wb;
    dacc(32'h0000_0480, 1'b0, 4'h0, '0, 1'b0, d);   // evicts one of them
    chk("dirty eviction issued a writeback", n_wb - m0, 1);
    chkw("evicted dirty data reached memory", u_mem.mem[32], 32'hAAAA_0001);

    m0 = n_miss;
    dacc(32'h0200_BFF8, 1'b0, 4'h0, '0, 1'b0, d);   // CLINT mtime
    chkw("MMIO read bypassed to the device", d, 32'hFACE_0000);
    chk("MMIO did not count as a cacheable miss", n_miss - m0, 0);
    dacc(32'h0200_BFF8, 1'b1, 4'hF, 32'h1234_5678, 1'b0, d);
    chkw("MMIO write reached the device", mmio_cell, 32'h1234_5678);
    dacc(32'h0200_BFF8, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("MMIO read is not cached (sees the device)", d, 32'h1234_5678);

    dacc(32'h0000_0700, 1'b1, 4'hF, 32'hDEAD_BEEF, 1'b1, d);
    dacc(32'h0000_0700, 1'b0, 4'h0, '0, 1'b0, d);
    chkw("killed store did NOT merge", d, 32'hD000_01C0);
    if (dut.tag_q[16][dut.lru_q[16]].state == LINE_E)
      $display("  ok   killed store left the line LINE_E (clean)");
    else begin $display("  FAIL killed store left state %0d", dut.tag_q[16][dut.lru_q[16]].state); errors++; end

    dacc(32'h0000_0900, 1'b1, 4'hF, 32'hCCCC_0003, 1'b0, d);  // make one dirty
    m0 = n_wb;
    flush = 1'b1;
    @(posedge clk); while (!flush_done) @(posedge clk);
    @(negedge clk); flush = 1'b0; @(negedge clk);
    if (n_wb - m0 >= 1) $display("  ok   fence wrote back %0d dirty line(s)", n_wb - m0);
    else begin $display("  FAIL fence wrote back nothing"); errors++; end
    chkw("fenced data reached memory", u_mem.mem[576], 32'hCCCC_0003);
    m0 = n_miss;
    dacc(32'h0000_0900, 1'b0, 4'h0, '0, 1'b0, d);
    chk("fence left the line VALID (writeback, not invalidate)", n_miss - m0, 0);
    chkw("fenced line still readable", d, 32'hCCCC_0003);

    if (errors == 0) $display("DCACHE PASS misses=%0d writebacks=%0d", n_miss, n_wb);
    else             $display("DCACHE FAIL: %0d", errors);
    $finish;
  end
endmodule
