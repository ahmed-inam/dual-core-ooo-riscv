# A MIXED-CLASS LOOP THAT DOES NOT KNOW WHEN IT WILL BE

  .equ MSTATUS_MIE,  0x00000008
  .equ MIE_MTIE,     0x00000080          # bit 7,  machine timer
  .equ MIE_MSIE,     0x00000008          # bit 3,  machine software
  .equ OUTER,        6000
  .equ WANT_IRQ,     500                 # 1 timer + up to 599 software

  .section .text
  .globl main
main:
  bnez  a0, hart_other                   # a0 = hartid from crt0_multihart

  la    t0, ctx_handler
  csrw  mtvec, t0
  li    t0, MIE_MTIE
  csrs  mie, t0
  li    t0, MIE_MSIE
  csrs  mie, t0
  li    t0, MSTATUS_MIE
  csrs  mstatus, t0                      # interrupts live from here

  la    t2, save_ra
  sw    ra, 0(t2)

  la    s1, irq_count
  la    s2, workbuf
  li    s3, 0                            # loop counter
  li    s4, 0x9E3779B9                   # an LFSR-ish value, kept in registers

outer:
  li    t0, MIE_MSIE
  csrs  mie, t0

  add   s4, s4, s3
  xori  s4, s4, 0x2A5
  lw    t1, 0(s2)
  add   t1, t1, s4
  sw    t1, 4(s2)
  mul    t2, s4, s3
  divu   t3, s4, s3
  remu   t4, s4, s3

  sw    t3, 8(s2)
  andi  t5, s4, 7
  beqz  t5, skip
  addi  t5, t5, 1
skip:
  jal   ra, leaf
  csrr  t6, mhartid
  fence rw, rw

  lw    t0, 0(s1)
  li    t1, WANT_IRQ
  bge   t0, t1, done

  addi  s3, s3, 1
  li    t0, OUTER
  blt   s3, t0, outer

done:

  la    t2, save_ra
  lw    ra, 0(t2)
  lw    a0, 0(s1)                        # a0 = interrupts taken
  beqz  a0, ctx_none
  li    a0, 0                            # PASS: at least one landed
  ret
ctx_none:
  li    a0, 1                            # no interrupt ever arrived
  ret

leaf:
  addi  a1, a1, 1
  ret

hart_other:
  li    a0, 0
  ret

  .align 4
ctx_handler:
  csrw  mscratch, t0
  csrr  t0, mcause

  andi  t0, t0, 0xF
  addi  t0, t0, -3
  beqz  t0, mask_soft

  li    t0, MIE_MTIE                     # timer: mask MTIE, loop re-enables it
  csrc  mie, t0
  j     ctx_count
mask_soft:
  li    t0, MIE_MSIE
  csrc  mie, t0

ctx_count:
  lw    t0, 0(s1)
  addi  t0, t0, 1
  sw    t0, 0(s1)
  csrr  t0, mscratch
  mret

  .section .data
  .align 4
save_ra:
  .word 0
irq_count:
  .word 0
workbuf:
  .word 0x11111111
  .word 0x22222222
  .word 0x33333333
  .word 0x44444444
