# OoO interrupt-taking gate, for tb_core_ooo's +IRQ_AT model.
  .section .text.init
  .globl _start
_start:
  li    x1, 0x80000040     # mtvec = handler
  csrw  mtvec, x1
  li    x4, 0x80           # MTIE (bit 7)
  csrw  mie, x4
  li    x5, 0x8            # MIE (mstatus.MIE bit 3)
  csrw  mstatus, x5
  li    x6, 0              # loop counter
  li    x9, 5000           # spin budget (must be < tb timeout)
loop:
  addi  x6, x6, 1
  blt   x6, x9, loop       # spin, waiting for the interrupt
  li    x10, 0x80001000
  li    x11, 3             # tohost = 3 -> FAIL testnum 1
  sw    x11, 0(x10)
fail_spin:
  j     fail_spin

  .org 0x40
handler:
  li    x12, 0x80000ff0
  li    x13, 1
  sw    x13, 0(x12)
  li    x7, 777            # marker: handler ran
  li    x10, 0x80001000
  li    x14, 1
  sw    x14, 0(x10)
done:
  j     done
