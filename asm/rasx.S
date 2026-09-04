# EVERY LINK-REGISTER COMBINATION, INCLUDING THE ONE THE RAS

  .section .text
  .globl main
main:
  la    t2, save_ra
  sw    ra, 0(t2)                  # t2 is x7, NOT a link register

  la    ra, L1
  jalr  ra, ra, 0                  # rd=ra  rs1=ra   call, NOT ret (rd == rs1)
L1:
  la    ra, L2
  jalr  t0, ra, 0                  # rd=t0  rs1=ra   call AND ret -- POP+PUSH
L2:
  la    ra, L3
  jalr  x0, ra, 0                  # rd=x0  rs1=ra   ret only (rd not link)
L3:

  la    t0, L4
  jalr  ra, t0, 0                  # rd=ra  rs1=t0   call AND ret -- POP+PUSH
L4:
  la    t0, L5
  jalr  t0, t0, 0                  # rd=t0  rs1=t0   call, NOT ret
L5:
  la    t0, L6
  jalr  x0, t0, 0                  # rd=x0  rs1=t0   ret only
L6:

  la    t1, L7
  jalr  ra, t1, 0                  # rd=ra  rs1=t1   call only, no pop
L7:
  la    t1, L8
  jalr  t0, t1, 0                  # rd=t0  rs1=t1   call only, no pop
L8:
  la    t1, L9
  jalr  x0, t1, 0                  # rd=x0  rs1=t1   neither -- a plain jump
L9:

  la    t2, save_ra
  lw    ra, 0(t2)                  # BEFORE the ret, or main returns into itself
  li    a0, 0
  ret

  .section .data
  .align 4
save_ra:
  .word 0
