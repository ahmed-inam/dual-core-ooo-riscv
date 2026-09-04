# Taken branch must squash the instruction behind it.
  .section .text.init
  .globl _start
_start:
  li   x1, 5
  li   x2, 10
  beq  x1, x1, target    # always taken
  li   x1, 99            # POISON: must be squashed
target:
  li   x3, 7
