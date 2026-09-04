# THE LR/SC SHAPES stress.hex DOES NOT PRODUCE.

  .equ RETRY_LIMIT, 2000

  .section .text
  .globl main
main:
  la    s0, shared
  la    s1, flag
  bnez  a0, hart_one

  lr.w  t0, (s0)
  sc.w  t1, t0, (s0)

  lr.w  t0, (s0)
  sc.w  t1, t0, (s0)

  li    t2, 1
  fence rw, rw
  sw    t2, 0(s1)                  # hart1 may now touch the line
  fence rw, rw

  li    t3, 64
2:
  lr.w  t0, (s0)
  sc.w  t1, t0, (s0)               # some of these land with a snoop in window
  addi  t3, t3, -1
  bnez  t3, 2b

  li    t3, RETRY_LIMIT
3:
  lr.w  t0, (s0)
  addi  t0, t0, 1
  sc.w  t1, t0, (s0)
  beqz  t1, 4f                     # sc.w writes 0 on SUCCESS
  addi  t3, t3, -1
  bnez  t3, 3b
  li    a0, 1                      # never succeeded -- report it
  ret
4:
  li    a0, 0
  ret

hart_one:
  li    t3, RETRY_LIMIT
1:
  lw    t0, 0(s1)
  bnez  t0, 2f
  addi  t3, t3, -1
  bnez  t3, 1b
  li    a0, 0                      # hart0 never released us; not our verdict
  ret
2:
  li    t3, 48
3:
  lw    t0, 0(s0)                  # a GETS into hart0's window: snoop-to-S
  li    t1, 0
  sw    t1, 0(s0)                  # a GETM: kills the reservation, forces backoff
  addi  t3, t3, -1
  bnez  t3, 3b
  li    a0, 0
  ret

  .section .data
  .align 4
shared:
  .word 0
  .word 0
  .word 0
  .word 0
flag:
  .word 0
