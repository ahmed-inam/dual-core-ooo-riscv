#!/bin/bash
# Compiled-C workload gate for the out-of-order core.
set -u
cd "$(dirname "$0")/.."
SPIKE=${SPIKE:-/opt/spike/bin/spike}
RISCV_DV=${RISCV_DV:-${RISCV_REFS:-/opt/refs}/riscv-dv}
GCC=riscv64-unknown-elf-gcc
CSRC=asm/csrc
WORK=/tmp/ctest_suite
mkdir -p "$WORK"

EXEMPT="vt_csr vt_misalign"

DUAL_ONLY="share contend stress bench_par"

if [ $# -ge 1 ]; then
  LIST="$*"
else
  LIST=""
  for f in "$CSRC"/*.c; do
    b=$(basename "$f" .c)
    case " $DUAL_ONLY " in *" $b "*) continue ;; esac
    grep -q "int main" "$f" && LIST="$LIST $b"
  done
fi

OOO_SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv \
rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv \
rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv \
rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv \
rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv \
rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv rtl/ooo/prf.sv \
rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv"

if [ ! -x obj_rvfi_ooo/tb_rvfi_ooo ]; then
  verilator --binary --timing -Wno-fatal -Wno-EOFNEWLINE -Mdir obj_rvfi_ooo \
    -o tb_rvfi_ooo $OOO_SRCS tb/ooo/core_wrap.sv tb/ooo/tb_rvfi_ooo.sv \
    --top-module tb_rvfi_ooo > "$WORK/build_harness.log" 2>&1 \
    || { echo "CTEST-SUITE: harness build failed"; exit 1; }
fi

PASS=0; FAIL=0; FAILED=""
for N in $LIST; do
  SRC="$CSRC/$N.c"
  [ -f "$SRC" ] || { echo "  [$N] no source"; FAIL=$((FAIL+1)); FAILED="$FAILED $N"; continue; }

  "$GCC" -march=rv32im_zicsr -mabi=ilp32 -static -mcmodel=medany \
    -fvisibility=hidden -nostdlib -nostartfiles ${OPT:--O2} \
    -T asm/link_rvfi.ld asm/crt0_rvfi.S "$SRC" -o "$WORK/$N.elf" -lgcc 2>/dev/null
  if [ ! -f "$WORK/$N.elf" ]; then
    echo "  [$N] compile failed"; FAIL=$((FAIL+1)); FAILED="$FAILED $N"; continue
  fi
  riscv64-unknown-elf-objcopy -O binary "$WORK/$N.elf" "$WORK/$N.bin"
  od -An -tx4 -w4 -v "$WORK/$N.bin" | tr -d ' ' > "$WORK/$N.hex"

  ./obj_rvfi_ooo/tb_rvfi_ooo +HEX="$WORK/$N.hex" > "$WORK/$N.rtl.log" 2>&1
  if ! grep -q "RVFI DONE PASS" "$WORK/$N.rtl.log"; then
    R=$(grep -oE "invalid entry [0-9]+|RVFI DONE FAIL[^$]*|RVFI TIMEOUT" "$WORK/$N.rtl.log" | head -1)
    echo "  [$N] RTL did not finish clean: $R"
    FAIL=$((FAIL+1)); FAILED="$FAILED $N"; continue
  fi
  RET=$(grep -c '^V ' "$WORK/$N.rtl.log")

  if echo " $EXEMPT " | grep -q " $N "; then
    echo "  [$N] PASS (clean, trace-exempt) ret=$RET"
    PASS=$((PASS+1)); continue
  fi

  grep "^V " "$WORK/$N.rtl.log" > "$WORK/$N.rvfi.log"
  python3 scripts/rvfi_to_csv.py "$WORK/$N.rvfi.log" "$WORK/$N.rtl.csv" > /dev/null 2>&1
  timeout 180 "$SPIKE" --isa=rv32im_zicsr --log-commits -l \
    --log="$WORK/$N.spike.log" "$WORK/$N.elf" 2>/dev/null
  python3 "$RISCV_DV/scripts/spike_log_to_trace_csv.py" \
    --log "$WORK/$N.spike.log" --csv "$WORK/$N.spike.csv" > /dev/null 2>&1
  rm -f "$WORK/$N.cmp.log"   # comparator opens a+; a stale [PASSED] here false-greens the grep below
  ( cd "$RISCV_DV/scripts" && python3 - "$WORK/$N.rtl.csv" "$WORK/$N.spike.csv" "$WORK/$N.cmp.log" << 'PY'
import sys
from instr_trace_compare import compare_trace_csv
compare_trace_csv(sys.argv[1], sys.argv[2], 'rtl', 'spike', sys.argv[3])
PY
  )
  VERDICT=$(grep -E "\[(PASSED|FAILED)\]" "$WORK/$N.cmp.log" | tail -1)   # last real verdict line (ignore trailing blanks/stale)
  if echo "$VERDICT" | grep -q "\[PASSED\]"; then
    M=$(echo "$VERDICT" | grep -oE "\[PASSED\]: [0-9]+ matched")
    echo "  [$N] $M (ret=$RET)"
    PASS=$((PASS+1))
  else
    echo "  [$N] TRACE MISMATCH vs Spike: $(grep -oE "\[FAILED\][^$]*" "$WORK/$N.cmp.log" | head -1)"
    FAIL=$((FAIL+1)); FAILED="$FAILED $N"
  fi
done

echo "CTEST-SUITE: pass=$PASS fail=$FAIL$FAILED"
[ "$FAIL" -eq 0 ]
