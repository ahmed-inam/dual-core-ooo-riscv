# DO THE RVFI MEMORY CHANNELS USE ONE CONVENTION?
  .section .data
  .align 6
buf:
  .word 0, 0, 0, 0
  .align 6
buf2:
  .word 0, 0, 0, 0

  .section .text
  .globl main
main:
  bnez  a0, hart_other

  la    t0, buf
  la    t1, buf2
  li    a0, 0                      # a0 accumulates the FIRST failure code

  li    t2, 0xA1
  sb    t2, 0(t0)
  li    t2, 0xB2
  sb    t2, 1(t0)
  li    t2, 0xC3
  sb    t2, 2(t0)
  li    t2, 0xD4
  sb    t2, 3(t0)
  fence

  lbu   t3, 0(t0)
  li    t4, 0xA1
  bne   t3, t4, fail1
  lbu   t3, 1(t0)
  li    t4, 0xB2
  bne   t3, t4, fail1
  lbu   t3, 2(t0)
  li    t4, 0xC3
  bne   t3, t4, fail1
  lbu   t3, 3(t0)
  li    t4, 0xD4
  bne   t3, t4, fail1

  li    t2, 0x1122
  sh    t2, 0(t1)
  li    t2, 0x3344
  sh    t2, 2(t1)
  fence

  lhu   t3, 0(t1)
  li    t4, 0x1122
  bne   t3, t4, fail2
  lhu   t3, 2(t1)
  li    t4, 0x3344
  bne   t3, t4, fail2

  li    t2, 0x5E
  sb    t2, 4(t0)
  lbu   t3, 4(t0)                  # offset 0 of the next word -- CONTROL
  li    t4, 0x5E
  bne   t3, t4, fail3

  li    t2, 0x6F
  sb    t2, 5(t0)
  lbu   t3, 5(t0)                  # offset 1 -- forwarded, subword
  li    t4, 0x6F
  bne   t3, t4, fail3

  li    t2, 0x70
  sb    t2, 6(t0)
  lbu   t3, 6(t0)                  # offset 2 -- forwarded, subword
  li    t4, 0x70
  bne   t3, t4, fail3

  li    t2, 0x81
  sb    t2, 7(t0)
  lbu   t3, 7(t0)                  # offset 3 -- forwarded, subword
  li    t4, 0x81
  bne   t3, t4, fail3

  li    t2, 0x9AB2
  sh    t2, 8(t1)
  lhu   t3, 8(t1)                  # halfword forward at offset 0
  li    t4, 0x9AB2
  bne   t3, t4, fail3

  li    t2, 0xCDE4
  sh    t2, 10(t1)
  lhu   t3, 10(t1)                 # halfword forward at offset 2
  li    t4, 0xCDE4
  bne   t3, t4, fail3

  li    t2, 0xFF
  sb    t2, 12(t0)
  fence
  lb    t3, 12(t0)                 # sign-extends to 0xFFFFFFFF
  li    t4, -1
  bne   t3, t4, fail4

  li    t5, 0x11                   # WAW pair 1: addi t5,x0,0x11 ...
  li    t5, 0x22                   #   ... overwritten unread
  li    t6, 0x33                   # WAW pair 2, different register
  li    t6, 0x44
  li    t5, 0x55                   # WAW pair 3, back on t5
  li    t5, 0x66

  mv    t3, t5                     # t3 <- t5   (reads t5)
  li    t5, 0x77                   # writes t5  (WAR against the read above)

  jal   t0, x5_target              # rd = x5: RAS PUSH on the alternate link reg
  j     x5_done
x5_target:
  jr    t0                         # rs1 = x5, rd = x0: RAS POP
x5_done:
  la    t2, x5_push
  jalr  t0, t2, 0                  # rd = x5, rs1 = x7 non-link: push only
x5_push:
  mv    t1, ra                     # preserve main's return address
  la    t2, x5_both
  jalr  ra, t2, 0                  # rd = x1, rs1 = x7: push on the usual link
x5_both:
  mv    ra, t1                     # restore before anything can `ret`

  li    t3, 100
  li    t4, 0
  div   t5, t3, t4                 # RISC-V: division by zero yields all ones
  li    t6, -1
  bne   t5, t6, fail6
  rem   t5, t3, t4                 # remainder by zero yields the DIVIDEND
  bne   t5, t3, fail6
  divu  t5, t3, t4                 # unsigned divide by zero: also all ones
  li    t6, -1
  bne   t5, t6, fail6

  li    t3, 0x80000000
  li    t4, -1
  div   t5, t3, t4
  bne   t5, t3, fail6

  li    a0, 0                      # every case passed
  ret

fail6:
  li    a0, 6
  ret

fail1:
  li    a0, 1
  ret
fail2:
  li    a0, 2
  ret
fail3:
  li    a0, 3
  ret
fail4:
  li    a0, 4
  ret

hart_other:
  li    a0, 0
  ret
