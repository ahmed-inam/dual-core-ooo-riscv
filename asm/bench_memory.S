# Working set deliberately LARGER than the 1 KB D-cache.
  .section .text.init
  .globl _start
_start:
  li    x2,  0x1000           # data base (above the code)
  li    x3,  0                # accumulator

  li    x10, 4
p1_outer:
  mv    x4,  x2
  li    x5,  1024             # 1024 words = 4 KB
p1:
  lw    x6,  0(x4)
  add   x3,  x3, x6
  addi  x4,  x4, 4
  addi  x5,  x5, -1
  bnez  x5,  p1
  addi  x10, x10, -1
  bnez  x10, p1_outer

  li    x11, 4
p2_outer:
  mv    x4,  x2
  li    x5,  64
p2:
  lw    x6,  0(x4)
  add   x3,  x3, x6
  addi  x4,  x4, 256
  addi  x5,  x5, -1
  bnez  x5,  p2
  addi  x11, x11, -1
  bnez  x11, p2_outer

  li    x12, 2
p3_outer:
  mv    x4,  x2
  li    x5,  512
p3:
  sw    x3,  0(x4)
  addi  x4,  x4, 4
  addi  x5,  x5, -1
  bnez  x5,  p3
  addi  x12, x12, -1
  bnez  x12, p3_outer

  csrr  x20, 0xB07            # hpm7  : I-cache misses
  csrr  x21, 0xB08            # hpm8  : D-cache misses
  csrr  x22, 0xB09            # hpm9  : D-cache writebacks
  csrr  x23, 0xB0A            # hpm10 : memory stall cycles
  csrr  x24, 0xB05            # hpm5  : load-use/csr stall cycles
  csrr  x25, 0xB06            # hpm6  : flush cycles
  csrr  x26, 0xB03            # hpm3  : branches
  csrr  x27, 0xB04            # hpm4  : mispredicts
  csrr  x18, mcycle
  csrr  x19, minstret

  li    x2,  0x200            # results area (low, outside the walked region)
  sw    x18, 0(x2)
  sw    x19, 4(x2)
  sw    x26, 8(x2)
  sw    x27, 12(x2)
  sw    x24, 16(x2)
  sw    x25, 20(x2)
  sw    x20, 24(x2)
  sw    x21, 28(x2)
  sw    x22, 32(x2)
  sw    x23, 36(x2)
  sw    x3,  40(x2)

  fence

  li    x28, 1
spin:
  j     spin
