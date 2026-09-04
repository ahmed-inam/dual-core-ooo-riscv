# The branch-behavior microkernel, mcycle-timed.
  .section .text.init
  .globl _start
_start:
  li   t0, 64          # trip count
  li   t1, 0           # acc
  li   t2, 0           # i
  csrr s0, mcycle
loop:
  andi t3, t2, 1
  beqz t3, even
  addi t1, t1, 3
  j    join
even:
  addi t1, t1, 5
join:
  addi t2, t2, 1
  blt  t2, t0, loop
  csrr s2, mcycle
  sub  s2, s2, s0
  li   t4, 0x400
  sw   s2, 0(t4)
  li   t5, 256
  li   a7, 1
  bne  t1, t5, fail
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
