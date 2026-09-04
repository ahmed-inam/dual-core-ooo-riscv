// Phase 5 exit test: the caches reach sim_mem through the.
`timescale 1ns/1ps
module tb_axi_path;
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;

  localparam int unsigned DELAY = 6;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic       d_req, d_gnt, d_we, d_rvalid, d_kill, d_flush, d_flush_done;
  logic [3:0] d_wstrb;
  word_t      d_addr, d_wdata, d_rdata;

  logic              dl_req, dl_gnt, dl_we, dl_rvalid;
  word_t             dl_addr;
  logic [LINE_W-1:0] dl_wdata, dl_rdata;
  logic       dm_req, dm_gnt, dm_we, dm_rvalid;
  logic [3:0] dm_wstrb;
  word_t      dm_addr, dm_wdata, dm_rdata;
  logic       d_ev_access, d_ev_miss, d_ev_wb;

  dcache u_dc (
    .clk, .rst_n,
    .snp_valid(1'b0), .snp_addr('0), .snp_type(coherence_pkg::SNP_TO_S),
    .snp_ack(), .snp_rsp(),
    .coh_req_valid(), .coh_req_type(), .coh_req_addr(),
    .coh_gnt(1'b1), .coh_done(1'b1), .coh_shared(1'b0),
    .coh_installed(),
    .req(d_req), .gnt(d_gnt), .addr(d_addr), .we(d_we), .wstrb(d_wstrb),
    .wdata(d_wdata), .rvalid(d_rvalid), .rdata(d_rdata),
    .kill(d_kill), .flush(d_flush), .flush_done(d_flush_done),
    .line_req(dl_req), .line_gnt(dl_gnt), .line_addr(dl_addr),
    .line_we(dl_we), .line_wdata(dl_wdata),
    .line_rvalid(dl_rvalid), .line_rdata(dl_rdata),
    .mmio_req(dm_req), .mmio_gnt(dm_gnt), .mmio_addr(dm_addr),
    .mmio_we(dm_we), .mmio_wstrb(dm_wstrb), .mmio_wdata(dm_wdata),
    .mmio_rvalid(dm_rvalid), .mmio_rdata(dm_rdata),
    .ev_access(d_ev_access), .ev_miss(d_ev_miss), .ev_wb(d_ev_wb)
  );

  logic  i_req, i_gnt, i_rvalid;
  word_t i_addr, i_rdata;
  logic              il_req, il_gnt, il_rvalid;
  word_t             il_addr;
  logic [LINE_W-1:0] il_rdata;
  logic  i_ev_access, i_ev_miss;

  icache u_ic (
    .clk, .rst_n,
    .req(i_req), .gnt(i_gnt), .addr(i_addr), .rvalid(i_rvalid), .rdata(i_rdata),
    .flush(1'b0),
    .line_req(il_req), .line_gnt(il_gnt), .line_addr(il_addr),
    .line_rvalid(il_rvalid), .line_rdata(il_rdata),
    .ev_access(i_ev_access), .ev_miss(i_ev_miss)
  );

  logic              o_req, o_gnt, o_we, o_word, o_rvalid;
  logic [3:0]        o_wstrb;
  word_t             o_addr;
  logic [LINE_W-1:0] o_wdata, o_rdata;
  logic              ev_starve_i;

  mem_arbiter u_arb (
    .clk, .rst_n,
    .d_req(dl_req), .d_gnt(dl_gnt), .d_addr(dl_addr), .d_we(dl_we),
    .d_wdata(dl_wdata), .d_rvalid(dl_rvalid), .d_rdata(dl_rdata),
    .m_req(dm_req), .m_gnt(dm_gnt), .m_addr(dm_addr), .m_we(dm_we),
    .m_wstrb(dm_wstrb), .m_wdata(dm_wdata),
    .m_rvalid(dm_rvalid), .m_rdata(dm_rdata),
    .i_req(il_req), .i_gnt(il_gnt), .i_addr(il_addr),
    .i_rvalid(il_rvalid), .i_rdata(il_rdata),
    .out_req(o_req), .out_gnt(o_gnt), .out_addr(o_addr), .out_we(o_we),
    .out_word(o_word), .out_wstrb(o_wstrb), .out_wdata(o_wdata),
    .out_rvalid(o_rvalid), .out_rdata(o_rdata),
    .ev_starve_i(ev_starve_i)
  );

  axi_req_t  axi_req;
  axi_resp_t axi_resp;

  axi_adapter u_adp (
    .clk, .rst_n,
    .req(o_req), .gnt(o_gnt), .addr(o_addr), .we(o_we), .word_mode(o_word),
    .wstrb(o_wstrb), .wdata(o_wdata), .rvalid(o_rvalid), .rdata(o_rdata),
    .axi_req, .axi_resp
  );

  word_t dbg_addr, dbg_data;
  logic  err_overlap, err_range;
  int unsigned cfg_delay, cfg_beat_delay;
  assign cfg_delay      = DELAY;
  assign cfg_beat_delay = 0;

  sim_mem #(.WORDS(8192)) u_mem (
    .clk, .rst_n, .cfg_delay, .cfg_beat_delay,
    .axi_req, .axi_resp, .dbg_addr, .dbg_data, .err_overlap, .err_range
  );

  logic mon_en, mon_clr, saw_word_burst, saw_line_burst;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || mon_clr) begin
      saw_word_burst <= 1'b0;
      saw_line_burst <= 1'b0;
    end else if (mon_en) begin
    if (axi_req.aw_valid && axi_resp.aw_ready) begin
      if (axi_req.aw.len == 8'd0) saw_word_burst <= 1'b1;
      if (axi_req.aw.len == 8'd3) saw_line_burst <= 1'b1;
    end
    if (axi_req.ar_valid && axi_resp.ar_ready) begin
      if (axi_req.ar.len == 8'd0) saw_word_burst <= 1'b1;
      if (axi_req.ar.len == 8'd3) saw_line_burst <= 1'b1;
    end
    end
  end

  int errors = 0;
  task chkw(input string n, input word_t g, input word_t e);
    if (g !== e) begin $display("  FAIL %s = %08h (exp %08h)", n, g, e); errors++; end
    else $display("  ok   %s = %08h", n, g);
  endtask

  task automatic dacc(input word_t a, input logic w_, input logic [3:0] st,
                      input word_t wd, output word_t d);
    d_req = 1'b1; d_addr = a; d_we = w_; d_wstrb = st; d_wdata = wd;
    @(posedge clk); while (!d_gnt) @(posedge clk);
    @(negedge clk); d_req = 1'b0; d_we = 1'b0;
    @(posedge clk); while (!d_rvalid) @(posedge clk);
    d = d_rdata; @(negedge clk);
  endtask

  task automatic ifetch(input word_t a, output word_t d);
    i_req = 1'b1; i_addr = a;
    @(posedge clk); while (!i_gnt) @(posedge clk);
    @(negedge clk); i_req = 1'b0;
    @(posedge clk); while (!i_rvalid) @(posedge clk);
    d = i_rdata; @(negedge clk);
  endtask

  word_t d, di;
  int    starve0;

  initial begin
    mon_en=0; mon_clr=1;
    d_req=0; d_addr='0; d_we=0; d_wstrb='0; d_wdata='0; d_kill=0; d_flush=0;
    i_req=0; i_addr='0; dbg_addr='0;
    for (int i = 0; i < 8192; i++) u_mem.mem[i] = 32'hE000_0000 + 32'(i);
    repeat (3) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    $display("=== AXI path: caches -> arbiter -> adapter -> sim_mem ===");

    dacc(32'h0000_0100, 1'b0, 4'h0, '0, d);
    chkw("D fill word 0 via 4-beat burst", d, 32'hE000_0040);
    dacc(32'h0000_010C, 1'b0, 4'h0, '0, d);
    chkw("D fill word 3 (burst assembled in order)", d, 32'hE000_0043);

    ifetch(32'h0000_0200, di);
    chkw("I fill through the shared adapter", di, 32'hE000_0080);

    dacc(32'h0000_0100, 1'b1, 4'hF, 32'h5151_5151, d);   // dirty it
    dacc(32'h0000_0500, 1'b0, 4'h0, '0, d);                  // same set, way 1
    dacc(32'h0000_0900, 1'b0, 4'h0, '0, d);                  // evict one
    dbg_addr = 32'h0000_0100; #1;
    chkw("evicted dirty line written back over AXI", dbg_data, 32'h5151_5151);

    mon_clr = 1'b1; @(negedge clk); mon_clr = 1'b0; mon_en = 1'b1;
    dacc(32'h0200_4000, 1'b1, 4'hF, 32'h0BAD_C0DE, d);
    if (saw_word_burst) $display("  ok   MMIO issued a single-beat burst (AxLEN=0)");
    else begin $display("  FAIL MMIO did not issue a single-beat burst"); errors++; end
    if (saw_line_burst) begin $display("  FAIL MMIO issued a 4-beat line burst"); errors++; end
    mon_en = 1'b0;

    starve0 = 0;
    fork
      begin d_req = 1'b1; d_addr = 32'h0000_1100; d_we = 1'b0; d_wstrb = '0; end
      begin i_req = 1'b1; i_addr = 32'h0000_1500; end
    join
    @(posedge clk);
    if (d_gnt && !i_gnt) $display("  ok   D wins arbitration over I");
    else if (!d_gnt && i_gnt) begin $display("  FAIL I won over D"); errors++; end
    else $display("  ..   neither granted this cycle (adapter busy)");
    @(negedge clk); d_req = 1'b0; i_req = 1'b0;
    repeat (80) @(negedge clk);

    if (err_overlap) begin $display("  FAIL sim_mem saw overlapping bursts"); errors++; end
    else $display("  ok   no overlapping read/write bursts (grant held)");
    if (err_range) begin $display("  FAIL an access fell out of range"); errors++; end

    if (errors == 0) $display("AXIPATH PASS");
    else             $display("AXIPATH FAIL: %0d", errors);
    $finish;
  end
endmodule
