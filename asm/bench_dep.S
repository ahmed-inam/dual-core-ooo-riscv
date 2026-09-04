# Dependency/latency-bound measurement workload. The
  .section .text.init
  .globl _start
_start:
  li    x2,  0x2000         # node region base (clear of program + 0x200 stores)
  li    x10, 64             # N nodes (one word each)
  li    x5,  0              # i
build:
  addi  x6,  x5, 1          # next = i+1
  blt   x6,  x10, bok       # wrap to 0 at the end -> a single cycle of N nodes
  li    x6,  0
bok:
  slli  x7,  x5, 2          # i*4
  add   x7,  x7, x2         # &node[i]
  slli  x8,  x6, 2          # next*4
  add   x8,  x8, x2         # &node[next]
  sw    x8,  0(x7)          # node[i] = &node[next]
  addi  x5,  x5, 1
  blt   x5,  x10, build
  mv    x4,  x2             # cursor = &node[0]
  li    x3,  0             # accumulator
  li    x11, 512            # chase steps
chase:
  lw    x4,  0(x4)          # DEPENDENT load: address comes from the prior load
  add   x3,  x3, x4         # use it (kept live)
  addi  x11, x11, -1
  bnez  x11, chase          # predictable loop branch (511/512 taken)
  csrr  x24, 0xB05          # mhpm5: stall cycles
  csrr  x25, 0xB06          # mhpm6: flush events
  csrr  x22, 0xB03          # mhpm3: branches resolved
  csrr  x23, 0xB04          # mhpm4: mispredicts
  csrr  x20, mcycle
  csrr  x21, minstret
  li    x2,  0x200
  sw    x20, 0(x2)
  sw    x21, 4(x2)
  sw    x22, 8(x2)
  sw    x23, 12(x2)
  sw    x24, 16(x2)
  sw    x25, 20(x2)
  sw    x3,  24(x2)         # keep the accumulator live
  li    x28, 1              # done marker
spin:
  j     spin
