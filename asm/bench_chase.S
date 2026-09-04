# POINTER CHASE. Same working set and the same number of
  .section .text.init
  .globl _start
_start:
  li    x2,  0x1000          # node region base
  li    x9,  0x100
  lw    x10, 0(x9)           # N nodes
  lw    x11, 4(x9)           # chase steps
  li    x12, 37              # STEP: odd, so coprime with a power-of-two N

  li    x5,  0               # i
build:
  add   x6,  x5, x12         # i + STEP
  remu_emul:                 # x6 mod N, by repeated subtraction (no M ext)
  blt   x6,  x10, build_ok
  sub   x6,  x6, x10
  j     remu_emul
build_ok:
  slli  x7,  x5, 4           # i*16
  add   x7,  x7, x2          # &node[i]
  slli  x8,  x6, 4           # next*16
  add   x8,  x8, x2          # &node[next]
  sw    x8,  0(x7)
  addi  x5,  x5, 1
  blt   x5,  x10, build

  mv    x4,  x2              # cursor = &node[0]
  li    x3,  0               # accumulator
chase:
  lw    x4,  0(x4)           # DEPENDENT load: next address comes from memory
  add   x3,  x3, x4
  addi  x11, x11, -1
  bnez  x11, chase

  csrr  x20, 0xB07
  csrr  x21, 0xB08
  csrr  x22, 0xB09
  csrr  x23, 0xB0A
  csrr  x24, 0xB05
  csrr  x25, 0xB06
  csrr  x26, 0xB03
  csrr  x27, 0xB04
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
