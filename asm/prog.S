# S1 smoke test: load immediates, then arithmetic on them.
  .section .text.init
  .globl _start
_start:
  li   x1,  5
  li   x2,  10
  li   x3,  15
  li   x4,  20
  li   x5,  25
  li   x6,  100
  li   x7,  7
  li   x8,  8
  add  x9,  x1, x2       # 15
  add  x10, x3, x4       # 35
  sub  x11, x6, x5       # 75
