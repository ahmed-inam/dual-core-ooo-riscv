# LR-SC-diff-loc3: SC to a DIFFERENT address than LR.

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
skew1:    .word 0            #          ... hart 1
  .align 6
raw0:     .word 0            # [6.8] hart0 raw {x5,x8}: x5 at +0, x8 at +4
  .align 6
raw1:     .word 0            # [6.8] hart1 raw            # hart 1 arrival flag

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

  beqz  a5, 8f
  la    x6, y                      # P1: 1:x6=y, 1:x9=x
  la    x9, x
  j     9f
8:
  la    x6, x                      # P0: 0:x6=x, 0:x9=y
  la    x9, y
9:
  lr.w  x5, 0(x6)
  ori   x7, x0, 1
  sc.w  x8, x7, 0(x9)              # MUST FAIL: address differs from the LR
  la    x28, raw0
  beqz  a5, 10f
  la    x28, raw1
10:
  sw    x5, 0(x28)                 # LR result, verbatim
  sw    x8, 4(x28)                 # SC result, verbatim (0 = success per ISA)
  andi  x5, x5, 1
  andi  x8, x8, 1
  slli  x8, x8, 1
  or    a0, x8, x5
  ret
