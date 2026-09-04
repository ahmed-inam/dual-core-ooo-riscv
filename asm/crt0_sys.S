# Minimal C runtime for the tb_compliance harness.

  .section .text.init
  .globl _start
_start:
  li   sp, 0x0000FF00        # 256 KB memory, 16-byte aligned top
  call main
  slli a0, a0, 1             # code<<1 | 1: 0 -> 1 (PASS), n -> odd FAIL
  ori  a0, a0, 1
  la   t0, tohost
  sw   a0, 0(t0)
1:
  j    1b

  .section .tohost, "aw", @progbits
  .align 4
  .globl tohost
tohost: .word 0
