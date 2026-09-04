#!/bin/bash
# RVFI versus Spike, offline per-instruction trace comparison.
set -u
cd "$(dirname "$0")/.."
HEX=${1:-asm/ctest_rvfi.hex}
ELF=${2:-/tmp/ctest_rvfi.elf}
SPIKE=${SPIKE:-/opt/spike/bin/spike}
RISCV_DV=${RISCV_DV:-${RISCV_REFS:-/opt/refs}/riscv-dv}

CORE_SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/alu.sv \
rtl/common/branch_unit.sv rtl/common/mul_unit.sv rtl/common/div_unit.sv rtl/common/decoder.sv \
rtl/common/imm_gen.sv rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv \
rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv"

if [ ! -f "$ELF" ] && [ "$HEX" = "asm/ctest_rvfi.hex" ]; then
  riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -static \
    -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles ${OPT:--O2} \
    -T asm/link_rvfi.ld asm/crt0_rvfi.S asm/ctest.c -o "$ELF" -lgcc \
    2>/dev/null || { echo "RVFI COMPARE: elf build failed"; exit 1; }
fi

verilator --binary --timing -Wno-fatal -Wno-EOFNEWLINE -Mdir obj_rvfi_ooo \
  -o tb_rvfi_ooo $CORE_SRCS tb/ooo/core_wrap.sv tb/ooo/tb_rvfi_ooo.sv \
  --top-module tb_rvfi_ooo > build_tb_rvfi.log 2>&1 \
  || { echo "RVFI COMPARE: tb build failed"; exit 1; }

./obj_rvfi_ooo/tb_rvfi_ooo +HEX="$HEX" > run_tb_rvfi.log 2>&1
grep -q "RVFI DONE PASS" run_tb_rvfi.log \
  || { echo "RVFI COMPARE: RTL run did not finish clean"; exit 1; }
grep "^V " run_tb_rvfi.log > /tmp/rvfi.log
python3 scripts/rvfi_to_csv.py /tmp/rvfi.log /tmp/rtl.csv > /dev/null

timeout 120 "$SPIKE" --isa=rv32im_zicsr --log-commits -l \
  --log=/tmp/spike_commits.log "$ELF" 2>/dev/null
python3 "$RISCV_DV/scripts/spike_log_to_trace_csv.py" \
  --log /tmp/spike_commits.log --csv /tmp/spike.csv > /dev/null 2>&1

rm -f /tmp/rvfi_cmp.log   # comparator opens a+; a stale [PASSED] would false-green the check below
cd "$RISCV_DV/scripts" && python3 - << 'EOF'
from instr_trace_compare import compare_trace_csv
compare_trace_csv('/tmp/rtl.csv', '/tmp/spike.csv', 'rtl', 'spike',
                  '/tmp/rvfi_cmp.log')
EOF
tail -2 /tmp/rvfi_cmp.log
grep -E "\[(PASSED|FAILED)\]" /tmp/rvfi_cmp.log | tail -1 | grep -q "\[PASSED\]" && exit 0 || exit 1
