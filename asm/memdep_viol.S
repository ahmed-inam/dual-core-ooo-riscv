# The VIOLATION kernel: the store's address
  .section .text.init
  .globl _start
_start:
  li   t0, 16
  li   t1, 0
  li   t2, 0
  li   t5, 3
  li   a0, 0x500
  sw   zero, 0(a0)     # X starts 0
  csrr s0, mcycle
loop:
  mv   t6, t2
  div  t4, t6, t5      # ~0 result but 33 cycles late
  andi t4, t4, 0       # address offset ALWAYS 0 -- but unknown till done
  add  t4, a0, t4
  sw   t2, 0(t4)       # store X = i (address late-known)
  lw   a2, 0(a0)       # load X -- MUST see i, not the stale value
  add  t1, t1, a2
  addi t2, t2, 1
  blt  t2, t0, loop
  csrr s2, mcycle
  sub  s2, s2, s0
  li   t4, 0x400
  sw   s2, 0(t4)
  li   a3, 120
  li   t0, 1
  bne  t1, a3, bad
  j    done
bad:
  li   t0, 2
done:
  la   t3, tohost
  sw   t0, 0(t3)
1: j 1b
  .section .tohost, "aw", @progbits
  .align 4
  .globl tohost
tohost: .word 0
