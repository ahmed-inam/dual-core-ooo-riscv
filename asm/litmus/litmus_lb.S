# LB (Load Buffer) as a two-hart program.

  .section .data
  .align 6
x:        .word 0
  .align 6
y:        .word 0
  .align 6
bar:      .word 0
  .align 6
bar1:     .word 0
  .align 6
skew0:    .word 0            # [S6-3.3] TB-seeded post-barrier spin count, hart 0
  .align 6
skew1:    .word 0            #          ... hart 1

  .section .text
  .globl main
main:
  mv    a5, a0

  li    t3, 1
  beqz  a5, 1f
  la    t2, bar1
  sw    t3, 0(t2)
  fence rw, rw
  la    t5, bar
  j     2f
1:
  la    t2, bar
  sw    t3, 0(t2)
  fence rw, rw
  la    t5, bar1
2:
  lw    t6, 0(t5)
  beqz  t6, 2b

  la    t0, skew0
  beqz  a5, 5f
  la    t0, skew1
5:
  lw    t1, 0(t0)
6:
  beqz  t1, 7f
  addi  t1, t1, -1
  j     6b
7:

  li    x7, 1
  beqz  a5, 3f
  la    x6, y                      # P1: 1:x6=y, 1:x8=x
  la    x8, x
  j     4f
3:
  la    x6, x                      # P0: 0:x6=x, 0:x8=y
  la    x8, y
4:
  lw    x5, 0(x6)                  # read my source
  sw    x7, 0(x8)                  # store the other (NO fence: that is the test)
  andi  a0, x5, 1
  ret
