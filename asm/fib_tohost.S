# The fib gate, self-checking via tohost.
  .section .text.init
  .globl _start
_start:
  li   x1, 0
  li   x2, 1
  li   x3, 0
  li   x4, 9
loop:
  add  x5, x1, x2
  mv   x1, x2
  mv   x2, x5
  addi x3, x3, 1
  blt  x3, x4, loop
  li   t0, 55
  li   a7, 1
  bne  x2, t0, fail
  li   t0, 34
  li   a7, 2
  bne  x1, t0, fail
  la   t1, buf
  sw   x2, 0(t1)
  lw   x7, 0(t1)
  li   a7, 3
  bne  x7, x2, fail
pass:
  li   t0, 1
  la   t1, tohost
  sw   t0, 0(t1)
1: j 1b
fail:
  slli a7, a7, 1
  ori  a7, a7, 1
  la   t1, tohost
  sw   a7, 0(t1)
1: j 1b
  .section .tohost, "aw", @progbits
  .align 4
  .globl tohost
tohost: .word 0
  .section .data
buf: .word 0
