# DUAL-HART TIMER INTERRUPT test program.

  .equ CLINT_BASE,    0x02000000
  .equ MTIMECMP0_LO,  0x4000
  .equ MTIMECMP0_HI,  0x4004

  .equ MSTATUS_MIE,   0x8          # mstatus bit 3
  .equ MIE_MTIE,      0x80         # mie bit 7

  .equ SPIN_LIMIT,    20000

  .section .text
  .globl main
main:
  bnez  a0, hart_other

  la    t0, timer_handler
  csrw  mtvec, t0                  # DIRECT mode: low two bits zero, and the
  li    t0, MIE_MTIE
  csrs  mie, t0
  li    t0, MSTATUS_MIE
  csrs  mstatus, t0                # interrupts live from here

  li    t1, SPIN_LIMIT
wait_irq:
  la    t2, irq_count
  lw    t3, 0(t2)
  bnez  t3, irq_arrived
  addi  t1, t1, -1
  bnez  t1, wait_irq

  li    a0, 1
  ret

irq_arrived:
  li    a0, 0
  ret

hart_other:
  li    a0, 0
  ret

  .align 4
timer_handler:
  addi  sp, sp, -16
  sw    t0, 0(sp)
  sw    t1, 4(sp)
  sw    t2, 8(sp)

  li    t0, MIE_MTIE
  csrc  mie, t0

  la    t0, irq_count
  lw    t1, 0(t0)
  addi  t1, t1, 1
  sw    t1, 0(t0)

  lw    t0, 0(sp)
  lw    t1, 4(sp)
  lw    t2, 8(sp)
  addi  sp, sp, 16
  mret

  .section .data
  .align 2
  .globl irq_count
irq_count:
  .word 0
