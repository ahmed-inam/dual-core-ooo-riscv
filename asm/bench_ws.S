# WORKING-SET sweep. The footprint varies; the TOTAL NUMBER OF
  .section .text.init
  .globl _start
_start:
  li    x2,  0x1000          # data base
  li    x9,  0x100
  lw    x10, 0(x9)           # walk length, in words
  lw    x11, 4(x9)           # pass count
  li    x3,  0               # accumulator

outer:
  mv    x4,  x2              # cursor
  mv    x5,  x10             # words remaining this pass
inner:
  lw    x6,  0(x4)
  add   x3,  x3, x6
  addi  x4,  x4, 4
  addi  x5,  x5, -1
  bnez  x5,  inner
  addi  x11, x11, -1
  bnez  x11, outer

  csrr  x20, 0xB07           # hpm7  : I-cache misses
  csrr  x21, 0xB08           # hpm8  : D-cache misses
  csrr  x22, 0xB09           # hpm9  : D-cache writebacks
  csrr  x23, 0xB0A           # hpm10 : memory stall cycles
  csrr  x24, 0xB05           # hpm5  : load-use / csr stalls
  csrr  x25, 0xB06           # hpm6  : flush cycles
  csrr  x26, 0xB03           # hpm3  : branches
  csrr  x27, 0xB04           # hpm4  : mispredicts
  csrr  x18, mcycle
  csrr  x19, minstret

  li    x2,  0x200
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
