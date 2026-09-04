# Rebuilding the .hex files from source

Every binary in the project is reproducible from a `.S` in this directory.

## Standard programs and benchmarks

```
riscv64-unknown-elf-gcc -march=rv32i_zicsr_zifencei -mabi=ilp32 -static \
  -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
  -T link.ld  NAME.S -o /tmp/NAME.elf
riscv64-unknown-elf-objcopy -O binary /tmp/NAME.elf /tmp/NAME.bin
od -An -tx4 -w4 -v /tmp/NAME.bin | tr -d ' ' > NAME.hex
```

`bench_branchy.S` uses `-T bench.ld`; `mispredict_test.S` uses `-T mis.ld`.
Drop `_zifencei` for programs with no `fence.i` (it only affects which
instructions the assembler will accept).

## Compliance (55 tests, built from riscv-tests sources)

```
-march=rv32i_zicsr_zifencei -I <riscv-tests>/env/p -I <riscv-tests>/isa/macros/scalar
-T link.ld
```
plus `nm | awk '$3=="tohost"'` for the per-test `.tohost` file. gcc 13 rejects
`fence.i` without `_zifencei`. Excluded as not-applicable: `ma_data`
(needs HW misaligned access), `breakpoint` (trigger module), `pmpaddr` (PMP).

## Note on the seven `prog_*` files

`prog`, `prog_fib`, `prog_branch`, `prog_fwd`, `prog_loaduse`,
`prog_trap_illegal` and `prog_trap_timer` were hand-assembled during S1/S2 and
had NO source until 2026-08-05, when they were recovered by disassembling the
hex. All seven rebuild with identical instruction words; the originals were
uppercase hex, and the two trap programs carried trailing zero padding that the
assembler does not emit (harmless -- `$readmemh` loads into a zeroed array).
The original `.hex` files are kept as the reference artifact; the `.S` files
are the documented source.

## Do NOT modify bench_branchy.S

It anchors the S3 fingerprint (834/681/217/23/98/23), the 3667-entry retirement
sequence diff, and the closed-form cycle attribution. One added instruction
breaks all three simultaneously. Full-system runs use `bench_memory.S`, which
carries its own `fence` to push results out of the write-back D-cache.

## Compiled-C tests (ctest, ctest_smc)

```
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -static \
  -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -O2 \
  -T link.ld crt0.S ctest.c -o /tmp/ctest.elf -lgcc
# ctest_smc: add _zifencei to -march, use crt0_sys.S (64 KB stack for tb_sys)
```
then objcopy/od as above. `-lgcc` supplies the soft mul/div; the disassembly
must contain ZERO mul/div/rem instructions (grep it - that check is part of
the point). For the Spike twin: relink at 0x80000000, sp to 0x8003FFF0, and
make tohost a 64-bit dword with a fromhost symbol beside it (HTIF reads 64
bits; a 32-bit tohost with nonzero adjacent bytes parses as a device command
and hangs).

## RVFI cross-check binary (ctest_rvfi)

Same source as ctest, shared-base flavor for the Spike comparison:
```
riscv64-unknown-elf-gcc -march=rv32i_zicsr -mabi=ilp32 -static \
  -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -O2 \
  -T link_rvfi.ld crt0_rvfi.S ctest.c -o ctest_rvfi.elf -lgcc
```
link_rvfi.ld = link.ld at 0x80000000; crt0_rvfi.S carries the dword tohost +
fromhost and sp=0x8003FFF0. Keep the ELF - spike consumes it directly; the
hex is the objcopy/od of the same image and the RTL harness aliases it via
addr[17:2].

## rv32um compliance (8 tests, added at S5 step 2.8)

Same recipe as the base compliance set, `-march=rv32im_zicsr_zifencei`,
sources at `<riscv-tests>/isa/rv32um/*.S` (mul mulh mulhsu mulhu div divu
rem remu). ctest/ctest_rvfi build with `-march=rv32im_zicsr` as of 2.8.
WARNING learned the hard way: never express the div-by-zero corner through
C operators -- it is UB and gcc's value-range analysis deletes the test
and hardwires the failure; use inline asm (see ctest.c phase 7).

## Dual-hart compiled-C programs (mh, contend, saturate, stress, share, min_sl)

**This recipe was not committed anywhere and had to be reconstructed twice.**

```
riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -static \
  -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -O2 \
  -T asm/link_rvfi.ld asm/crt0_multihart.S asm/csrc/NAME.c \
  -o asm/NAME.elf -lgcc
[ asm/NAME.elf -nt asm/csrc/NAME.c ] || exit 1      # objcopy SUCCEEDS on a stale ELF
riscv64-unknown-elf-objcopy -O binary asm/NAME.elf /tmp/NAME.bin
od -An -tx4 -w4 -v /tmp/NAME.bin | tr -d ' ' > asm/NAME.hex
```

`link_rvfi.ld`, NOT `link.ld`: the multihart flavour bases at `0x8000_0000`,
and the memory model loads the hex at that base while **Spike loads the ELF by
its own addresses**. Getting this wrong produces a run that dies before its
first retirement and reports no mismatches, which reads exactly like a clean
run.

**VALIDATE AGAINST THE ELF, NOT THE HEX.** A `.hex` is a raw word dump carrying
no addresses at all, so `link.ld` and `link_rvfi.ld` produce BYTE-IDENTICAL hex
and a diff of it cannot fail. Rebuild an existing program and compare
`riscv64-unknown-elf-nm` output -- `_start`, `main`, `tohost`, `park_forever`.
Verified for this recipe: `contend` rebuilds byte-identical AND symbol-identical
(`_start 80000000, tohost 80001000, park_forever 800000dc, main 80002000`).

## Dual-hart HAND-WRITTEN ASSEMBLY (lrsc_trap, lrsc_qtrap, irq_mh, irq_ctx, ...)

Same recipe with the `.S` in place of the `.c`, and **one flag differs**:

```
riscv64-unknown-elf-gcc -march=rv32ima_zicsr -mabi=ilp32 -static \
  -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -O2 \
  -T asm/link_rvfi.ld asm/crt0_multihart.S asm/NAME.S \
  -o asm/NAME.elf -lgcc
[ asm/NAME.elf -nt asm/NAME.S ] || exit 1
riscv64-unknown-elf-objcopy -O binary asm/NAME.elf /tmp/NAME.bin
od -An -tx4 -w4 -v /tmp/NAME.bin | tr -d ' ' > asm/NAME.hex
```

**`rv32ima_zicsr`, NOT `rv32im_zicsr`.** The dual-hart C recipe above omits the
`a` because no C program here uses atomics; the assembly ones do, and the
assembler refuses with *"unrecognized opcode `lr.w`, extension `a` required"*.
It fails loudly, unlike its twin one level out: `run_rvfi_sys_ooo.sh` hardcoded
`--isa=rv32im_zicsr` for SPIKE, where the same omission made `lr.w` trap as
ILLEGAL and the comparator reported `[PASSED]: 6 matched` vacuously (S6-6.8).
`cpu_atomic_prog_test` exists for the one field that fixes the UVM side of it,
`ref_isa = "rv32ima_zicsr"`.

VALIDATED the way this file requires -- rebuilt `asm/lrsc_trap.S` with the
recipe above and compared against the committed artefacts: hex BYTE-IDENTICAL
and `nm` identical (`_start 80000000, main 80002000, tohost 80001000,
park_forever 800000dc, shared 80003100`).

Before invoking gcc, run `./scripts/check_uvm_comments.sh`. A `.S` comment whose
first word after the hash is a preprocessor keyword is parsed as that directive;
the guard covers `*.S` and it caught one while `lrsc_qtrap.S` was being written
(`#     if (snoop_clear[h] ...` -> `#if`).

Note `crt0_multihart.S` HANGS on a single hart by design (its barrier waits for
NUM_HARTS done flags); that is deliberate, not a defect to work around.

## The comment strip, and why the .hex were not rebuilt

Every comment in `asm/*.S`, `asm/litmus/*.S` and `asm/csrc/*.c` was removed for
publication, leaving one header line per file. The binaries were NOT rebuilt,
because they did not change: all 74 programs were assembled or compiled twice
with the same toolchain, once from the original source and once from the
stripped source, and every pair came out byte-identical. The `.hex` timestamps
were then updated so `scripts/check_asm_fresh.sh` records that the committed
binaries do correspond to the committed sources.

A comment cannot reach the binary, so this is the expected result. It was
measured rather than assumed because the guard exists precisely for the case
where someone believes that and is wrong.
