# Iterative fib(10) = 55, then a store/load round trip.
  .section .text.init
  .globl _start
_start:
  li   x1, 0             # a
  li   x2, 1             # b
  li   x3, 0             # i
  li   x4, 9             # trip count
loop:
  add  x5, x1, x2
  mv   x1, x2
  mv   x2, x5
  addi x3, x3, 1
  bne  x3, x4, loop
  li   x6, 40            # result address
  sw   x2, 0(x6)         # store fib(10) = 55
  lw   x7, 0(x6)         # read it back
  mv   x8, x7
