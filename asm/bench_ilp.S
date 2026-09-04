# ILP-heavy measurement workload (the deliberate

  .section .text.init
  .globl _start
_start:
  li    x10, 200          # iteration count (steady-state window)
  li    x11, 1            # shared read-only source (no anti-dep: never written)
  li    x3,  0
  li    x4,  0
  li    x5,  0
  li    x6,  0
  li    x7,  0
  li    x8,  0
  li    x9,  0
  li    x12, 0
  li    x13, 0
  li    x14, 0
  li    x15, 0
  li    x16, 0

loop:
  add   x3,  x3,  x11     # 12 independent accumulator updates -- each is its own
  add   x4,  x4,  x11     # loop-carried chain, but the twelve chains are mutually
  add   x5,  x5,  x11     # independent, so ~12 ops are ready every cycle.
  add   x6,  x6,  x11
  xor   x7,  x7,  x11
  add   x8,  x8,  x11
  add   x9,  x9,  x11
  add   x12, x12, x11
  add   x13, x13, x11
  xor   x14, x14, x11
  add   x15, x15, x11
  add   x16, x16, x11
  addi  x10, x10, -1      # loop counter (its own chain)
  bnez  x10, loop         # single predictable branch (199/200 taken)

done:
  csrr  x24, 0xB05         # mhpm5: stall cycles
  csrr  x25, 0xB06         # mhpm6: flush cycles
  csrr  x22, 0xB03         # mhpm3: branches resolved
  csrr  x23, 0xB04         # mhpm4: mispredicts
  csrr  x20, mcycle
  csrr  x21, minstret

  li    x2, 0x200
  sw    x20, 0(x2)
  sw    x21, 4(x2)
  sw    x22, 8(x2)
  sw    x23, 12(x2)
  sw    x24, 16(x2)
  sw    x25, 20(x2)

  li    x28, 1             # done marker
spin:
  j     spin
