# BUS ERRORS ARE FAULTS: a load whose fill returns SLVERR traps, is retried, and the program still finishes.
  .section .data
  .align 12
buf:
  .space 2048                      # 512 words, twice the D-cache, so reads keep missing

  .section .text
  .globl main
main:
  bnez  a0, hart_other

  la    t0, handler
  csrw  mtvec, t0
  li    t6, 0                      # fault count, owned by the handler

  la    s0, buf
  li    s1, 512
  li    s2, 0x1234

  mv    s3, s0
  li    s4, 0
1:
  add   s5, s2, s4
  sw    s5, 0(s3)                  # a faulted store fill is retried by the cache
  addi  s3, s3, 4
  addi  s4, s4, 1
  bne   s4, s1, 1b
  fence

  li    s6, 3
2:
  mv    s3, s0
  li    s4, 0
3:
  lw    s5, 0(s3)                  # a faulted load traps and is retried by the handler
  add   s7, s2, s4
  bne   s5, s7, bad
  addi  s3, s3, 4
  addi  s4, s4, 1
  bne   s4, s1, 3b
  addi  s6, s6, -1
  bnez  s6, 2b

  li    a0, 0
  ret
bad:
  li    a0, 1
  ret

  .align 4
handler:
  csrr  t5, mcause
  li    t4, 5                      # load access fault: re-execute the load
  bne   t5, t4, 4f
  addi  t6, t6, 1
4:
  mret

hart_other:
  li    a0, 0
  ret
