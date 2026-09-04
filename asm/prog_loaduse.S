# The load-use hazard in three instructions: a load followed
  .section .text.init
  .globl _start
_start:
  li   x2, 40
  lw   x3, 0(x2)
  addi x4, x3, 8         # dist-1 consumer of a LOAD -> stall required
