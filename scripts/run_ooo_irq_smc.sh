#!/bin/bash
# OoO coverage for interrupt-taking and self-modifying code.
cd "$(dirname "$0")/.."
PASS=0; FAIL=0; FAILED=""

OOO_SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv"
SYS_OOO_SRCS="$OOO_SRCS rtl/mem/mem_pkg.sv rtl/mem/coreaxi_pkg.sv rtl/mem/sram_1rw.sv rtl/mem/icache.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv rtl/mem/mem_arbiter.sv rtl/mem/axi_adapter.sv rtl/mem/sim_mem.sv"

if [ ! -x obj_tb_core_ooo/tco ]; then
  verilator --binary --timing -Wno-fatal -Wno-EOFNEWLINE -Mdir obj_tb_core_ooo -o tco \
    $OOO_SRCS tb/ooo/core_wrap.sv tb/ooo/tb_core_ooo.sv --top-module tb_core_ooo \
    > build_tb_core_ooo.log 2>&1
fi
r=$(timeout 30 ./obj_tb_core_ooo/tco +HEX=asm/ooo_irq.hex +TOHOST=80001000 +IRQ_AT=100 2>&1 | grep -oE "COMPLIANCE (PASS|FAIL[^$]*|TIMEOUT)" | head -1)
[ "$r" = "COMPLIANCE PASS" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); FAILED="$FAILED irq_taken($r)"; }
r=$(timeout 30 ./obj_tb_core_ooo/tco +HEX=asm/ooo_irq.hex +TOHOST=80001000 +IRQ_AT=99999999 2>&1 | grep -oE "COMPLIANCE (PASS|FAIL[^$]*|TIMEOUT)" | head -1)
case "$r" in
  "COMPLIANCE FAIL: testnum 1") PASS=$((PASS+1));;   # correct: test depends on the IRQ
  *) FAIL=$((FAIL+1)); FAILED="$FAILED irq_control($r)";;
esac

if [ ! -x obj_sys_ooo/tb_sys_ooo ]; then
  verilator --binary --timing -Wno-fatal -Wno-EOFNEWLINE -Mdir obj_sys_ooo -o tb_sys_ooo \
    $SYS_OOO_SRCS tb/ooo/tb_sys_ooo.sv --top-module tb_sys_ooo > build_sys_ooo.log 2>&1
fi
r=$(timeout 90 ./obj_sys_ooo/tb_sys_ooo +HEX=asm/ctest_smc.hex 2>&1 | grep -oE "checksum=[0-9a-f]+" | head -1)
[ "$r" = "checksum=5afe0004" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); FAILED="$FAILED smc($r)"; }

echo "OOO IRQ+SMC: pass=$PASS fail=$FAIL$FAILED"
[ $FAIL -eq 0 ]
