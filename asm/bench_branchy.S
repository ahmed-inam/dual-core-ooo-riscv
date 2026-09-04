# Stage 3 baseline / measurement workload.

  .section .text.init
  .globl _start
_start:
  li    x2, 0x100          # data base
  li    x3, 0              # accumulator
  li    x10, 8             # outer count

outer:
  li    x11, 12            # inner count

inner:
  lw    x5, 0(x2)          # load ...
  add   x3, x3, x5         # ... use immediately -> load-use stall
  andi  x6, x11, 1         # data-dependent condition
  beq   x6, x0, skip       # taken ~half the time (hard for a 1-bit scheme)
  addi  x3, x3, 1
skip:
  addi  x11, x11, -1
  bnez  x11, inner         # taken 11/12 -> the loop branch

  jal   x1, leaf           # call (RAS push)
  addi  x10, x10, -1
  bnez  x10, outer         # taken 7/8
  j     done

leaf:
  addi  x3, x3, 2
  ret                      # jalr x0,0(x1) -- RAS pop

done:
  csrr  x24, 0xB05         # mhpm5: stall cycles   (loop only)
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
