# A SNOOP TO THE RESERVED LINE, INSIDE THE WINDOW.
  .section .data
  .align 6
shared:                            # hart0's LR/SC target
  .word 0
peer:                              # hart1's target: SAME 16-byte line, +4
  .word 0

  .section .text
  .globl main
main:
  bnez  a0, hart1_side

  la    t1, shared
  li    a1, 96                     # attempts
h0_loop:
  lr.w  t3, (t1)
  li    t5, 40
h0_wait:
  addi  t5, t5, -1
  bnez  t5, h0_wait
  addi  t3, t3, 1
  sc.w  t4, t3, (t1)               # rd 0 = success; either outcome is fine here
  addi  a1, a1, -1
  bnez  a1, h0_loop
  li    a0, 0
  ret

hart1_side:
  la    t1, peer
  li    a1, 3000
h1_loads:
  lw    t2, 0(t1)
  addi  a1, a1, -1
  bnez  a1, h1_loads
  li    a1, 3000
h1_stores:
  sw    a1, 0(t1)
  addi  a1, a1, -1
  bnez  a1, h1_stores
  li    a0, 0
  ret
