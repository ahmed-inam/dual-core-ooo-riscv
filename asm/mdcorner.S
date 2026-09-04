# THE M-EXTENSION VALUE CORNERS.

  .section .text
  .globl main
main:
  li    t6, 0                          # failure accumulator

  li    t0, 1234
  li    t1, 0
  div   t2, t0, t1                     # -> -1
  li    t3, -1
  bne   t2, t3, bad
  divu  t2, t0, t1                     # -> all ones
  bne   t2, t3, bad
  rem   t2, t0, t1                     # -> the dividend
  bne   t2, t0, bad
  remu  t2, t0, t1                     # -> the dividend
  bne   t2, t0, bad

  li    t0, -7
  div   t2, t0, t1
  bne   t2, t3, bad
  rem   t2, t0, t1
  bne   t2, t0, bad

  li    t0, 0x80000000
  li    t1, -1
  div   t2, t0, t1                     # -> 0x80000000, the quotient wraps
  bne   t2, t0, bad
  rem   t2, t0, t1                     # -> 0
  bnez  t2, bad

  li    t0, -3
  li    t1, -5
  mul   t2, t0, t1                     # neg x neg
  li    t3, 15
  bne   t2, t3, bad
  mulh  t2, t0, t1                     # signed high half -> 0
  bnez  t2, bad
  li    t0, 0x80000000
  li    t1, 2
  mulhu t2, t0, t1                     # unsigned high half -> 1
  li    t3, 1
  bne   t2, t3, bad
  mulhsu t2, t0, t1                    # signed x unsigned high half -> -1
  li    t3, -1
  bne   t2, t3, bad

  li    t0, 0x80000000
  li    t1, -1
  mul   t2, t0, t1                     # low half of (-2^31 * -1) = 0x80000000
  bne   t2, t0, bad
  mulh  t2, t0, t1                     # high half -> 0
  bnez  t2, bad

  li    t0, 12345
  li    t1, 0
  mul   t2, t0, t1
  bnez  t2, bad
  mulh  t2, t0, t1
  bnez  t2, bad

  li    a0, 0
  ret
bad:
  li    a0, 1
  ret
