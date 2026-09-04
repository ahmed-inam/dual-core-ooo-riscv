# A dependency chain with no independent work between links, so
  .section .text.init
  .globl _start
_start:
  li   x1, 5
  addi x2, x1, 3         # dist-1 on x1
  addi x3, x1, 7         # dist-2 on x1
  add  x4, x2, x3        # dist-1 and dist-2 in one instruction
  addi x5, x4, 100
  sub  x6, x5, x1
