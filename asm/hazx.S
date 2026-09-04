# THE REGISTER-HAZARD CELLS COMPILED CODE DOES NOT PRODUCE.

  .section .text
  .globl main
main:
  la    t0, save_ra
  slli  t1, a0, 2
  add   t0, t0, t1
  sw    ra, 0(t0)

  la    t3, atomic_slot
  slli  t4, a0, 4                  # per-hart 16 B slot: no false sharing
  add   t3, t3, t4

  addi  t5, ra, 0
  jal   ra, l_war
l_war:

  jal   ra, l_waw1
l_waw1:
  jal   ra, l_waw2
l_waw2:

  li    t1, 7
  li    t2, 9
  addi  t0, x0, 3
  mul   t0, t1, t2

  addi  t3, t3, 0                  # writes t3 ...
  lr.w  t6, (t3)                   # ... and the atomic READS it: RAW
  sc.w  t0, t6, (t3)

  addi  t6, x0, 5                  # dead: overwritten by the lr.w below
  lr.w  t6, (t3)
  sc.w  t0, t6, (t3)               # close the reservation so nothing dangles

  la    t0, save_ra
  slli  t1, a0, 2
  add   t0, t0, t1
  lw    ra, 0(t0)                  # BEFORE the ret, or main returns into itself
  li    a0, 0
  ret

  .section .data
  .align 4
save_ra:
  .word 0
  .word 0
  .align 4
atomic_slot:
  .word 0
  .word 0
  .word 0
  .word 0
  .word 0
  .word 0
  .word 0
  .word 0
