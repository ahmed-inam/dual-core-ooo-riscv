# Runtime for DUAL-HART bare-metal tests.

  .equ NUM_HARTS,   2                 # keep in step with platform_cfg_pkg
  .equ STACK_SIZE,  0x4000            # 16 KB per hart
  .equ SLOT_STRIDE, 64
  .equ SP_TOP,      0x8003FFF0        # top of the aliased 256 KB, 16-B aligned

  .section .text.init
  .globl _start
_start:
  csrr t0, mhartid                    # t0 = my hart id
  li   t1, STACK_SIZE
  mul  t2, t0, t1                     # t2 = hartid * STACK_SIZE
  li   sp, SP_TOP
  sub  sp, sp, t2

  li   t3, NUM_HARTS
  bltu t0, t3, 1f
9:
  wfi
  j    9b
1:

  mv   a0, t0
  call main

  csrr t0, mhartid
  slli t1, t0, 6                      # hartid * SLOT_STRIDE (64 B)
  la   t2, hart_result
  add  t2, t2, t1
  sw   a0, 0(t2)                      # hart_result[hartid] = main's return

  fence rw, rw

  la   t2, hart_done
  add  t2, t2, t1
  li   t3, 1
  sw   t3, 0(t2)                      # hart_done[hartid] = 1  (release)

  fence rw, rw

  bnez t0, park_forever

  .globl _f3_barrier_begin
_f3_barrier_begin:                     # <-- step 0.7 truncates RVFI traces HERE
  li   t4, 0                          # t4 = hart index
barrier_loop:
  li   t5, NUM_HARTS
  bgeu t4, t5, barrier_done
  slli t6, t4, 6                      # hartid * SLOT_STRIDE
  la   t2, hart_done
  add  t2, t2, t6
wait_one:
  lw   t3, 0(t2)
  fence r, rw                         # acquire: flag before the result read
  beqz t3, wait_one
  addi t4, t4, 1
  j    barrier_loop
barrier_done:

  li   t4, 0
  li   a0, 0                          # a0 = accumulated result
reduce_loop:
  li   t5, NUM_HARTS
  bgeu t4, t5, reduce_done
  slli t6, t4, 6                      # hartid * SLOT_STRIDE
  la   t2, hart_result
  add  t2, t2, t6
  lw   t3, 0(t2)
  or   a0, a0, t3
  addi t4, t4, 1
  j    reduce_loop
reduce_done:

  slli a0, a0, 1                      # 1 = PASS, (n<<1)|1 = FAIL n
  ori  a0, a0, 1
  la   t0, tohost
  sw   a0, 0(t0)

park_forever:
2:
  wfi
  j    2b

  .section .data
  .align 6
  .globl hart_done
hart_done:    .fill NUM_HARTS*SLOT_STRIDE, 1, 0   # one CACHE LINE per hart
  .align 6
  .globl hart_result
hart_result:  .fill NUM_HARTS*SLOT_STRIDE, 1, 0   # one CACHE LINE per hart

  .section .tohost, "aw", @progbits
  .align 8
  .globl tohost
tohost:   .dword 0
  .align 8
  .globl fromhost
fromhost: .dword 0
