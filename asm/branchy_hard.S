# The ADVERSARIAL branch kernel: an xorshift
  .section .text.init
  .globl _start
_start:
  li   t0, 256         # trip count
  li   t1, 0           # acc
  li   t2, 0           # i
  li   t6, 0x2545F491  # xorshift state (nonzero seed)
  csrr s0, mcycle
loop:
  slli t3, t6, 13
  xor  t6, t6, t3
  srli t3, t6, 17
  xor  t6, t6, t3
  slli t3, t6, 5
  xor  t6, t6, t3
  andi t3, t6, 1
  beqz t3, even        # data-random: unlearnable
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
  sw   t1, 4(t4)       # acc, machine-comparable
  li   t0, 1
  la   t1, tohost
  sw   t0, 0(t1)
1: j 1b
  .section .tohost, "aw", @progbits
  .align 4
  .globl tohost
tohost: .word 0
