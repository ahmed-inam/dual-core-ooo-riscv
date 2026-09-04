# A PROGRAM THAT DOES NOTHING, ON PURPOSE.

  .equ ITERS, 4096

  .section .text
  .globl main
main:
  bnez  a0, hart_one

  li    t0, ITERS
  li    t1, 0
  li    t2, 1
1:
  add   t1, t1, t2                 # RAW on t1 every iteration, deliberately
  xor   t3, t1, t2
  sub   t4, t3, t2
  addi  t0, t0, -1
  bnez  t0, 1b

  mv    a0, x0
  ret

hart_one:
  li    a0, 0
  ret
