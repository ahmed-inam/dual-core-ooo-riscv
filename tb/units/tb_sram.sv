// Unit test for the physical-memory seam.
`timescale 1ns/1ps
module tb_sram;

  localparam int unsigned WIDTH = 128;
  localparam int unsigned DEPTH = 64;
  localparam int unsigned AW    = 6;
  localparam int unsigned BEW   = WIDTH/8;

  logic clk = 0;
  always #5 clk = ~clk;

  logic            en, we;
  logic [AW-1:0]   addr;
  logic [WIDTH-1:0] wdata, rdata;
  logic [BEW-1:0]  be;

  sram_1rw #(.WIDTH(WIDTH), .DEPTH(DEPTH)) dut (
    .clk, .en, .we, .addr, .wdata, .be, .rdata
  );

  int errors = 0;
  task chk(input string n, input logic [WIDTH-1:0] g, input logic [WIDTH-1:0] e);
    if (g !== e) begin
      $display("  FAIL %s", n);
      $display("       got %032h", g);
      $display("       exp %032h", e);
      errors++;
    end else $display("  ok   %s", n);
  endtask

  task automatic wr(input logic [AW-1:0] a, input logic [WIDTH-1:0] d,
                    input logic [BEW-1:0] b);
    @(negedge clk); en = 1; we = 1; addr = a; wdata = d; be = b;
    @(negedge clk); en = 0; we = 0;
  endtask

  task automatic rd(input logic [AW-1:0] a);
    @(negedge clk); en = 1; we = 0; addr = a; be = '0;
    @(negedge clk); en = 0;
  endtask

  logic [WIDTH-1:0] snap_during;

  initial begin
    en = 0; we = 0; addr = '0; wdata = '0; be = '0;
    repeat (2) @(negedge clk);

    $display("=== sram_1rw: single-port synchronous array ===");

    rd(6'd33);
    if (rdata === '0) begin
      $display("  FAIL unwritten entry reads as ZERO (silent-bug hazard)"); errors++;
    end else $display("  ok   unwritten entry reads poison, not zero (%032h)", rdata);

    wr(6'd5, 128'hDEAD_BEEF_0123_4567_89AB_CDEF_FEED_FACE, {BEW{1'b1}});
    @(negedge clk); en = 1; we = 0; addr = 6'd5;   // address presented here
    snap_during = rdata;                            // ... data NOT here yet
    @(negedge clk); en = 0;                         // edge captured it
    chk("sync read returns written data",
        rdata, 128'hDEAD_BEEF_0123_4567_89AB_CDEF_FEED_FACE);
    if (snap_during === 128'hDEAD_BEEF_0123_4567_89AB_CDEF_FEED_FACE)
      begin $display("  FAIL read was COMBINATIONAL (data valid in the address cycle)"); errors++; end
    else $display("  ok   read is not combinational (address cycle shows stale data)");

    wr(6'd5, 128'h0000_0000_0000_0000_0000_0000_1122_3344, 16'h000F);
    rd(6'd5);
    chk("byte-enabled merge preserves untouched bytes",
        rdata, 128'hDEAD_BEEF_0123_4567_89AB_CDEF_1122_3344);

    @(negedge clk); en = 0; we = 1; addr = 6'd5;
    wdata = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF; be = {BEW{1'b1}};
    @(negedge clk); we = 0;
    chk("rdata holds while en=0",
        rdata, 128'hDEAD_BEEF_0123_4567_89AB_CDEF_1122_3344);
    rd(6'd5);
    chk("en=0 did not write",
        rdata, 128'hDEAD_BEEF_0123_4567_89AB_CDEF_1122_3344);

    wr(6'd9, 128'h1111_1111_2222_2222_3333_3333_4444_4444, {BEW{1'b1}});
    rd(6'd5);
    chk("address 5 unchanged by write to 9",
        rdata, 128'hDEAD_BEEF_0123_4567_89AB_CDEF_1122_3344);
    rd(6'd9);
    chk("address 9 holds its own data",
        rdata, 128'h1111_1111_2222_2222_3333_3333_4444_4444);

    @(negedge clk); en = 1; we = 1; addr = 6'd17;
    wdata = 128'hA5A5_A5A5_5A5A_5A5A_A5A5_A5A5_5A5A_5A5A; be = {BEW{1'b1}};
    @(negedge clk); en = 1; we = 0; addr = 6'd17;   // read the very next cycle
    @(negedge clk); en = 0;
    chk("back-to-back write then read",
        rdata, 128'hA5A5_A5A5_5A5A_5A5A_A5A5_A5A5_5A5A_5A5A);

    if (errors == 0) $display("SRAM PASS");
    else             $display("SRAM FAIL: %0d", errors);
    $finish;
  end
endmodule
