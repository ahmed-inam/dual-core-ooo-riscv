# Exercises every way a prediction can be wrong, and

  .section .text.init
  .globl _start
_start:
  li    x20, 0x200         # result base (NOT x2 -- x2 is sp, and the nested
  li    sp, 0x1000         # stack pointer for the nested-call test

  li    x10, 20            # train the branch taken 20 times
  li    x11, 0
train_loop:
  addi  x11, x11, 1
  addi  x10, x10, -1
  bnez  x10, train_loop    # strongly taken by the end
  sw    x11, 0(x20)         # expect 20

  li    x10, 0
  li    x12, 7
  bnez  x10, wrong_way     # predicted taken (trained), actually NOT taken
  addi  x12, x12, 1        # must execute: 7 -> 8
  j     dir_done
wrong_way:
  li    x12, 999           # must NOT execute
dir_done:
  sw    x12, 4(x20)         # expect 8

  la    x5, tgt_a
  li    x13, 0
  jalr  x1, 0(x5)          # first: trains BTB with tgt_a
back_a:
  la    x5, tgt_b
  jalr  x1, 0(x5)          # second: BTB says tgt_a, truth is tgt_b
back_b:
  sw    x13, 8(x20)         # expect 1 + 16 = 17
  j     ras_test

tgt_a:
  addi  x13, x13, 1
  jr    x1
tgt_b:
  addi  x13, x13, 16
  jr    x1

ras_test:
  li    x14, 0
  li    x10, 20            # train this branch taken
  li    x15, 0
spec_train:
  addi  x15, x15, 1
  addi  x10, x10, -1
  bnez  x10, spec_train
  li    x10, 0
  bnez  x10, poison_path   # predicted taken -> fetch runs into the call below
  j     after_poison
poison_path:
  jal   x1, leaf_poison    # speculatively fetched: pushes a bogus RAS frame
  nop
after_poison:
  jal   x1, leaf_good
  addi  x14, x14, 4        # reached only if leaf_good returned correctly
  sw    x14, 12(x20)        # expect 2 + 4 = 6
  j     nest_test

leaf_poison:
  li    x14, 900           # must never execute
  ret
leaf_good:
  addi  x14, x14, 2
  ret

nest_test:
  li    x16, 0
  jal   x1, lvl1
  sw    x16, 16(x20)        # expect 1 + 2 + 4 = 7

  li    x28, 1             # done marker
spin:
  j     spin

lvl1:
  addi  sp, sp, -16
  sw    x1, 0(sp)
  addi  x16, x16, 1
  jal   x1, lvl2
  lw    x1, 0(sp)
  addi  sp, sp, 16
  ret

lvl2:
  addi  sp, sp, -16
  sw    x1, 0(sp)
  addi  x16, x16, 2
  li    x10, 0
  bnez  x10, never_here
  jal   x1, lvl3
  lw    x1, 0(sp)
  addi  sp, sp, 16
  ret
never_here:
  li    x16, 800
  j     spin

lvl3:
  addi  x16, x16, 4
  ret
