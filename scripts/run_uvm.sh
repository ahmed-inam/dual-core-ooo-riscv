#!/usr/bin/env bash
# Build and run the cluster UVM environment.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TEST="${1:-cpu_smoke_test}"
shift || true

NO_DPI=0
EXTRA=()
for a in "$@"; do
  if [[ "$a" == "--no-dpi" ]]; then NO_DPI=1; else EXTRA+=("$a"); fi
done

UVM_SRC="${UVM_HOME:-/opt/uvm}/src"
SPIKE_SRC="${SPIKE_SRC:-/opt/refs/riscv-isa-sim}"
OBJ=obj_uvm
export JOBS="${UVM_JOBS:-1}"

./scripts/check_uvm_comments.sh || exit 1

rm -f $OBJ/run.log $OBJ/spike_commits.log $OBJ/verdict.txt

rm -f $OBJ/sim_uvm

RTL=$(sed -n 's/.*tb_dual_ooo) SRCS="\([^"]*\)".*/\1/p' scripts/run_regression.sh)
if [[ -z "$RTL" ]]; then
  echo "run_uvm.sh: could not extract the RTL list from run_regression.sh" >&2
  exit 1
fi

mkdir -p $OBJ

DPI_OBJ=""
DPI_LD=""
SPIKE_LIB="${SPIKE_LIB:-/opt/spike/lib}"
if [[ $NO_DPI -eq 0 ]]; then
  echo "=== compiling spike_dpi.cc ==="
  VROOT="${VERILATOR_ROOT:-$(verilator --getenv VERILATOR_ROOT 2>/dev/null)}"
  SVDPI_DIR=$(dirname "$(find "$VROOT" /usr/share/verilator /opt/verilator-5.050 -name svdpi.h 2>/dev/null | head -1)")
  rm -f $OBJ/spike_dpi.o
  g++ -std=c++2a -fPIC -c tb/uvm/ref/spike_dpi.cc -o $OBJ/spike_dpi.o \
      -include cstdint -include sys/syscall.h \
      -I"$SPIKE_SRC" -I"$SPIKE_SRC/riscv" -I"$SPIKE_SRC/fesvr" \
      -I"$SPIKE_SRC/softfloat" -I"$SPIKE_SRC/build" \
      -I"$SVDPI_DIR" 2>&1 | head -30
  if [[ ${PIPESTATUS[0]} -ne 0 || ! -f $OBJ/spike_dpi.o ]]; then
    echo
    echo "spike_dpi.cc did not compile. That is expected on a first attempt --"
    echo "see docs/verification.md. To get the DUT running meanwhile:"
    echo "    ./scripts/run_uvm.sh cpu_smoke_test --no-dpi"
    exit 1
  fi
  DPI_OBJ="$PWD/$OBJ/spike_dpi.o"
  DPI_LD="-LDFLAGS -lriscv -LDFLAGS -lfesvr -LDFLAGS -lsoftfloat -LDFLAGS -L$SPIKE_LIB"

  rm -f $OBJ/sim_uvm
else
  echo "=== --no-dpi: building WITHOUT the Spike reference model ==="
  echo "    Only cpu_smoke_test is meaningful; every other test needs a reference."
fi

mkdir -p $OBJ

INC="+incdir+tb/uvm/txn +incdir+tb/uvm/cfg +incdir+tb/uvm/rvfi +incdir+tb/uvm/ref"
INC="$INC +incdir+tb/uvm/sb +incdir+tb/uvm/mem +incdir+tb/uvm/snoop"
INC="$INC +incdir+tb/uvm/clint +incdir+tb/uvm/sys +incdir+tb/uvm/cov"
INC="$INC +incdir+tb/uvm/env +incdir+tb/uvm/seq +incdir+tb/uvm/test"
INC="$INC +incdir+tb/uvm/ral"

echo "=== elaborating (test: $TEST) ==="
uvmv --top-module tb_top -Mdir $OBJ -o sim_uvm \
     --coverage-user --coverage-line \
     tb/uvm/cov_scope.vlt \
     $INC \
     $RTL \
     tb/uvm/if/cpu_ifs.sv \
     tb/uvm/pkg/cpu_tb_pkg.sv \
     tb/uvm/top/tb_top.sv \
     $DPI_OBJ $DPI_LD \
     2>&1 | tee $OBJ/build.log | grep -E "%Error|%Warning-PINMISSING|Internal Error" | head -30

if [[ ! -x $OBJ/sim_uvm ]]; then
  echo
  echo "BUILD FAILED -- no sim_uvm was produced by THIS run."
  echo "(sim_uvm is deleted before every build, so this cannot be a stale one.)"
  echo
  echo "If build.log ends in 'Killed signal terminated program cc1plus', it is"
  echo "MEMORY, not code: rebuild with JOBS=1, which is the default here."
  echo
  echo "Otherwise suspect, in order:"
  echo "  1. the three hierarchical references into BOUND instances --"
  echo "     u_dut.u_snoop_vif, u_dut.g_hart[h].u_dc.u_cache_probe,"
  echo "     u_dut.g_hart[h].u_core.u_core_probe. Legal SystemVerilog; the 5.020"
  echo "     build crashes on all three. Fallback is in tb_top's comment."
  echo "  2. covergroup syntax. Gate B verified illegal_bins / cross / ignore_bins"
  echo "     / at_least / wildcard on 5.050, and that transition bins with ENUM"
  echo "     ITEM REFERENCES crash it. Every transition bin here already uses"
  echo "     integer literals -- do not 'fix' them back to enum names."
  echo "  full log: $OBJ/build.log"
  exit 1
fi

# 4. run
HEX="${HEX:-asm/mh.hex}"
TOHOST="${TOHOST:-80001000}"

ELF="${ELF:-asm/mh.elf}"
# The reference model needs the ELF, not the hex. htif_t::load_program() parses
# ELF headers; handed a Verilog hex file it reads garbage and SEGFAULTS with no
# message -- which presents as the simulation vanishing silently after the
# memory model loads.
SEED="${SEED:-$(cksum <<< "$TEST$HEX" | cut -d' ' -f1)}"
ARGS="+UVM_TESTNAME=$TEST +HEX=$HEX +TOHOST=$TOHOST +verilator+seed+$SEED"
[[ -f "$ELF" ]] && ARGS="$ARGS +ELF=$ELF"
echo "=== seed: $SEED (override with SEED=) ==="

# ---- the cut point -----------------------------------------------------------
# Both harts finish in crt0_multihart.S's `park_forever` loop (wfi ; j -4). The
NM="${NM:-riscv64-unknown-elf-nm}"
if [[ -f "$ELF" ]]; then
  TPC=$($NM "$ELF" 2>/dev/null | grep -w "park_forever" | awk '{print $1}')
  if [[ -n "$TPC" ]]; then
    ARGS="$ARGS +TRUNC_PC=$TPC"
  else
    echo "run_uvm.sh: WARNING -- no park_forever in $ELF; nothing will be truncated" >&2
  fi
fi

ARGS="$ARGS ${EXTRA[*]:-}"

echo "=== running: $ARGS ==="
./$OBJ/sim_uvm $ARGS 2> $OBJ/spike_commits.log | tee $OBJ/run.log

if grep -qE "%Error|%Fatal|Assertion failed|Segmentation fault" $OBJ/spike_commits.log; then
  echo
  echo "!!! stderr carried a real diagnostic, not just commit log:"
  grep -E "%Error|%Fatal|Assertion failed|Segmentation fault" $OBJ/spike_commits.log | head -10
fi

echo
echo "============================================================"
echo " READ THESE BEFORE CONCLUDING ANYTHING"
echo "============================================================"
grep -E "UVM_ERROR|UVM_FATAL|UVM_WARNING" $OBJ/run.log | head -20
echo "---"
echo " Several components report that a checker DID NOT RUN, which is not the"
echo " same as a checker that found nothing:"
grep -E "vacuous|never ran|never sampled|ZERO|NO interrupt|never read|only one master" \
     $OBJ/run.log | head -12
echo "============================================================"
