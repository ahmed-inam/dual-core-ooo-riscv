# Micro-benchmark isolating the is_call bit: a hot loop containing a NON-CALL
  .section .text.init
  .globl _start
_start:
  li    sp, 0x1000
  li    x20, 0x200
  li    x21, 0
  li    x22, 40
loop:
  jal   x1, leaf           # a REAL call: pushes
  j     skip               # a PLAIN jump: must NOT push
skip:
  addi  x22, x22, -1
  bnez  x22, loop

  csrr  x24, 0xB05
  csrr  x25, 0xB06
  csrr  x26, 0xB03
  csrr  x27, 0xB04
  csrr  x10, mcycle
  csrr  x11, minstret
  sw    x10, 0(x20)
  sw    x11, 4(x20)
  sw    x26, 8(x20)
  sw    x27, 12(x20)
  sw    x24, 16(x20)
  sw    x25, 20(x20)
  sw    x21, 24(x20)
  li    x28, 1
spin:
  j     spin

leaf:
  addi  x21, x21, 1
  ret
