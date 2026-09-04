# Timer interrupt -> handler -> mret -> keep counting.
  .section .text.init
  .globl _start
_start:
  li    x1, 0x40
  csrw  mtvec, x1
  li    x2, 25             # fire the timer early
  lui   x3, 0x2004         # CLINT mtimecmp
  sw    x2, 0(x3)
  li    x4, 128            # MTIE
  csrw  mie, x4
  li    x5, 8              # MIE
  csrw  mstatus, x5
loop:
  addi  x6, x6, 1          # keep counting; must resume after the trap
  j     loop

  .org 0x40
handler:
  li    x7, 777            # handler ran
  lui   x3, 0x2004
  li    x8, -1             # push mtimecmp out so it cannot re-fire
  sw    x8, 0(x3)
  mret
