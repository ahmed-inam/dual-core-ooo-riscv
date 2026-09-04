# THE EXCLUSIVE-LINE HANDOFF. What no program here has ever done.

  .equ SPIN_LIMIT, 20000
  .equ THRASH_LINES, 128            # 128 x 16 B = 2 KB, 4x the 1 KB cache

  .section .text
  .globl main
main:
  la    t0, save_ra
  slli  t1, a0, 2
  add   t0, t0, t1
  sw    ra, 0(t0)

  la    s0, turn
  la    s1, lines
  li    s6, 0                       # phase failure flag
  bnez  a0, hart_one

  lw    t0, 0(s1)                   # L0: GETS, nobody else has it -> E
  li    a1, 1
  jal   ra, set_turn

  li    a1, 2
  jal   ra, wait_turn
  lw    t0, 16(s1)                  # L1 -> E
  li    a1, 3
  jal   ra, set_turn

  li    a1, 4
  jal   ra, wait_turn
  lw    t0, 32(s1)                  # L2 -> E
  li    a1, 5
  jal   ra, set_turn

  li    a1, 6
  jal   ra, wait_turn
  sw    t0, 32(s1)                  # UPGRADE with other = I
  lw    t0, 48(s1)                  # L3 -> E
  li    a1, 7
  jal   ra, set_turn

  li    a1, 8
  jal   ra, wait_turn
  la    a2, thrash0
  jal   ra, thrash
  lw    t0, 48(s1)                  # GETS with other = S
  la    a2, thrash0
  jal   ra, thrash
  sw    t0, 48(s1)                  # GETM with other = S
  li    a1, 9
  jal   ra, set_turn
  j     done

hart_one:
  li    a1, 1
  jal   ra, wait_turn
  lw    t0, 0(s1)                   # GETS, other holds E -> it answers TtoB
  li    a1, 2
  jal   ra, set_turn

  li    a1, 3
  jal   ra, wait_turn
  li    t0, 0x5A5A0001
  sw    t0, 16(s1)                  # GETM, other holds E -> it answers TtoN
  li    a1, 4
  jal   ra, set_turn

  li    a1, 5
  jal   ra, wait_turn
  lw    t0, 32(s1)                  # share L2 with hart0
  la    a2, thrash1
  jal   ra, thrash                  # then drop it, silently
  li    a1, 6
  jal   ra, set_turn

  li    a1, 7
  jal   ra, wait_turn
  lw    t0, 48(s1)                  # share L3, and KEEP it
  li    a1, 8
  jal   ra, set_turn

  li    a1, 9
  jal   ra, wait_turn
  j     done

done:
  la    t0, save_ra
  slli  t1, a0, 2
  add   t0, t0, t1
  lw    ra, 0(t0)                   # BEFORE the ret, or main returns into itself
  mv    a0, s6                      # 0 unless a handshake timed out
  ret

set_turn:
  fence rw, rw
  sw    a1, 0(s0)
  fence rw, rw
  ret

wait_turn:
  li    a3, SPIN_LIMIT
1:
  lw    a4, 0(s0)
  beq   a4, a1, 2f
  addi  a3, a3, -1
  bnez  a3, 1b
  li    s6, 1                       # timed out -- report, do not hang
2:
  fence rw, rw
  ret

thrash:
  li    a5, THRASH_LINES
1:
  lw    a6, 0(a2)
  addi  a2, a2, 16
  addi  a5, a5, -1
  bnez  a5, 1b
  fence rw, rw
  ret

  .section .data
  .align 4
turn:
  .word 0
  .word 0
  .word 0
  .word 0
lines:
  .rept 16
  .word 0x11223344
  .endr
thrash0:
  .rept 512
  .word 0xA5A5A5A5
  .endr
thrash1:
  .rept 512
  .word 0x5A5A5A5A
  .endr
  .align 4
save_ra:
  .word 0
  .word 0
