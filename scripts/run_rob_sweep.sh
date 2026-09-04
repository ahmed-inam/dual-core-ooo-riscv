#!/bin/bash
# Sweep ROB_N with PRF and IQ co-scaled so the ROB stays the binding constraint.
set -u
cd "$(dirname "$0")/.."

SIZES="${1:-8 16 32 64}"
echo "ROB sweep skeleton: sizes = $SIZES"
echo "(measurement body lands at Gate A step 4f)"

for n in $SIZES; do
  prf=$(( 32 + n ))
  p2=1; while [ $p2 -lt $prf ]; do p2=$(( p2 * 2 )); done; prf=$p2
  iq=16; [ $iq -gt $n ] && iq=$n
  sed -e "s/ROB_N  = 32/ROB_N  = $n/" \
      -e "s/PRF_N  = 64/PRF_N  = $prf/" \
      -e "s/IQ_N   = 16/IQ_N   = $iq/" \
      rtl/ooo/core_cfg_pkg.sv > /tmp/cfg_rob_$n.sv
  if ! verilator --lint-only --timing -Wno-EOFNEWLINE \
       /tmp/cfg_rob_$n.sv rtl/ooo/core_cfg_check.sv \
       --top-module core_cfg_check > /tmp/cfg_rob_$n.log 2>&1; then
    echo "ROB_N=$n : REJECTED by core_cfg_check (see /tmp/cfg_rob_$n.log)"
    continue
  fi
  echo "ROB_N=$n PRF_N=$prf IQ_N=$iq : config valid"
  rm -rf /tmp/obj_sweep_$n
  verilator --binary --timing -Wno-fatal -Wno-EOFNEWLINE --unroll-count 1024 \
    -Mdir /tmp/obj_sweep_$n -o t \
    rtl/common/rv32i_pkg.sv /tmp/cfg_rob_$n.sv rtl/ooo/ooo_pkg.sv \
    rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv \
    rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv \
    rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv \
    rtl/common/ras.sv rtl/common/btb.sv rtl/common/gshare.sv \
    rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv \
    rtl/ooo/rename.sv rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv \
    rtl/ooo/lsq.sv rtl/ooo/core.sv rtl/mem/mem_pkg.sv rtl/mem/coreaxi_pkg.sv \
    rtl/mem/sram_1rw.sv rtl/mem/sram_1r1w.sv rtl/mem/icache.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv \
    rtl/mem/mem_arbiter.sv rtl/mem/axi_adapter.sv rtl/mem/sim_mem.sv \
    tb/ooo/tb_sys_ooo.sv --top-module tb_sys_ooo \
    > /tmp/sweep_build_$n.log 2>&1 \
    || { echo "ROB_N=$n : BUILD FAILED (see /tmp/sweep_build_$n.log)"; continue; }
  line=$(timeout 300 /tmp/obj_sweep_$n/t +HEX=asm/bench_chase.hex \
         +TOHOST=00001000 +WS_WORDS=256 +WS_PASSES=8192 2>/dev/null | grep "SYS DELAY")
  echo "ROB_N=$n bench_chase  : $line"
  line=$(timeout 160 /tmp/obj_sweep_$n/t +HEX=asm/bench_memory.hex \
         +TOHOST=00001000 2>/dev/null | grep "SYS DELAY")
  echo "ROB_N=$n bench_memory : $line"
  find /tmp/obj_sweep_$n -name "*.o" -delete; find /tmp/obj_sweep_$n -name "*.a" -delete
  rm -rf /tmp/obj_sweepp_$n
  verilator --binary --timing -Wno-fatal -Wno-EOFNEWLINE --unroll-count 1024 \
    -Mdir /tmp/obj_sweepp_$n -o t \
    rtl/common/rv32i_pkg.sv /tmp/cfg_rob_$n.sv rtl/ooo/ooo_pkg.sv \
    rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv \
    rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv \
    rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv \
    rtl/common/ras.sv rtl/common/btb.sv rtl/common/gshare.sv \
    rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv \
    rtl/ooo/rename.sv rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv \
    rtl/ooo/lsq.sv rtl/ooo/core.sv tb/ooo/core_wrap.sv tb/ooo/tb_trace_o.sv \
    --top-module tb_trace_o > /tmp/sweepp_build_$n.log 2>&1 \
    || { echo "ROB_N=$n : PLAIN BUILD FAILED"; continue; }
  h=$(timeout 120 /tmp/obj_sweepp_$n/t +HEX=asm/bench_branchy.hex \
      +TOHOST=00001000 2>/dev/null | grep "^V " | awk '$4=="b0002a73" {print $6; exit}')
  [ -n "$h" ] && printf "ROB_N=%s bench_branchy: cycles=%d\n" $n $((0x$h)) \
              || echo "ROB_N=$n bench_branchy: (no readout)"
  find /tmp/obj_sweepp_$n -name "*.o" -delete; find /tmp/obj_sweepp_$n -name "*.a" -delete
done
