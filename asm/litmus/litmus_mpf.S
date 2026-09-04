# MP+fence.w.w+fence.tso.

  .equ SLOT_STRIDE, 64

  .section .data
  .align 6
x:        .word 0
  .align 6
y:        .word 0
  .align 6
bar:      .word 0            # hart 0 arrival flag
  .align 6
bar1:     .word 0
  .align 6
skew0:    .word 0            # [S6-3.3] TB-seeded post-barrier spin count, hart 0
  .align 6
skew1:    .word 0            #          ... hart 1            # hart 1 arrival flag

  .section .text
  .globl main

main:
  mv    a5, a0                     # a5 = my hart id (a0 is the return reg)

  li    t3, 1
  beqz  a5, 1f
  la    t2, bar1                   # hart 1 publishes bar1, waits on bar
  sw    t3, 0(t2)
  fence rw, rw
  la    t5, bar
  j     2f
1:
  la    t2, bar                    # hart 0 publishes bar, waits on bar1
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

  bnez  a5, P1

P0:
  li    x5, 1
  la    x6, x
  la    x7, y
  sw    x5, 0(x6)                  # x = 1
  fence w, w                       # <-- orders the two stores
  sw    x5, 0(x7)                  # y = 1
  li    a0, 0                      # P0 observes nothing
  ret

P1:
  la    x6, y
  la    x8, x
  lw    x5, 0(x6)                  # read y
  fence.tso                        # <-- orders the two loads
  lw    x7, 0(x8)                  # read x
  andi  x5, x5, 1
  andi  x7, x7, 1
  slli  x5, x5, 1
  or    a0, x5, x7
  ret
