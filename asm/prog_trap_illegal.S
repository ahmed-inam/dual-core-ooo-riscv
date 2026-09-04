# Illegal instruction -> handler -> mret -> resume.
  .section .text.init
  .globl _start
_start:
  li    x1, 0x40
  csrw  mtvec, x1
  li    x5, 111            # pre-trap marker
  .word 0x00000000         # ILLEGAL: an all-zero encoding
  li    x6, 222            # resumed marker (mepc+4 lands here)
spin:
  j     spin

  .org 0x40
handler:
  li    x7, 333            # handler ran
  csrr  x9, mcause         # expect 2 = illegal instruction
  csrr  x8, mepc
  addi  x8, x8, 4          # step past the offending instruction
  csrw  mepc, x8
  mret
