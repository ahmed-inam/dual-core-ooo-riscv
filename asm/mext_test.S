# Step 2.7: the M-extension directed suite, run through

  .section .text.init
  .globl _start
_start:
  li   a0, 7
  li   a1, 6
  mul  a2, a0, a1
  li   t0, 42
  li   a7, 1
  bne  a2, t0, fail

  mul  a3, a0, a1
  addi a4, a3, 1
  li   t0, 43
  li   a7, 2
  bne  a4, t0, fail

  la   t1, buf
  mul  a5, a0, a1
  sw   a5, 0(t1)
  lw   t2, 0(t1)
  li   t0, 42
  li   a7, 3
  bne  t2, t0, fail

  li   a0, -1
  li   a1, -1
  mulh a2, a0, a1
  li   a7, 4
  bnez a2, fail

  mulhu a2, a0, a1
  li   t0, 0xFFFFFFFE
  li   a7, 5
  bne  a2, t0, fail

  mulhsu a2, a0, a1
  li   t0, 0xFFFFFFFF
  li   a7, 6
  bne  a2, t0, fail

  li   a0, 100
  li   a1, 7
  div  a2, a0, a1
  li   t0, 14
  li   a7, 7
  bne  a2, t0, fail
  rem  a2, a0, a1
  li   t0, 2
  li   a7, 8
  bne  a2, t0, fail

  li   a0, -100
  div  a2, a0, a1
  li   t0, -14
  li   a7, 9
  bne  a2, t0, fail
  rem  a2, a0, a1
  li   t0, -2
  li   a7, 10
  bne  a2, t0, fail

  li   a0, 5
  li   a1, 0
  div  a2, a0, a1
  li   t0, -1
  li   a7, 11
  bne  a2, t0, fail
  rem  a2, a0, a1
  li   t0, 5
  li   a7, 12
  bne  a2, t0, fail

  li   a0, 0x80000000
  li   a1, -1
  div  a2, a0, a1
  li   t0, 0x80000000
  li   a7, 13
  bne  a2, t0, fail
  rem  a2, a0, a1
  li   a7, 14
  bnez a2, fail

  li   a0, 90
  li   a1, 9
  div  a2, a0, a1
  addi a3, a2, 5
  li   t0, 15
  li   a7, 15
  bne  a3, t0, fail

  li   a0, 3
  li   a1, 5
  mul  a2, a0, a1
  mul  a3, a1, a1
  mul  a4, a0, a0
  li   a7, 16
  li   t0, 15
  bne  a2, t0, fail
  li   t0, 25
  bne  a3, t0, fail
  li   t0, 9
  bne  a4, t0, fail

  li   a0, 11
  li   a1, 13
  mul  a2, a0, a1        # producer
  addi a3, x0, 1         # unrelated filler
  addi a4, a2, 0         # dist-2 consumer
  li   t0, 143
  li   a7, 17
  bne  a4, t0, fail

  li   a0, 3
  li   a1, 5
  csrr s0, mcycle
  mul  t0, a0, a1
  mul  t1, a1, a0
  mul  t2, a0, a0
  mul  t3, a1, a1
  mul  t4, a0, a1
  mul  t5, a1, a0
  mul  t6, a0, a0
  mul  s1, a1, a1
  csrr s2, mcycle
  sub  s2, s2, s0
  li   t0, 0x400
  sw   s2, 0(t0)

  li   a0, 100
  li   a1, 7
  csrr s0, mcycle
  div  t1, a0, a1
  csrr s2, mcycle
  sub  s2, s2, s0
  li   t0, 0x400
  sw   s2, 4(t0)

  li   a0, 90
  li   a1, 9
  csrr s0, mcycle
  div  t1, a0, a1
  addi t2, x0, 1
  addi t3, x0, 2
  addi t4, x0, 3
  addi t5, x0, 4
  addi t6, x0, 5
  addi s3, x0, 6
  addi s4, x0, 7
  addi s5, x0, 8
  addi s6, x0, 9
  addi s7, x0, 10
  csrr s2, mcycle
  sub  s2, s2, s0
  li   t0, 0x400
  sw   s2, 8(t0)

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
buf:  .word 0
