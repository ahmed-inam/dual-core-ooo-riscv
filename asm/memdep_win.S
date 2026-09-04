# The SPECULATION-WIN kernel: each iteration's
  .section .text.init
  .globl _start
_start:
  li   t0, 32          # iters
  li   t1, 0           # acc
  li   t2, 0           # i
  li   t5, 3
  li   t6, 0x2545F491
  li   a0, 0x500       # store region A
  li   a1, 0x600       # load region B (disjoint)
  li   a2, 1
  sw   a2, 0(a1)
  li   a2, 2
  sw   a2, 4(a1)
  li   a2, 3
  sw   a2, 8(a1)
  li   a2, 4
  sw   a2, 12(a1)
  csrr s0, mcycle
loop:
  slli t3, t6, 13
  xor  t6, t6, t3
  srli t3, t6, 17
  xor  t6, t6, t3
  slli t3, t6, 5
  xor  t6, t6, t3
  div  t4, t6, t5      # late-known store address
  andi t4, t4, 28      # word-aligned offset 0..28 in A
  add  t4, a0, t4
  sw   t2, 0(t4)       # store: address unknown for 33 cycles
  lw   a2, 0(a1)       # loads: DISJOINT -- pure speculation win
  add  t1, t1, a2
  lw   a2, 4(a1)
  add  t1, t1, a2
  lw   a2, 8(a1)
  add  t1, t1, a2
  lw   a2, 12(a1)
  add  t1, t1, a2
  xor  t6, t6, a2      # loop-carried dependency THROUGH the load: the
  addi t2, t2, 1
  blt  t2, t0, loop
  csrr s2, mcycle
  sub  s2, s2, s0
  li   t4, 0x400
  sw   s2, 0(t4)
  li   a3, 320
  li   t0, 1
  bne  t1, a3, bad
  j    done
bad:
  li   t0, 2
done:
  la   t3, tohost
  sw   t0, 0(t3)
1: j 1b
  .section .tohost, "aw", @progbits
  .align 4
  .globl tohost
tohost: .word 0
