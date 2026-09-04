# READ EVERY IMPLEMENTED CSR, ONCE, WITH A KNOWN COUNT.

  .equ N_CSR_MAIN, 39

  .section .text
  .globl main
main:
  csrr  t0, mvendorid          # F11  required to exist, reads 0
  csrr  t0, marchid            # F12  required to exist, reads 0
  csrr  t0, mimpid             # F13  required to exist, reads 0
  csrr  t0, mhartid            # F14  the one that differs per hart
  csrr  t0, misa               # 301  MXL=1 (RV32), I and M

  csrr  t0, mstatus            # 300
  csrr  t0, mie                # 304
  csrr  t0, mtvec              # 305
  csrr  t0, mscratch           # 340
  csrr  t0, mepc               # 341
  csrr  t0, mcause             # 342
  csrr  t0, mtval              # 343
  csrr  t0, mip                # 344

  csrr  t0, mcycle             # B00  cycles
  csrr  t0, minstret           # B02  instructions retired
  csrr  t0, mhpmcounter3       # B03  branches resolved
  csrr  t0, mhpmcounter4       # B04  branch mispredicts
  csrr  t0, mhpmcounter5       # B05  stall cycles
  csrr  t0, mhpmcounter6       # B06  flush cycles
  csrr  t0, mhpmcounter7       # B07  I-cache misses
  csrr  t0, mhpmcounter8       # B08  D-cache misses
  csrr  t0, mhpmcounter9       # B09  D-cache writebacks
  csrr  t0, mhpmcounter10      # B0A  memory stall cycles

  csrr  t0, mcycleh            # B80
  csrr  t0, minstreth          # B82
  csrr  t0, mhpmcounter3h      # B83
  csrr  t0, mhpmcounter4h      # B84
  csrr  t0, mhpmcounter5h      # B85
  csrr  t0, mhpmcounter6h      # B86
  csrr  t0, mhpmcounter7h      # B87
  csrr  t0, mhpmcounter8h      # B88
  csrr  t0, mhpmcounter9h      # B89
  csrr  t0, mhpmcounter10h     # B8A

  csrr  t0, cycle              # C00
  csrr  t0, instret            # C02
  csrr  t0, cycleh             # C80
  csrr  t0, instreth           # C82

  li    t1, 0x5A5A1234
  csrw  mscratch, t1           # 340, write
  csrr  t2, mscratch           # 340, read back
  bne   t1, t2, csr_bad

  li    t1, 0x0080             # MPP = 2'b00 (bits 12:11) | MPIE (bit 7)
  csrw  mstatus, t1            # 300, write
  csrr  t2, mstatus            # 300, read back
  li    t3, 0x1800
  and   t3, t2, t3             # isolate MPP
  li    t4, 0x1800
  bne   t3, t4, csr_bad        # MPP is hardwired to M in a machine-only core
  li    t3, 0x80
  and   t3, t2, t3             # isolate MPIE
  beqz  t3, csr_bad            # MPIE must have stuck

  li    a0, 0                  # pass
  ret

csr_bad:
  li    a0, 1                  # mscratch did not hold what was written
  ret
