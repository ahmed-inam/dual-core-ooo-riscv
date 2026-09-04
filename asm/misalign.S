# EXECUTE-TIME EXCEPTIONS, WHICH THIS ENVIRONMENT HAS NEVER

  .equ MCAUSE_INSN_MISALIGNED,  0
  .equ MCAUSE_LOAD_MISALIGNED,  4
  .equ MCAUSE_STORE_MISALIGNED, 6
  .equ EXPECT_TRAPS,            5

  .section .text
  .globl main
main:
  li    t3, 0
  li    t4, 0

  la    t0, misalign_handler
  csrw  mtvec, t0                  # DIRECT mode; the handler is .align 4

  la    t1, scratch
  addi  t1, t1, 1
  lw    t2, 0(t1)                  # TRAPS

  la    t1, scratch
  addi  t1, t1, 1
  li    t2, 0x12345678
  sw    t2, 0(t1)                  # TRAPS

  la    t1, some_label
  addi  t1, t1, 2
  jalr  x0, t1, 0                  # TRAPS, and does not transfer control

some_label:
  nop

  la    t1, scratch
  addi  t1, t1, 1                  # odd address: misaligned for a 2-byte access
  lh    t2, 0(t1)                  # TRAPS, cause 4

  la    t1, scratch
  addi  t1, t1, 1
  li    t2, 0x1234
  sh    t2, 0(t1)                  # TRAPS, cause 6

  li    t0, EXPECT_TRAPS
  bne   t3, t0, mis_bad            # wrong number of traps

  li    t0, 0x51
  bne   t4, t0, mis_bad            # right count, WRONG causes -- which is the
  li    a0, 0
  ret

mis_bad:
  li    a0, 1
  ret

  .align 4
misalign_handler:
  csrw  mscratch, t5               # ONE scratch register, and no memory
  csrr  t5, mcause
  addi  t3, t3, 1                  # count this trap

  beqz  t5, h_fetch                # 0  instruction address misaligned
  addi  t5, t5, -4
  beqz  t5, h_load                 # 4  load address misaligned
  addi  t5, t5, -2
  beqz  t5, h_store                # 6  store address misaligned
  j     h_other

h_fetch:  ori  t4, t4, 0x01
          j    h_skip
h_load:   ori  t4, t4, 0x10
          j    h_skip
h_store:  ori  t4, t4, 0x40
          j    h_skip
h_other:  ori  t4, t4, 0x80        # any other cause -- makes a wrong trap

h_skip:
  csrr  t5, mepc
  addi  t5, t5, 4
  csrw  mepc, t5

  csrr  t5, mscratch
  mret

  .section .data
  .align 4
scratch:
  .word 0xA5A5A5A5
  .word 0x5A5A5A5A
