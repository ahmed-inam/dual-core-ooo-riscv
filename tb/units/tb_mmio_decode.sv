// Locks the address map before a cache exists to violate.
`timescale 1ns/1ps
module tb_mmio_decode;
  import mem_pkg::*;

  int errors = 0;
  task chk(input string n, input logic [31:0] a, input logic exp);
    if (is_mmio(a) !== exp) begin
      $display("  FAIL %s: is_mmio(%08h)=%0b exp %0b", n, a, is_mmio(a), exp);
      errors++;
    end else $display("  ok   %s: is_mmio(%08h)=%0b", n, a, is_mmio(a));
  endtask

  initial begin
    $display("=== address map: is_mmio decode ===");

    chk("reset vector",        32'h0000_0000, 1'b0);
    chk("low RAM",             32'h0000_1000, 1'b0);
    chk("bench data",          32'h0000_0200, 1'b0);
    chk("just below CLINT",    32'h01FF_FFFF, 1'b0);
    chk("just above CLINT",    32'h0201_0000, 1'b0);
    chk("high cacheable",      32'h7FFF_FFFF, 1'b0);

    chk("clint msip",          32'h0200_0000, 1'b1);
    chk("clint mtimecmp",      32'h0200_4000, 1'b1);
    chk("clint mtime",         32'h0200_BFF8, 1'b1);
    chk("clint window top",    32'h0200_FFFF, 1'b1);

    chk("ram base",            32'h8000_0000, 1'b0);
    chk("ram high",            32'hFFFF_FFFF, 1'b0);

    if (errors == 0) $display("MMIO-DECODE PASS");
    else             $display("MMIO-DECODE FAIL: %0d", errors);
    $finish;
  end
endmodule
