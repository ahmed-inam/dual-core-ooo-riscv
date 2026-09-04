# The LATE-RESOLVE branch kernel: the branch
  .section .text.init
  .globl _start
_start:
  li   t0, 64
  li   t1, 0
  li   t2, 0
  li   t6, 0x2545F491
  li   t5, 3
  csrr s0, mcycle
loop:
  slli t3, t6, 13
  xor  t6, t6, t3
  srli t3, t6, 17
  xor  t6, t6, t3
  slli t3, t6, 5
  xor  t6, t6, t3
  div  t4, t6, t5      # 33-cycle producer
  andi t4, t4, 1
  beqz t4, even        # resolves LATE; ~50% unlearnable
  addi t1, t1, 3
  j    join
even:
  addi t1, t1, 5
join:
  addi t1, t1, 1
  addi t1, t1, 1
  addi t1, t1, 1
  addi t1, t1, 1
  addi t2, t2, 1
  blt  t2, t0, loop
  csrr s2, mcycle
  sub  s2, s2, s0
  li   t4, 0x400
  sw   s2, 0(t4)
  sw   t1, 4(t4)
  li   t0, 1
  la   t1, tohost
  sw   t0, 0(t1)
1: j 1b
  .section .tohost, "aw", @progbits
  .align 4
  .globl tohost
tohost: .word 0
