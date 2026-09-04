# Exercises the RAS properly, which bench_branchy does not

  .section .text.init
  .globl _start
_start:
  li    sp, 0x1000
  li    x20, 0x200         # result base
  li    x21, 0             # accumulator

  li    x22, 10
sh_loop:
  jal   x1, a1
  addi  x22, x22, -1
  bnez  x22, sh_loop

  li    x22, 5
rec_loop:
  li    a0, 30
  jal   x1, recurse
  addi  x22, x22, -1
  bnez  x22, rec_loop

  li    x22, 5
nest_loop:
  jal   x1, n1
  addi  x22, x22, -1
  bnez  x22, nest_loop

  csrr  x24, 0xB05         # stalls
  csrr  x25, 0xB06         # flushes
  csrr  x26, 0xB03         # branches resolved
  csrr  x27, 0xB04         # mispredicts
  csrr  x10, mcycle
  csrr  x11, minstret

  sw    x10, 0(x20)
  sw    x11, 4(x20)
  sw    x26, 8(x20)
  sw    x27, 12(x20)
  sw    x24, 16(x20)
  sw    x25, 20(x20)
  sw    x21, 24(x20)       # accumulator: proves the calls actually ran

  li    x28, 1             # done marker
spin:
  j     spin

a1: addi sp,sp,-16
    sw   x1,0(sp)
    addi x21,x21,1
    jal  x1,a2
    lw   x1,0(sp)
    addi sp,sp,16
    ret
a2: addi sp,sp,-16
    sw   x1,0(sp)
    jal  x1,a3
    lw   x1,0(sp)
    addi sp,sp,16
    ret
a3: addi sp,sp,-16
    sw   x1,0(sp)
    jal  x1,a4
    lw   x1,0(sp)
    addi sp,sp,16
    ret
a4: addi x21,x21,1
    ret

recurse:
    addi sp,sp,-16
    sw   x1,0(sp)
    addi x21,x21,1
    beqz a0, rec_base
    addi a0,a0,-1
    jal  x1,recurse        # <- the single recursive call site
rec_base:
    lw   x1,0(sp)
    addi sp,sp,16
    ret

n1: addi sp,sp,-16
    sw x1,0(sp)
    addi x21,x21,1
    jal x1,n2
    lw x1,0(sp)
    addi sp,sp,16
    ret
n2: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n3
    lw x1,0(sp)
    addi sp,sp,16
    ret
n3: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n4
    lw x1,0(sp)
    addi sp,sp,16
    ret
n4: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n5
    lw x1,0(sp)
    addi sp,sp,16
    ret
n5: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n6
    lw x1,0(sp)
    addi sp,sp,16
    ret
n6: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n7
    lw x1,0(sp)
    addi sp,sp,16
    ret
n7: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n8
    lw x1,0(sp)
    addi sp,sp,16
    ret
n8: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n9
    lw x1,0(sp)
    addi sp,sp,16
    ret
n9: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n10
    lw x1,0(sp)
    addi sp,sp,16
    ret
n10: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n11
    lw x1,0(sp)
    addi sp,sp,16
    ret
n11: addi sp,sp,-16
    sw x1,0(sp)
    jal x1,n12
    lw x1,0(sp)
    addi sp,sp,16
    ret
n12: addi x21,x21,1
    ret
