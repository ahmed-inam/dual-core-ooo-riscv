# ARCHITECTURAL LR/SC result gate.
  .section .text
  .globl _start_test
  .globl main
main:
_start_test:
  la    x6, lrsc_a
  la    x9, lrsc_b

  lr.w  x5,  0(x6)
  ori   x7,  x0, 1
  sc.w  x11, x7, 0(x6)            # x11 = 0 expected

  lr.w  x12, 0(x6)
  ori   x7,  x0, 2
  sc.w  x13, x7, 0(x9)            # x13 != 0 expected

  ori   x7,  x0, 3
  sc.w  x14, x7, 0(x6)            # x14 != 0 expected


  add   x17, x11, x13
  add   x17, x17, x14
  add   x17, x17, x16
  li    a0, 0
  ret

  .section .data
  .align 6
lrsc_a:   .word 0
  .align 6
lrsc_b:   .word 0
