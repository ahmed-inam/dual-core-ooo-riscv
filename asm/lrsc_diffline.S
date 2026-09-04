# THE S6-6.9 DIFFERENT-LINE BACK-OFF, WHICH HAS NEVER

  .equ RETRY_LIMIT, 2000

  .section .text
  .globl main
main:
  la    s0, line_a
  la    s1, line_b
  bnez  a0, hart_one

  li    s2, 0                      # s2 counts failures; 0 == pass

  lr.w  t0, (s0)                   # ARM   -- cnt_q == 0
  lr.w  t1, (s1)                   # BACKOFF -- cnt_q != 0, different line

  sc.w  t2, t0, (s0)
  beqz  t2, bad_success            # succeeded -> the back-off did not happen

  li    t3, RETRY_LIMIT
1:
  lr.w  t0, (s1)
  addi  t0, t0, 1
  sc.w  t2, t0, (s1)
  beqz  t2, 2f                     # success
  addi  t3, t3, -1
  bnez  t3, 1b
  li    s2, 2                      # never recovered -- the 6.9 livelock shape
  j     done
2:

  li    t3, 16
3:
  lr.w  t0, (s0)
  lr.w  t1, (s1)                   # back off again
  sc.w  t2, t0, (s0)               # must fail again, but not checked per pass:
  addi  t3, t3, -1
  bnez  t3, 3b

done:
  mv    a0, s2
  ret

bad_success:
  li    a0, 1                      # an SC succeeded on a backed-off reservation
  ret

hart_one:
  li    a0, 0
  ret

  .section .data
  .balign 64
line_a:
  .word 0
  .balign 64
line_b:
  .word 0
