# Runtime for the RVFI cross-check flow: ONE binary, linked at

  .section .text.init
  .globl _start
_start:
  li   sp, 0x8003FFF0        # top of the aliased 256 KB, 16-byte aligned
  call main
  slli a0, a0, 1             # tohost protocol: 1 = PASS, (n<<1)|1 = FAIL n
  ori  a0, a0, 1
  la   t0, tohost
  sw   a0, 0(t0)
1:
  j    1b

  .section .tohost, "aw", @progbits
  .align 8
  .globl tohost
tohost:   .dword 0
  .align 8
  .globl fromhost
fromhost: .dword 0
