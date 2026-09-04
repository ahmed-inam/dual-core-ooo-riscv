# Self-modifying code. Writes an instruction into memory, fences,
  .section .text.init
  .globl _start
_start:
  li    x28, 0                 # completion flag
  li    x5,  0                 # marker written by the patched slot
  la    x6,  patch             # address of the slot to overwrite
  lw    x7,  0(x6)             # touch it: pulls the line into the I-cache too
  jal   x0,  warm

warm:
  jal   x1,  patch             # EXECUTE the slot before patching (caches it)

  li    x8,  0x0DE00293
  sw    x8,  0(x6)             # overwrite the slot in memory
  fence                        # make the store visible to the fetch path
  fence.i                      # drop the stale I-cache copy
  jal   x1,  patch             # execute the PATCHED slot
  li    x28, 1
spin:
  j     spin

  .align 4
patch:
  addi  x5, x0, 111            # original: writes 111; patched: writes 222
  jalr  x0, 0(x1)
