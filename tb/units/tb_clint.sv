// Unit gate for the CLINT: per-hart msip and mtimecmp.
module tb_clint
  import rv32i_pkg::*;
  import mem_pkg::*;
  import platform_cfg_pkg::*;
();

  logic  clk = 1'b0, rst_n = 1'b0;
  logic  req = 1'b0, gnt, we = 1'b0, rvalid, rtc_tick = 1'b0;
  word_t addr = '0, wdata = '0, rdata;
  logic [3:0] wstrb = 4'hF;
  logic [NUM_HARTS-1:0] msip_o, mtip_o;

  int errors = 0;

  always #5 clk = ~clk;

  clint dut (.clk, .rst_n, .req, .gnt, .addr, .we, .wstrb, .wdata,
             .rvalid, .rdata, .rtc_tick, .msip_o, .mtip_o);

  task automatic wr(input word_t a, input word_t d);
    @(negedge clk); req = 1'b1; we = 1'b1; addr = a; wdata = d; wstrb = 4'hF;
    @(negedge clk); req = 1'b0; we = 1'b0;
  endtask

  task automatic rd(input word_t a, output word_t d);
    @(negedge clk); req = 1'b1; we = 1'b0; addr = a;
    @(negedge clk); req = 1'b0;
    wait (rvalid);
    d = rdata;
  endtask

  task automatic tick(input int n);
    for (int i = 0; i < n; i++) begin
      @(negedge clk); rtc_tick = 1'b1;
      @(negedge clk); rtc_tick = 1'b0;
    end
  endtask

  task automatic chk(input string what, input logic cond);
    if (!cond) begin errors++; $display("  [FAIL] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  word_t got;
  logic [63:0] t0, t1;

  initial begin
    $display("=== tb_clint (NUM_HARTS=%0d) ===", NUM_HARTS);
    repeat (3) @(negedge clk); rst_n = 1'b1; repeat (2) @(negedge clk);

    chk("msip clear out of reset", msip_o == '0);
    chk("mtip clear out of reset (mtimecmp never-expired)", mtip_o == '0);

    rd(CLINT_BASE + 32'hBFF8, got); t0 = {32'd0, got};
    tick(5);
    rd(CLINT_BASE + 32'hBFF8, got); t1 = {32'd0, got};
    chk("mtime advances on rtc_tick", t1 > t0);
    chk("mtime advanced by exactly the tick count", (t1 - t0) == 64'd5);

    rd(CLINT_BASE + 32'hBFF8, got); t0 = {32'd0, got};
    repeat (10) @(negedge clk);
    rd(CLINT_BASE + 32'hBFF8, got); t1 = {32'd0, got};
    chk("mtime frozen without rtc_tick", t1 == t0);

    for (int h = 0; h < NUM_HARTS; h++) begin
      wr(CLINT_BASE + 32'(h*4), 32'd1);
      chk($sformatf("msip[%0d] set by its own write", h), msip_o[h] === 1'b1);
      for (int o = 0; o < NUM_HARTS; o++)
        if (o != h)
          chk($sformatf("msip[%0d] NOT disturbed by hart %0d write", o, h),
              msip_o[o] === 1'b0);
      rd(CLINT_BASE + 32'(h*4), got);
      chk($sformatf("msip[%0d] reads back 1", h), got == 32'd1);
      wr(CLINT_BASE + 32'(h*4), 32'd0);
      chk($sformatf("msip[%0d] cleared", h), msip_o[h] === 1'b0);
    end

    wr(CLINT_BASE + 32'h0, 32'hFFFF_FFFE);
    chk("msip ignores bits 31:1", msip_o[0] === 1'b0);
    wr(CLINT_BASE + 32'h0, 32'd0);

    rd(CLINT_BASE + 32'hBFF8, got); t0 = {32'd0, got};
    wr(CLINT_BASE + 32'h4000, got + 32'd3);   // hart0 lo
    wr(CLINT_BASE + 32'h4004, 32'd0);         // hart0 hi = 0
    chk("mtip[0] still low before mtime reaches mtimecmp", mtip_o[0] === 1'b0);
    if (NUM_HARTS > 1)
      chk("mtip[1] low while only hart0 armed", mtip_o[1] === 1'b0);

    tick(4);
    chk("mtip[0] fires when mtime >= mtimecmp[0]", mtip_o[0] === 1'b1);
    if (NUM_HARTS > 1)
      chk("mtip[1] STILL low -- per-hart isolation", mtip_o[1] === 1'b0);

    rd(CLINT_BASE + 32'hBFF8, got);
    wr(CLINT_BASE + 32'h4000, got + 32'd1000);
    chk("mtip[0] cleared by reprogramming mtimecmp", mtip_o[0] === 1'b0);

    if (NUM_HARTS > 1) begin
      rd(CLINT_BASE + 32'hBFF8, got); t0 = {32'd0, got};
      wr(CLINT_BASE + 32'h4000 + 32'((NUM_HARTS-1)*8),     got + 32'd2);
      wr(CLINT_BASE + 32'h4000 + 32'((NUM_HARTS-1)*8 + 4), 32'd0);
      tick(3);
      chk($sformatf("mtip[%0d] fires", NUM_HARTS-1), mtip_o[NUM_HARTS-1] === 1'b1);
      chk("mtip[0] NOT disturbed by another hart's mtimecmp", mtip_o[0] === 1'b0);
    end

    wr(CLINT_BASE + 32'h4000, 32'hDEAD_BEEF);
    wr(CLINT_BASE + 32'h4004, 32'h1234_5678);
    rd(CLINT_BASE + 32'h4000, got);
    chk("mtimecmp[0] lo readback", got == 32'hDEAD_BEEF);
    rd(CLINT_BASE + 32'h4004, got);
    chk("mtimecmp[0] hi readback", got == 32'h1234_5678);

    chk("CLINT_BASE is inside the mem_pkg MMIO/CLINT decode",
        is_mmio(CLINT_BASE));
    chk("top of the 64KB CLINT window still decodes as MMIO",
        is_mmio(CLINT_BASE + 32'hFFFF));

    rd(CLINT_BASE + 32'h2000, got);
    chk("unmapped CLINT offset reads 0", got == 32'd0);

    $display("=== tb_clint: %0d error(s) ===", errors);
    if (errors == 0) $display("TB_CLINT PASS");
    else             $display("TB_CLINT FAIL");
    $finish;
  end

  initial begin
    #200000;
    $display("TB_CLINT FAIL (timeout)");
    $finish;
  end

endmodule
