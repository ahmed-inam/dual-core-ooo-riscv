# IRQ-during-stall sweep target. A short straight-line body
  .section .text.init
  .globl _start
_start:
  li    x2, 0x200          # data base
  la    x1, handler
  csrw  mtvec, x1
  li    x1, 0x37
  sw    x1, 0(x2)          # preload the word the swept load reads
  li    x11, 0x111
  li    x10, 0             # handler count -- MUST precede interrupt enable: an
  li    x1, 0x888          # MEIE | MTIE | MSIE
  csrw  mie, x1
  csrwi mstatus, 8         # MIE
main:
  addi  x12, x0, 1
  lw    x5, 0(x2)          # swept load: dmem_stall in M, then load-use below
  add   x6, x5, x11        # load-use consumer
  sw    x6, 4(x2)          # swept store: dmem_stall in M, write-once required
  addi  x13, x0, 2
  lw    x7, 4(x2)          # readback through memory
  addi  x14, x0, 3
  li    x28, 1             # done flag
spin:
  j     spin

handler:
  addi  x10, x10, 1
  csrr  x15, mepc
  csrr  x16, mcause
  mret
