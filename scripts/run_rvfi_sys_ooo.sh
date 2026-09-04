#!/bin/bash
# RVFI versus Spike through the real memory system.
set -u
cd "$(dirname "$0")/.."
HEX=${1:?hex}; ELF=${2:?elf}; DELAY=${3:-10}; BEAT=${4:-1}; TH=${5:-80001000}
SPIKE=${SPIKE:-/opt/spike/bin/spike}
RISCV_DV=${RISCV_DV:-${RISCV_REFS:-/opt/refs}/riscv-dv}

OOO="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv"
SYS="$OOO rtl/mem/mem_pkg.sv rtl/mem/coreaxi_pkg.sv rtl/mem/sram_1rw.sv rtl/mem/icache.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv rtl/mem/mem_arbiter.sv rtl/mem/axi_adapter.sv rtl/common/platform_cfg_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/lrsc_unit.sv rtl/mem/sim_mem.sv"

if [ ! -x obj_rvfi_sys_ooo/tb_rvfi_sys_ooo ]; then
  verilator --binary --timing --unroll-count 1024 -Wno-fatal -Wno-EOFNEWLINE \
    -Mdir obj_rvfi_sys_ooo -o tb_rvfi_sys_ooo $SYS tb/ooo/tb_rvfi_sys_ooo.sv \
    --top-module tb_rvfi_sys_ooo > build_rvfi_sys.log 2>&1 \
    || { echo "RVFI-SYS: tb build failed"; tail -3 build_rvfi_sys.log; exit 1; }
fi

./obj_rvfi_sys_ooo/tb_rvfi_sys_ooo +HEX="$HEX" +DELAY="$DELAY" +BEAT_DELAY="$BEAT" +TOHOST="$TH" \
  > run_rvfi_sys.log 2>&1
if ! grep -q "RVFI DONE PASS" run_rvfi_sys.log; then
  echo "RVFI-SYS: RTL run did not finish clean: $(grep -oE 'RVFI DONE FAIL[^$]*|RVFISYS TIMEOUT|err_range' run_rvfi_sys.log | head -1)"
  exit 1
fi
IPC=$(grep -oE "RVFISYS DELAY=[0-9]+ BEAT_DELAY=[0-9]+ cycles=[0-9]+ instret=[0-9]+" run_rvfi_sys.log | head -1)

grep "^V " run_rvfi_sys.log > /tmp/rvfi_sys.log
python3 scripts/rvfi_to_csv.py /tmp/rvfi_sys.log /tmp/rtl_sys.csv > /dev/null

timeout 120 "$SPIKE" --isa="${RVFI_ISA:-rv32im_zicsr}" --log-commits -l \
  --log=/tmp/spike_sys.log "$ELF" 2>/dev/null
python3 "$RISCV_DV/scripts/spike_log_to_trace_csv.py" \
  --log /tmp/spike_sys.log --csv /tmp/spike_sys.csv > /dev/null 2>&1

rm -f /tmp/rvfi_sys_cmp.log
cd "$RISCV_DV/scripts" && python3 - << 'EOF'
from instr_trace_compare import compare_trace_csv
compare_trace_csv('/tmp/rtl_sys.csv', '/tmp/spike_sys.csv', 'rtl', 'spike',
                  '/tmp/rvfi_sys_cmp.log')
EOF
cd - > /dev/null
V=$(grep -E "\[(PASSED|FAILED)\]" /tmp/rvfi_sys_cmp.log | tail -1)
echo "DELAY=$DELAY BEAT=$BEAT :: $V :: $IPC"
echo "$V" | grep -q "\[PASSED\]" && exit 0 || exit 1
