# EVERY REACHABLE size x offset x direction, AND THE PAIRS

  .section .text
  .globl main
main:
  la    t0, buf                    # .align 4, so t0 + n has offset n
  li    t1, 0xA5

  sb    t1, 0(t0)
  lbu   t2, 0(t0)
  sb    t1, 1(t0)
  lbu   t2, 1(t0)
  sb    t1, 2(t0)
  lbu   t2, 2(t0)
  sb    t1, 3(t0)
  lbu   t2, 3(t0)

  li    t1, 0x1234
  sh    t1, 0(t0)
  lhu   t2, 0(t0)
  sh    t1, 2(t0)
  lhu   t2, 2(t0)

  li    t1, 0x89ABCDEF
  sw    t1, 0(t0)
  lw    t2, 0(t0)

  addi  sp, sp, -16
  sw    t1, 0(sp)
  lw    t2, 0(sp)
  sb    t1, 5(sp)
  lbu   t2, 5(sp)
  addi  sp, sp, 16

  la    t3, main
  lw    t2, 0(t3)
  lbu   t2, 2(t3)

  li    t1, 0x11223344
  sw    t1, 8(t0)
  lw    t2, 8(t0)

  sw    t1, 12(t0)
  lbu   t2, 13(t0)

  lw    t2, 8(t0)
  sw    t1, 8(t0)

  sw    t1, 8(t0)
  sw    t1, 8(t0)

  li    t4, 0x0BADC0DE
  li    t4, 0x600DC0DE

  li    a0, 0
  ret

  .section .data
  .align 4
buf:
  .word 0x00000000
  .word 0x11111111
  .word 0x22222222
  .word 0x33333333
  .word 0x44444444
