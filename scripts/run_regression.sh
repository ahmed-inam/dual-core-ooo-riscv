#!/bin/bash
# The full gate battery. EXPECT_GATES makes a vanished gate a failure, not a shift.
cd "$(dirname "$0")/.."
ROSTER=""
PASS=0; FAIL=0; FAILED=""

if [ -n "${UVM_ONLY:-}" ]; then
  echo "############################################################"
  echo "## UVM_ONLY -- PARTIAL RUN. The 42 unit testbenches, the"
  echo "## cluster gates and the tail sub-scripts DID NOT RUN."
  echo "## This is a PRE-FLIGHT, not a battery. It cannot report"
  echo "## pass=N fail=0 for the project, and EXPECT_GATES is not"
  echo "## applied. Run \`make regression\` before believing a total."
  echo "############################################################"
fi

OOO_SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/alu.sv \
rtl/common/branch_unit.sv rtl/common/mul_unit.sv rtl/common/div_unit.sv rtl/common/decoder.sv \
rtl/common/imm_gen.sv rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv \
rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv"

UNIT_SRCS="rtl/common/rv32i_pkg.sv rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/perf_counters.sv"
cp asm/*.hex . 2>/dev/null   # older TBs $readmemh from the run directory
if [ -z "${UVM_ONLY:-}" ]; then
for tbf in tb/*/tb_*.sv; do
  tb=$(basename "$tbf" .sv)
  VFLAGS=""
  RUNARGS=""
  case "$tb" in
    tb_ras|tb_btb|tb_gshare|tb_perf|tb_hpm0) SRCS="$UNIT_SRCS"; EXTRA="" ;;
    tb_sram) SRCS="rtl/mem/sram_1rw.sv"; EXTRA="" ;;
    tb_sram_1r1w) SRCS="rtl/mem/sram_1r1w.sv"; EXTRA="" ;;
    tb_mmio_decode) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv"; EXTRA="" ;;
    tb_clint) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/clint.sv"; EXTRA="" ;;
    tb_coherence_pkg) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv"; EXTRA="" ;;
    tb_mesi_ctrl) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv"; EXTRA="" ;;
    tb_coherence_mgr) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/coherence_mgr.sv"; EXTRA="" ;;
    tb_bridge) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coreaxi_pkg.sv rtl/mem/axi4/axi4_pkg.sv rtl/mem/axi4/axi4_if.sv tb/axi4/xbar_probe_if.sv tb/axi4/axi4_tb_pkg.sv rtl/mem/axi4/rst_sync.sv rtl/mem/axi4/skid_buffer.sv rtl/mem/axi4/rr_arbiter.sv rtl/mem/axi4/addr_decoder.sv rtl/mem/axi4/thread_tracker.sv rtl/mem/axi4/decerr_rd_resp.sv rtl/mem/axi4/decerr_wr_resp.sv rtl/mem/axi4/resp_return_mux.sv rtl/mem/axi4/rd_port_ctrl.sv rtl/mem/axi4/wr_port_ctrl.sv rtl/mem/axi4/slave_rd_port.sv rtl/mem/axi4/slave_wr_port.sv rtl/mem/axi4/axi4_xbar_top.sv tb/axi4/axi4_assert.sv rtl/mem/axi_adapter.sv rtl/mem/coreaxi_axi4_bridge.sv"; EXTRA=""
               VFLAGS="-Irtl/mem/axi4 -Itb/axi4" ;;
    tb_mesi_coh) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/coherence_mgr.sv"; EXTRA="" ;;
    tb_dcache_snoop) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/sram_1rw.sv rtl/mem/dcache.sv"; EXTRA="" ;;
    tb_dcache_upg_race) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/sram_1rw.sv rtl/mem/dcache.sv"; EXTRA="" ;;
    tb_dcache_flush_snoop) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/sram_1rw.sv rtl/mem/dcache.sv"; EXTRA="" ;;
    tb_dcache_swmr) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/sram_1rw.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv"; EXTRA="" ;;
    tb_axi4_word_slv) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/axi4/axi4_pkg.sv rtl/mem/axi4/axi4_if.sv rtl/mem/axi4_word_slv.sv"; EXTRA="" ;;
    tb_axi4_coreaxi_slv) SRCS="rtl/mem/axi4/axi4_pkg.sv rtl/mem/axi4/axi4_if.sv rtl/mem/coreaxi_pkg.sv rtl/mem/axi4_coreaxi_slv.sv"; EXTRA="" ;;
    tb_merge_dcoh) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/merge_dcoh.sv"; EXTRA="" ;;
    tb_dcache_acquire) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/sram_1rw.sv rtl/mem/dcache.sv"; EXTRA="" ;;
    tb_snp_store_race) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/sram_1rw.sv rtl/mem/dcache.sv"; EXTRA="" ;;
    tb_viol_merge) SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv"; EXTRA="" ;;
    tb_merges) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/merge_d_mmio.sv rtl/mem/merge_ifetch.sv"; EXTRA="" ;;
    tb_lrsc_path) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/common/lsu.sv rtl/ooo/lsq.sv rtl/mem/lrsc_unit.sv"; EXTRA="" ;;
    tb_lsq_snoop) SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/mem/mem_pkg.sv rtl/common/lsu.sv rtl/ooo/lsq.sv"; EXTRA="" ;;
    tb_decode_lrsc) SRCS="rtl/common/rv32i_pkg.sv rtl/common/decoder.sv rtl/common/imm_gen.sv"; EXTRA="" ;;
    tb_race_directed) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/coherence_mgr.sv"; EXTRA="" ;;
    tb_lrsc_unit) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coherence_pkg.sv rtl/mem/lrsc_unit.sv"; EXTRA="" ;;
    tb_dual_ooo) SRCS="rtl/common/rv32i_pkg.sv rtl/common/platform_cfg_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coreaxi_pkg.sv rtl/mem/axi4/axi4_pkg.sv rtl/mem/axi4/axi4_if.sv rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv rtl/mem/sram_1rw.sv rtl/mem/icache.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv rtl/mem/mem_arbiter.sv rtl/mem/axi_adapter.sv rtl/mem/sim_mem.sv rtl/mem/clint.sv rtl/mem/coherence_mgr.sv rtl/mem/lrsc_unit.sv rtl/mem/merge_d_mmio.sv rtl/mem/merge_ifetch.sv rtl/mem/merge_dcoh.sv rtl/mem/coreaxi_axi4_bridge.sv rtl/mem/axi4_coreaxi_slv.sv rtl/mem/axi4_word_slv.sv rtl/mem/axi4/addr_decoder.sv rtl/mem/axi4/rr_arbiter.sv rtl/mem/axi4/rst_sync.sv rtl/mem/axi4/skid_buffer.sv rtl/mem/axi4/thread_tracker.sv rtl/mem/axi4/decerr_rd_resp.sv rtl/mem/axi4/decerr_wr_resp.sv rtl/mem/axi4/rd_port_ctrl.sv rtl/mem/axi4/wr_port_ctrl.sv rtl/mem/axi4/resp_return_mux.sv rtl/mem/axi4/slave_rd_port.sv rtl/mem/axi4/slave_wr_port.sv rtl/mem/axi4/axi4_xbar_top.sv rtl/ooo/cluster.sv rtl/ooo/soc_top.sv"; EXTRA=""
                 RUNARGS="+HEX=asm/mh.hex +TOHOST=80001000 +DELAY=10 +BEAT_DELAY=1" ;;
    tb_sim_mem) SRCS="rtl/mem/coreaxi_pkg.sv rtl/mem/sim_mem.sv"; EXTRA="" ;;
    tb_icache) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/sram_1rw.sv rtl/mem/icache.sv"; EXTRA="tb/units/stub_linemem.sv" ;;
    tb_dcache) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/sram_1rw.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv"; EXTRA="tb/units/stub_linemem.sv" ;;
    tb_sys_ooo) continue ;;                          # run in the tail
    tb_freelist)   SRCS="rtl/ooo/core_cfg_pkg.sv rtl/ooo/freelist.sv"; EXTRA="" ;;
    tb_rename)     SRCS="rtl/ooo/core_cfg_pkg.sv rtl/ooo/rename.sv";   EXTRA="" ;;
    tb_fetch_queue) SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/fetch_queue.sv"; EXTRA="" ;;
    tb_prf)        SRCS="rtl/ooo/core_cfg_pkg.sv rtl/ooo/prf.sv";      EXTRA="" ;;
    tb_rob)        SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/ooo/rob.sv"; EXTRA="" ;;
    tb_issue_queue) SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/ooo/issue_queue.sv"; EXTRA="" ;;
    tb_lsq)        SRCS="rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/lsu.sv rtl/ooo/lsq.sv"; EXTRA="" ;;
    tb_core_ooo)   SRCS="$OOO_SRCS"; EXTRA="tb/ooo/core_wrap.sv"
                   RUNARGS="+HEX=asm/mext_smoke.hex +TOHOST=00001000" ;;
    tb_axi_path) SRCS="rtl/common/rv32i_pkg.sv rtl/mem/mem_pkg.sv rtl/mem/coreaxi_pkg.sv rtl/mem/sram_1rw.sv rtl/mem/icache.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv rtl/mem/mem_arbiter.sv rtl/mem/axi_adapter.sv rtl/mem/sim_mem.sv"; EXTRA="tb/axi4/axi4_assert.sv"; VFLAGS="--assert -DAXI_CHECK -DAXI4_ASSERT_NO_BIND -Itb/axi4" ;;
    tb_rvfi_ooo)  continue ;;                        # run via run_rvfi_compare_ooo.sh
    tb_rvfi_sys_ooo) continue ;;                    # run via run_rvfi_sys_ooo.sh tail gate
    tb_trace_o)   continue ;;                        # measurement harness for run_rob_sweep.sh, not a gate
    *)             echo "  [$tb] no SRCS mapping -- skipped"; continue ;;
  esac
  verilator --binary --timing $VFLAGS -Wno-fatal -Wno-EOFNEWLINE \
    -Mdir "obj_$tb" -o "$tb" \
    $SRCS $EXTRA "$tbf" --top-module "$tb" > "build_$tb.log" 2>&1
  if [ $? -ne 0 ]; then
    echo "BUILD FAIL: $tb"; FAIL=$((FAIL+1)); FAILED="$FAILED $tb"
    ROSTER="$ROSTER $tb:BUILDFAIL"; continue
  fi
  ./"obj_$tb"/"$tb" $RUNARGS > "run_$tb.log" 2>&1
  rc=$?
  # a testbench that crashed or printed nothing is not a pass
  if [ $rc -ne 0 ] || [ ! -s "run_$tb.log" ] \
     || grep -qE "FAIL|%Fatal|Assertion failed|%Error|BROKEN|\[BAD |[1-9][0-9]* error\(s\)" "run_$tb.log"; then
    echo "RUN FAIL: $tb"; FAIL=$((FAIL+1)); FAILED="$FAILED $tb"
    ROSTER="$ROSTER $tb:FAIL"
  else
    PASS=$((PASS+1)); ROSTER="$ROSTER $tb:ok"
  fi
done

if scripts/run_rvfi_compare_ooo.sh > run_ctest_ooo.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER ctest_rvfi_ooo:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED ctest_rvfi_ooo"; ROSTER="$ROSTER ctest_rvfi_ooo:FAIL"
fi
if [ ! -x obj_sys_ooo/tb_sys_ooo ]; then
  verilator --binary --timing --unroll-count 1024 -Wno-fatal -Wno-EOFNEWLINE \
    -Mdir obj_sys_ooo -o tb_sys_ooo rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv rtl/common/alu.sv rtl/common/branch_unit.sv rtl/common/mul_unit.sv rtl/common/div_unit.sv rtl/common/decoder.sv rtl/common/imm_gen.sv rtl/common/lsu.sv rtl/common/csr_regfile.sv rtl/common/perf_counters.sv rtl/common/ras.sv rtl/mem/sram_1r1w.sv rtl/common/btb.sv rtl/common/gshare.sv rtl/common/bp_top.sv rtl/common/fetch_queue.sv rtl/ooo/freelist.sv rtl/ooo/rename.sv rtl/ooo/prf.sv rtl/ooo/rob.sv rtl/ooo/issue_queue.sv rtl/ooo/lsq.sv rtl/ooo/core.sv rtl/mem/mem_pkg.sv rtl/mem/coreaxi_pkg.sv rtl/mem/sram_1rw.sv rtl/mem/icache.sv rtl/mem/coherence_pkg.sv rtl/mem/mesi_ctrl.sv rtl/mem/dcache.sv rtl/mem/mem_arbiter.sv rtl/mem/axi_adapter.sv rtl/mem/sim_mem.sv \
    tb/ooo/tb_sys_ooo.sv --top-module tb_sys_ooo > build_sys_ooo.log 2>&1 \
    || echo "BUILD FAIL obj_sys_ooo"
fi
if timeout 300 ./obj_sys_ooo/tb_sys_ooo +DELAY=10 +BEAT_DELAY=1 \
     +HEX=asm/bench_memory.hex 2>/dev/null | grep -q "checksum=5abda100"; then
  PASS=$((PASS+1)); ROSTER="$ROSTER sys_ooo:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED sys_ooo"; ROSTER="$ROSTER sys_ooo:FAIL"
fi

if scripts/run_ooo_irq_smc.sh > run_ooo_irq_smc.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER ooo_irq_smc:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED ooo_irq_smc"; ROSTER="$ROSTER ooo_irq_smc:FAIL"
fi

if verilator --lint-only --timing -Wno-EOFNEWLINE \
     rtl/common/rv32i_pkg.sv rtl/ooo/core_cfg_pkg.sv rtl/ooo/ooo_pkg.sv \
     rtl/ooo/core_cfg_check.sv \
     --top-module core_cfg_check > build_cfg_check.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER cfg_check:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED cfg_check"; ROSTER="$ROSTER cfg_check:FAIL"
fi


if scripts/run_ctest_suite.sh > run_ctest_suite.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER ctest_suite:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED ctest_suite"; ROSTER="$ROSTER ctest_suite:FAIL"
fi

riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -static -mcmodel=medany \
  -fvisibility=hidden -nostdlib -nostartfiles -O2 -T asm/link_rvfi.ld \
  asm/crt0_rvfi.S asm/ctest.c -o /tmp/ct_reg.elf -lgcc 2>/dev/null
riscv64-unknown-elf-objcopy -O binary /tmp/ct_reg.elf /tmp/ct_reg.bin 2>/dev/null
od -An -tx4 -w4 -v /tmp/ct_reg.bin | tr -d ' ' > /tmp/ct_reg.hex
if scripts/run_rvfi_sys_ooo.sh /tmp/ct_reg.hex /tmp/ct_reg.elf 10 1 > run_rvfi_sys_ooo.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER rvfi_sys_ooo:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED rvfi_sys_ooo"; ROSTER="$ROSTER rvfi_sys_ooo:FAIL"
fi

if RVFI_ISA=rv32ima_zicsr scripts/run_rvfi_sys_ooo.sh asm/lrsc_arch.hex asm/lrsc_arch.elf 10 1 > run_lrsc_arch.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER lrsc_arch:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED lrsc_arch"; ROSTER="$ROSTER lrsc_arch:FAIL"
fi

if scripts/run_litmus.sh mp sb lb mpf s lrsc > run_litmus.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER litmus:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED litmus"; ROSTER="$ROSTER litmus:FAIL"
fi

if [ ! -x obj_tb_xbar/tb_xbar ]; then
  R=rtl/mem/axi4; T=tb/axi4
  verilator --binary --timing -j 1 -Wno-fatal -Wno-EOFNEWLINE --top-module tb_top -I$R -I$T \
    $R/axi4_pkg.sv $R/axi4_if.sv $T/xbar_probe_if.sv $T/axi4_tb_pkg.sv $R/rst_sync.sv \
    $R/skid_buffer.sv $R/rr_arbiter.sv $R/addr_decoder.sv $R/thread_tracker.sv \
    $R/decerr_rd_resp.sv $R/decerr_wr_resp.sv $R/resp_return_mux.sv $R/rd_port_ctrl.sv \
    $R/wr_port_ctrl.sv $R/slave_rd_port.sv $R/slave_wr_port.sv $R/axi4_xbar_top.sv \
    $T/tb_top.sv --Mdir obj_tb_xbar -o tb_xbar > build_xbar.log 2>&1 \
    || echo "BUILD FAIL obj_tb_xbar"
fi
if scripts/run_xbar.sh 2>/dev/null | grep -q "pass=23 fail=0"; then
  PASS=$((PASS+1)); ROSTER="$ROSTER xbar:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED xbar"; ROSTER="$ROSTER xbar:FAIL"
fi

if scripts/run_mesi_xcells.sh 2>/dev/null | grep -q "pass=8 fail=0"; then
  PASS=$((PASS+1)); ROSTER="$ROSTER mesi_xcells:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED mesi_xcells"; ROSTER="$ROSTER mesi_xcells:FAIL"
fi

STRESS_OK=1
for lat in "0 0" "10 1" "20 3" "40 7"; do
  set -- $lat
  out=$(timeout 300 ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/stress.hex \
        +TOHOST=80001000 +DELAY=$1 +BEAT_DELAY=$2 2>&1)
  echo "$out" | grep -q "STRESS counter=128  SC-OK h0=64 h1=64" || STRESS_OK=0
  echo "$out" | grep -q "SC-ON-UNOWNED-LINE h0=0 h1=0"          || STRESS_OK=0
  echo "$out" | grep -q "SWMR-VIOLATIONS cluster-wide: 0"       || STRESS_OK=0
  echo "$out" | grep -q "DUAL TIMEOUT"                          && STRESS_OK=0
done
if [ "$STRESS_OK" = "1" ]; then
  PASS=$((PASS+1)); ROSTER="$ROSTER stress_lrsc:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED stress_lrsc"; ROSTER="$ROSTER stress_lrsc:FAIL"
fi

SWMR_OK=1
for prog in mh share contend litmus_lrsc; do
  timeout 250 ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/$prog.hex \
    +TOHOST=80001000 +DELAY=10 +BEAT_DELAY=1 2>&1 \
    | grep -q "SWMR-VIOLATIONS cluster-wide: 0" || SWMR_OK=0
done
if [ "$SWMR_OK" = "1" ]; then
  PASS=$((PASS+1)); ROSTER="$ROSTER swmr_cluster:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED swmr_cluster"; ROSTER="$ROSTER swmr_cluster:FAIL"
fi

if SPIKE="${SPIKE:-/opt/spike/bin/spike}" scripts/run_rvfi_dual.sh > run_rvfi_dual.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER rvfi_dual:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED rvfi_dual"; ROSTER="$ROSTER rvfi_dual:FAIL"
fi

BENCH_OK=1
for v in ser par; do
  timeout 300 ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/bench_par_$v.hex \
    +TOHOST=80001000 +DELAY=10 +BEAT_DELAY=1 2>&1 \
    | grep -q "testnum 1235124224" || BENCH_OK=0
done
if [ "$BENCH_OK" = "1" ]; then
  PASS=$((PASS+1)); ROSTER="$ROSTER bench_par:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED bench_par"; ROSTER="$ROSTER bench_par:FAIL"
fi

fi   # end of the non-UVM region skipped by UVM_ONLY

UVM_OK_BUILD=1
rm -rf obj_uvm/gatecov
if [ -n "${SKIP_BUILD:-}" ] && [ -x obj_uvm/sim_uvm ]; then
  newer=$(find tb rtl \( -name '*.sv' -o -name '*.svh' -o -name '*.vlt' \) \
            -newer obj_uvm/sim_uvm 2>/dev/null | head -3)
  if [ -n "$newer" ]; then
    echo "!! SKIP_BUILD refused: these sources are NEWER than obj_uvm/sim_uvm:"
    echo "$newer"
    echo "   Reusing it would test code that is not on disk. Building."
    ./scripts/run_uvm.sh cpu_smoke_test > obj_uvm/uvm_gate_build.log 2>&1
  else
    echo "   SKIP_BUILD: reusing obj_uvm/sim_uvm ($(date -r obj_uvm/sim_uvm '+%H:%M:%S')), sources are older"
  fi
else
  ./scripts/run_uvm.sh cpu_smoke_test > obj_uvm/uvm_gate_build.log 2>&1
fi
[ -x obj_uvm/sim_uvm ] || UVM_OK_BUILD=0

uvm_gate () {   # uvm_gate <gate-name> <test> <hexbase> <min-compared>
  local name=$1 test=$2 hb=$3 floor=$4
  local hex="asm/$hb.hex" elf="asm/$hb.elf"
  local args="+UVM_TESTNAME=$test +HEX=$hex +TOHOST=80001000"
  [ -f "$elf" ] && args="$args +ELF=$elf"
  local tpc
  tpc=$(${NM:-riscv64-unknown-elf-nm} "$elf" 2>/dev/null | grep -w park_forever | awk '{print $1}')
  [ -n "$tpc" ] && args="$args +TRUNC_PC=$tpc"

  if [ "$UVM_OK_BUILD" = "0" ]; then
    FAIL=$((FAIL+1)); FAILED="$FAILED $name"; ROSTER="$ROSTER $name:NOBUILD"
    return
  fi

  rm -f obj_uvm/verdict.txt coverage.dat
  timeout 900 ./obj_uvm/sim_uvm $args > obj_uvm/uvm_$name.log 2> obj_uvm/uvm_$name.err
  [ -f coverage.dat ] && { mkdir -p obj_uvm/gatecov; cp coverage.dat obj_uvm/gatecov/$name.dat; }

  local ok=1 mism cmp
  if [ ! -f obj_uvm/verdict.txt ]; then
    ok=0
  else
    mism=$(grep -oE "^ mismatches +[0-9]+" obj_uvm/verdict.txt | awk "{print \$2}")
    cmp=$(grep -oE "^ CHECKED +[0-9]+" obj_uvm/verdict.txt | awk "{print \$2}")
    [ -n "$mism" ] && [ "$mism" = "0" ] || ok=0
    [ -n "$cmp" ] && [ "$cmp" -ge "$floor" ] 2>/dev/null || ok=0
    grep -q "DID NOT TERMINATE" obj_uvm/verdict.txt && ok=0
  fi
  grep -q "UVM_FATAL :    0" obj_uvm/uvm_$name.log || ok=0

  if grep -qE "UVM_ERROR.*\[COV_LRSC\].*(ATOMICITY VIOLATION|reservation read VALID)"        obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_COH\].*ILLEGAL C1 cell" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_COH\].*C1 EQUIVALENCE" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*OUTSIDE THE LINKED IMAGE" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_RETIRE\].*deferrals exceeds the ceiling" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*COMMIT SLOT 1" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SYS_MON\]" obj_uvm/uvm_$name.log; then ok=0; fi

  if grep -qE "UVM_ERROR.*\[SB_COH\].*SWMR violated"                       obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_COH\].*WRITEBACK of line"                   obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_COH\].*(unknown snoop response|unknown request)" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_COH\].*DISAGREEMENT: ordering point"        obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SNOOP_MON\].*(granted while a transaction|overlapping grants)" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SNOOP_MON\].*no req_installed"                 obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RVFI_MON\].*(order not increasing|order GAP)"  obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RVFI_MON\].*rvfi_trap asserted"                obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[MEM_MON\].*(with nothing outstanding|orphan B)" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[MEM_MON\].*RLAST after"                        obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*byte mask"                          obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*contradict axi_adapter"             obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RAL\].*at reset, model says"      obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RAL\].*is declared RO with reset" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_CSR\]"                          obj_uvm/uvm_$name.log; then ok=0; fi

  if [ "$ok" = "1" ]; then
    PASS=$((PASS+1)); ROSTER="$ROSTER $name:ok"
  else
    FAIL=$((FAIL+1)); FAILED="$FAILED $name"; ROSTER="$ROSTER $name:FAIL"
  fi
}

uvm_gate uvm_base        cpu_base_test        mh          200
uvm_gate uvm_stress      cpu_stress_test      stress      3000
uvm_gate uvm_saturate    cpu_saturate_test    saturate    150000
uvm_gate uvm_contend     cpu_contend_test     contend     20000
uvm_gate uvm_share       cpu_share_test       share       100
uvm_gate uvm_memconv     cpu_memconv_test     memconv     150
uvm_gate uvm_lrsc_trap   cpu_lrsc_trap_test   lrsc_trap   50
uvm_gate uvm_timer_irq   cpu_timer_irq_test   irq_mh      400
uvm_gate uvm_min_sl      cpu_base_test        min_sl      4000

uvm_cov_gate () {   # uvm_cov_gate <gate-name> <test> <hexbase> <required-regex>
  local name=$1 test=$2 hb=$3 want=$4
  local hex="asm/$hb.hex" elf="asm/$hb.elf"
  local args="+UVM_TESTNAME=$test +HEX=$hex +TOHOST=80001000"
  [ -f "$elf" ] && args="$args +ELF=$elf"
  local tpc
  tpc=$(${NM:-riscv64-unknown-elf-nm} "$elf" 2>/dev/null | grep -w park_forever | awk '{print $1}')
  [ -n "$tpc" ] && args="$args +TRUNC_PC=$tpc"

  if [ "$UVM_OK_BUILD" = "0" ]; then
    FAIL=$((FAIL+1)); FAILED="$FAILED $name"; ROSTER="$ROSTER $name:NOBUILD"
    return
  fi

  rm -f obj_uvm/verdict.txt coverage.dat
  timeout 900 ./obj_uvm/sim_uvm $args > obj_uvm/uvm_$name.log 2> obj_uvm/uvm_$name.err
  [ -f coverage.dat ] && { mkdir -p obj_uvm/gatecov; cp coverage.dat obj_uvm/gatecov/$name.dat; }

  local ok=1
  [ -f obj_uvm/verdict.txt ] || ok=0
  grep -q "DID NOT TERMINATE" obj_uvm/verdict.txt 2>/dev/null && ok=0
  grep -q "UVM_FATAL :    0" obj_uvm/uvm_$name.log || ok=0
  grep -qE "$want" obj_uvm/uvm_$name.log || ok=0
  if grep -qE "UVM_ERROR.*\[SYS_MON\]" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_LRSC\].*(ATOMICITY VIOLATION|reservation read VALID)" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_COH\].*ILLEGAL C1 cell"  obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_COH\].*C1 EQUIVALENCE"   obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*COMMIT SLOT 1"    obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*OUTSIDE THE LINKED IMAGE" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_RETIRE\].*deferrals exceeds the ceiling" obj_uvm/uvm_$name.log; then ok=0; fi

  if grep -qE "UVM_ERROR.*\[SB_COH\].*SWMR violated"                       obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_COH\].*WRITEBACK of line"                   obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_COH\].*(unknown snoop response|unknown request)" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_COH\].*DISAGREEMENT: ordering point"        obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SNOOP_MON\].*(granted while a transaction|overlapping grants)" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SNOOP_MON\].*no req_installed"                 obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RVFI_MON\].*(order not increasing|order GAP)"  obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RVFI_MON\].*rvfi_trap asserted"                obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[MEM_MON\].*(with nothing outstanding|orphan B)" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[MEM_MON\].*RLAST after"                        obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*byte mask"                          obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[COV_ISA\].*contradict axi_adapter"             obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RAL\].*at reset, model says"      obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[RAL\].*is declared RO with reset" obj_uvm/uvm_$name.log; then ok=0; fi
  if grep -qE "UVM_ERROR.*\[SB_CSR\]"                          obj_uvm/uvm_$name.log; then ok=0; fi

  if [ "$ok" = "1" ]; then
    PASS=$((PASS+1)); ROSTER="$ROSTER $name:ok"
  else
    FAIL=$((FAIL+1)); FAILED="$FAILED $name"; ROSTER="$ROSTER $name:FAIL"
  fi
}

uvm_gate uvm_misalign    cpu_misalign_test    misalign    200

uvm_cov_gate uvm_csrprobe cpu_csrprobe_test   csrprobe    "86 CSR access\(es\)"
uvm_cov_gate uvm_ral       cpu_ral_test         csrprobe    "REGISTER MODEL: [1-9][0-9]* reset check"

uvm_gate uvm_rasx        cpu_base_test        rasx        150
uvm_gate uvm_mdcorner    cpu_base_test        mdcorner    150
uvm_gate uvm_memshape    cpu_base_test        memshape    150

uvm_cov_gate uvm_axierr  cpu_axierr_test      buserr      "[1-9][0-9]* trap cause\(s\) binned"

uvm_cov_gate uvm_irq_ctx cpu_irq_ctx_test     irq_ctx     "[1-9][0-9]* trap cause\(s\) binned"

uvm_gate uvm_excl        cpu_base_test         excl        15000
uvm_gate uvm_satviol     cpu_base_test         satviol     120000
uvm_gate uvm_hazx        cpu_atomic_prog_test  hazx        120
uvm_gate uvm_lrscx       cpu_atomic_prog_test  lrscx       400
uvm_gate uvm_lrsc_qtrap  cpu_atomic_prog_test  lrsc_qtrap  150
uvm_gate uvm_lrsc_conflict cpu_atomic_prog_test lrsc_conflict 20000
uvm_gate uvm_lrsc_diffline cpu_atomic_prog_test lrsc_diffline 150
uvm_gate uvm_fencefull   cpu_base_test         fencefull   50000
uvm_gate uvm_wstall      cpu_wstall_test       memconv     150

if [ "$UVM_OK_BUILD" = "0" ]; then
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_bins"; ROSTER="$ROSTER uvm_bins:NOBUILD"
elif [ ! -f coverage.dat ]; then
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_bins"; ROSTER="$ROSTER uvm_bins:NODAT"
else
  ./scripts/cov_bin_audit.sh coverage.dat > obj_uvm/uvm_bins.log 2>&1
  if grep -q "^    0 array-bin coverpoint(s) WRONG." obj_uvm/uvm_bins.log \
     && grep -q "^    0 cross(es) with a bin count" obj_uvm/uvm_bins.log; then
    PASS=$((PASS+1)); ROSTER="$ROSTER uvm_bins:ok"
  else
    FAIL=$((FAIL+1)); FAILED="$FAILED uvm_bins"; ROSTER="$ROSTER uvm_bins:FAIL"
  fi
fi

if ./scripts/check_asm_fresh.sh > obj_uvm/asm_fresh.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER asm_fresh:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED asm_fresh"; ROSTER="$ROSTER asm_fresh:FAIL"
fi

if [ "$UVM_OK_BUILD" = "0" ]; then
  FAIL=$((FAIL+1)); FAILED="$FAILED step6_latency"; ROSTER="$ROSTER step6_latency:NOBUILD"
elif ./scripts/run_step6.sh > obj_uvm/step6.log 2>&1; then
  PASS=$((PASS+1)); ROSTER="$ROSTER step6_latency:ok"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED step6_latency"; ROSTER="$ROSTER step6_latency:FAIL"
fi

if [ "$UVM_OK_BUILD" = "0" ]; then
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_proofs"; ROSTER="$ROSTER uvm_proofs:NOBUILD"
elif [ -z "$(ls obj_uvm/gatecov/*.dat 2>/dev/null)" ]; then
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_proofs"; ROSTER="$ROSTER uvm_proofs:NODAT"
else
  verilator_coverage --write obj_uvm/gatecov/union.dat obj_uvm/gatecov/*.dat \
      > obj_uvm/uvm_proofs.log 2>&1
  if ./scripts/cov_proof_audit.sh --hit-only obj_uvm/gatecov/union.dat \
       >> obj_uvm/uvm_proofs.log 2>&1; then
    PASS=$((PASS+1)); ROSTER="$ROSTER uvm_proofs:ok"
  else
    FAIL=$((FAIL+1)); FAILED="$FAILED uvm_proofs"; ROSTER="$ROSTER uvm_proofs:FAIL"
  fi
fi

./scripts/cite_audit.sh --anchors-only > obj_uvm/uvm_cites.log 2>&1; rc=$?
if [ "$rc" = "0" ]; then
  PASS=$((PASS+1)); ROSTER="$ROSTER uvm_cites:ok"
elif [ "$rc" = "2" ]; then
  ROSTER="$ROSTER uvm_cites:SKIP"
  echo "(uvm_cites: exit 2 -- audit unavailable, NOT a verdict. Not counted either way.)"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_cites"; ROSTER="$ROSTER uvm_cites:FAIL"
fi

./scripts/checker_audit.sh > obj_uvm/uvm_checkers.log 2>&1; rc=$?
if [ "$rc" = "0" ]; then
  PASS=$((PASS+1)); ROSTER="$ROSTER uvm_checkers:ok"
elif [ "$rc" = "2" ]; then
  ROSTER="$ROSTER uvm_checkers:SKIP"
  echo "(uvm_checkers: exit 2 -- audit unavailable, NOT a verdict. Not counted either way.)"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_checkers"; ROSTER="$ROSTER uvm_checkers:FAIL"
fi

./scripts/docs_audit.sh --no-coverage > obj_uvm/uvm_docs.log 2>&1; rc=$?
if [ "$rc" = "0" ]; then
  PASS=$((PASS+1)); ROSTER="$ROSTER uvm_docs:ok"
elif [ "$rc" = "2" ]; then
  ROSTER="$ROSTER uvm_docs:SKIP"
  echo "(uvm_docs: exit 2 -- audit unavailable, NOT a verdict. Not counted either way.)"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_docs"; ROSTER="$ROSTER uvm_docs:FAIL"
fi

./scripts/gate_criteria_check.sh          > obj_uvm/uvm_criteria.log 2>&1; rc=$?
./scripts/gate_criteria_check.sh --coverage >> obj_uvm/uvm_criteria.log 2>&1; rc2=$?
if [ "$rc" = "0" ] && [ "$rc2" = "0" ]; then
  PASS=$((PASS+1)); ROSTER="$ROSTER uvm_criteria:ok"
elif [ "$rc2" = "2" ]; then
  ROSTER="$ROSTER uvm_criteria:SKIP"
  echo "(uvm_criteria: exit 2 -- audit unavailable on a mutated tree, NOT a verdict.)"
else
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_criteria"; ROSTER="$ROSTER uvm_criteria:FAIL"
fi

if [ -x obj_uvm/sim_uvm ]; then
  GEN_ARGS="--shared-rate 0.35" SEED0=90001 LEN=300 \
    ./scripts/run_random.sh 2 > obj_uvm/uvm_random.log 2>&1
  if grep -q "^RANDOM: built=2 pass=2 fail=0" obj_uvm/uvm_random.log; then
    PASS=$((PASS+1)); ROSTER="$ROSTER uvm_random:ok"
  else
    FAIL=$((FAIL+1)); FAILED="$FAILED uvm_random"; ROSTER="$ROSTER uvm_random:FAIL"
  fi
else
  FAIL=$((FAIL+1)); FAILED="$FAILED uvm_random"; ROSTER="$ROSTER uvm_random:NOBUILD"
fi

echo "ROSTER($(echo $ROSTER | wc -w)):"
for g in $ROSTER; do echo "  $g"; done | sort

if [ -n "${UVM_ONLY:-}" ]; then
  echo "(UVM_ONLY: roster diff and EXPECT_GATES skipped -- this run is partial by design)"
elif [ -f docs/gate_roster.txt ]; then
  for g in $ROSTER; do echo "${g%%:*}"; done | sort -u > obj_uvm/roster_now.txt
  grep '^  ' docs/gate_roster.txt | sed 's/^  //; s/:.*//' | sort -u > obj_uvm/roster_doc.txt
  if ! diff -q obj_uvm/roster_now.txt obj_uvm/roster_doc.txt >/dev/null; then
    echo "GATE ROSTER DRIFT -- docs/gate_roster.txt does not list the gates that ran:"
    diff obj_uvm/roster_doc.txt obj_uvm/roster_now.txt | sed 's/^/  /'
    echo "  Adding a gate needs run_regression.sh, EXPECT_GATES and this file in ONE patch."
    FAIL=$((FAIL+1)); FAILED="$FAILED gate_roster_drift"
  fi
fi
if [ -n "${EXPECT_GATES:-}" ] && [ -z "${UVM_ONLY:-}" ]; then
  N=$(echo $ROSTER | wc -w)
  if [ "$N" -ne "$EXPECT_GATES" ]; then
    echo "ROSTER SIZE CHANGED: $N gates, expected $EXPECT_GATES -- a gate was ADDED or VANISHED"
    FAIL=$((FAIL+1)); FAILED="$FAILED roster_size"
  fi
fi
if [ -n "${UVM_ONLY:-}" ]; then
  echo "UVM_PREFLIGHT: pass=$PASS fail=$FAIL$FAILED   (PARTIAL -- not a battery result)"
else
  echo "REGRESSION: pass=$PASS fail=$FAIL$FAILED"
fi
