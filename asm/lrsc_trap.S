# DOES A TRAP CLEAR THE RESERVATION?
  .section .data
  .align 6
shared:
  .word 0

  .section .text
  .globl main
main:
  bnez  a0, hart_other

  la    t0, trap_handler
  csrw  mtvec, t0                  # DIRECT mode; the handler is .align 4
  la    t1, shared
  li    a0, 0                      # a0 accumulates the verdict

  lr.w  t3, (t1)
  li    t2, 0x11
  sc.w  t4, t2, (t1)               # rd == 0 means SUCCESS (insns/sc_w.h)
  beqz  t4, case_b                 # succeeded as expected -> go on
  li    a0, 1                      # CONTROL FAILED: SCs do not work here at
  ret                              # all, so case B would prove nothing

  li    t5, 4000
quiet_wait:
  addi  t5, t5, -1
  bnez  t5, quiet_wait

case_b:
  lr.w  t3, (t1)
  .word 0x00000000                 # ILLEGAL -> mtvec -> handler -> mret
  li    t2, 0x22
  sc.w  t4, t2, (t1)               # MUST FAIL: the trap cleared the reservation
  bnez  t4, done                   # failed as required -> pass
  li    a0, 2                      # SC SUCCEEDED ACROSS A TRAP -- the defect

done:
  ret

hart_other:
  li    a0, 0
  ret

  .align 4
trap_handler:
  csrw  mscratch, t5               # stash WITHOUT touching memory
  csrr  t5, mepc
  addi  t5, t5, 4                  # step past the illegal word
  csrw  mepc, t5
  csrr  t5, mscratch               # restore
  mret
