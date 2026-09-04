#!/bin/bash
# [S5-4c6] the same suite against the OoO `core` (obj_tb_core_ooo harness)
# riscv-tests compliance run. Excluded as not-applicable (documented):
#   ma_data   - requires HW misaligned load/store (Zicclsm); this core traps, which is spec-valid
#   (ma_fetch INCLUDED since instr-misalign traps went live: with misa.C=0 it tests cause-0 traps)
#   breakpoint- needs trigger module (tselect/tdata); not implemented
#   pmpaddr   - needs PMP; not implemented
#   (zicntr + instret_overflow INCLUDED as of S3: perf_counters implements
#    mcycle/minstret + the unprivileged cycle/instret shadows)
cd "$(dirname "$0")"
# [reorg] SELF-BUILDING: the obj was previously created by ad-hoc commands
# (a reproducibility hole the folder reorg exposed). Delete obj_* to force
# a fresh build; the [-x] guard skips when current.
if [ ! -x ../obj_tb_core_ooo/tb_core_ooo ]; then
  (cd .. && verilator --binary --timing -Wno-fatal -Wno-EOFNEWLINE \
    -Mdir obj_tb_core_ooo -o tb_core_ooo rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv rtl/common/ras.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv \
    tb/ooo/core_wrap.sv tb/ooo/tb_core_ooo.sv \
    --top-module tb_core_ooo > build_tb_core_ooo.log 2>&1) \
    || { echo "BUILD FAIL obj_tb_core_ooo"; exit 1; }
fi

pass=0; total=0; failed=""
for h in hex/*.hex; do
  n=$(basename $h .hex); th=$(cat hex/$n.tohost); total=$((total+1))
  r=$(../obj_tb_core_ooo/tb_core_ooo +HEX=$h +TOHOST=$th 2>/dev/null | grep COMPLIANCE)
  case "$r" in *PASS*) pass=$((pass+1));; *) failed="$failed $n";; esac
done
echo "COMPLIANCE(OoO): $pass / $total"
[ -n "$failed" ] && echo "FAILED:$failed"
