# Directed interrupt test for the OoO machine.
  .section .text.init
  .globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  li   t0, 0x80          # MTIE
  csrw mie, t0
  li   t1, 0
  la   t2, count
  sw   t1, 0(t2)
  csrsi mstatus, 0x8     # MIE on
spin:
  la   t2, count
  lw   t3, 0(t2)
  beqz t3, spin
  li   t0, 1
  la   t1, tohost
  sw   t0, 0(t1)
1: j 1b

handler:
  la   t4, tohost
  addi t4, t4, -16
  li   t5, 1
  sw   t5, 0(t4)
  la   t4, count
  lw   t5, 0(t4)
  addi t5, t5, 1
  sw   t5, 0(t4)
  mret

  .section .tohost, "aw", @progbits
  .align 4
  .globl tohost
tohost: .word 0
  .section .data
count: .word 0
