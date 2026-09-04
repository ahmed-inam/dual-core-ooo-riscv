// Phase 2 exit test for the memory model.
`timescale 1ns/1ps
module tb_sim_mem;
  import coreaxi_pkg::*;

  int unsigned DELAY, BEAT_DELAY;
  localparam int unsigned BEATS = 4;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  axi_req_t  req;
  axi_resp_t resp;
  logic [31:0] dbg_addr, dbg_data;
  logic        err_overlap, err_range;

  sim_mem #(.WORDS(4096)) dut (
    .clk, .rst_n,
    .cfg_delay(DELAY), .cfg_beat_delay(BEAT_DELAY),
    .axi_req(req), .axi_resp(resp),
    .dbg_addr, .dbg_data, .err_overlap, .err_range
  );

  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;

  int t_ar, t_rlast;
  always_ff @(posedge clk) if (rst_n) begin
    if (req.ar_valid && resp.ar_ready)                  t_ar    <= cyc;
    if (req.r_ready && resp.r_valid && resp.r.last)     t_rlast <= cyc;
  end

  int errors = 0;
  logic err_overlap_seen;
  always_ff @(posedge clk) if (rst_n && err_overlap) err_overlap_seen <= 1'b1;

  task chk(input string n, input int g, input int e);
    if (g !== e) begin $display("  FAIL %s = %0d (exp %0d)", n, g, e); errors++; end
    else $display("  ok   %s = %0d", n, g);
  endtask

  task automatic axi_write(input logic [31:0] addr, input logic [31:0] d0);
    req.aw       = '{id: 4'h1, addr: addr, len: 8'(BEATS-1),
                     size: AXI_SIZE_4B, burst: BURST_INCR};
    req.aw_valid = 1'b1;
    @(posedge clk); while (!resp.aw_ready) @(posedge clk);
    @(negedge clk); req.aw_valid = 1'b0;
    for (int i = 0; i < BEATS; i++) begin
      req.w       = '{data: d0 + 32'(i), strb: 4'hF, last: (i == BEATS-1)};
      req.w_valid = 1'b1;
      @(posedge clk); while (!resp.w_ready) @(posedge clk);
      @(negedge clk); req.w_valid = 1'b0;
    end
    req.b_ready = 1'b1;
    @(posedge clk); while (!resp.b_valid) @(posedge clk);
    @(negedge clk); req.b_ready = 1'b0;
  endtask

  task automatic axi_read(input logic [31:0] addr, output int cycles,
                          output logic [31:0] first_word, output logic ok);
    logic [31:0] w0;
    ok = 1'b1;
    req.ar       = '{id: 4'h2, addr: addr, len: 8'(BEATS-1),
                     size: AXI_SIZE_4B, burst: BURST_INCR};
    req.ar_valid = 1'b1;
    @(posedge clk); while (!resp.ar_ready) @(posedge clk);
    @(negedge clk); req.ar_valid = 1'b0;
    req.r_ready = 1'b1;
    for (int i = 0; i < BEATS; i++) begin
      @(posedge clk); while (!resp.r_valid) @(posedge clk);
      if (i == 0) w0 = resp.r.data;
      if (resp.r.resp != RESP_OKAY) ok = 1'b0;
      if ((i == BEATS-1) != resp.r.last) begin
        $display("  FAIL rlast misplaced at beat %0d", i); errors++;
      end
      @(negedge clk);
    end
    first_word = w0;
    req.r_ready = 1'b0;
    @(negedge clk);
    cycles = t_rlast - t_ar;   // both stamped by the same monitor
  endtask

  int          t_fill;
  logic [31:0] got;
  logic        ok;

  initial begin
    req = AXI_REQ_NONE; dbg_addr = '0;
    if (!$value$plusargs("DELAY=%d", DELAY))           DELAY = 10;
    if (!$value$plusargs("BEAT_DELAY=%d", BEAT_DELAY)) BEAT_DELAY = 0;
    repeat (3) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

    $display("=== sim_mem: DELAY=%0d BEAT_DELAY=%0d ===", DELAY, BEAT_DELAY);

    dbg_addr = 32'h0000_0400; #1;
    if (dbg_data === 32'hBAD1_BAD1) $display("  ok   unwritten memory reads poison");
    else begin $display("  FAIL unwritten memory = %08h", dbg_data); errors++; end

    axi_write(32'h0000_0100, 32'hA000_0000);
    axi_read (32'h0000_0100, t_fill, got, ok);
    if (got === 32'hA000_0000) $display("  ok   read data matches written");
    else begin $display("  FAIL read data = %08h", got); errors++; end
    if (ok) $display("  ok   all beats RESP_OKAY");
    else begin $display("  FAIL non-OKAY response"); errors++; end

    chk("fill cycles == 1 + DELAY + (BEATS-1)*(1+BEAT_DELAY)",
        t_fill, 1 + DELAY + (BEATS-1)*(1+BEAT_DELAY));

    dbg_addr = 32'h0000_010C; #1;
    if (dbg_data === 32'hA000_0003) $display("  ok   debug port reads beat 3 non-intrusively");
    else begin $display("  FAIL debug port = %08h", dbg_data); errors++; end

    axi_read(32'h0000_0100, t_fill, got, ok);
    chk("repeat read costs the same", t_fill, 1 + DELAY + (BEATS-1)*(1+BEAT_DELAY));

    axi_read(32'hDEAD_0000, t_fill, got, ok);
    if (!ok && got === 32'hBAD1_BAD1)
      $display("  ok   out-of-range read gives SLVERR + poison");
    else begin $display("  FAIL out-of-range read: ok=%0b data=%08h", ok, got); errors++; end

    if (!err_overlap) $display("  ok   no overlapping-transaction flag raised");
    else begin $display("  FAIL overlap flag raised on clean traffic"); errors++; end

    fork
      axi_write(32'h0000_0040, 32'hFEED_0000);
      begin
        int c; logic [31:0] w; logic o;
        axi_read(32'h0000_0040, c, w, o);
      end
    join
    if (err_overlap_seen)
      $display("  ok   err_overlap FIRED on a same-word read/write race (check is live)");
    else begin
      $display("  FAIL err_overlap did NOT fire on a same-word race -- the check is vacuous");
      errors++;
    end

    if (errors == 0) $display("SIMMEM PASS DELAY=%0d BEAT_DELAY=%0d fill=%0d",
                              DELAY, BEAT_DELAY, 1 + DELAY + (BEATS-1)*(1+BEAT_DELAY));
    else             $display("SIMMEM FAIL: %0d", errors);
    $finish;
  end
endmodule
