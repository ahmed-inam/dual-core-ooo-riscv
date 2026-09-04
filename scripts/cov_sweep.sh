#!/usr/bin/env bash
# Run every program against ONE sim_uvm and merge the coverage.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

OBJ=obj_uvm
COV=$OBJ/cov
NM="${NM:-riscv64-unknown-elf-nm}"

if [[ ! -x $OBJ/sim_uvm ]]; then
  echo "cov_sweep.sh: no $OBJ/sim_uvm. Build first: ./scripts/run_uvm.sh cpu_smoke_test" >&2
  exit 1
fi

echo "=== sweeping against $OBJ/sim_uvm ($(date -r $OBJ/sim_uvm '+%Y-%m-%d %H:%M:%S')) ==="
newer=$(find tb rtl \( -name '*.sv' -o -name '*.svh' -o -name '*.vlt' \) \
          -newer $OBJ/sim_uvm 2>/dev/null | head -3)
if [[ -n "$newer" ]]; then
  echo "!! REFUSING: these sources are NEWER than sim_uvm, so it does not describe them:" >&2
  echo "$newer" >&2
  exit 1
fi

rm -rf "$COV"; mkdir -p "$COV"
rm -f coverage.dat

run () {  # run <test> <hexbase> [label]
  local test=$1 hb=$2 lbl=${3:-$2}
  local hex="asm/$hb.hex" elf="asm/$hb.elf"
  [[ -f "$hex" ]] || { echo "  -- $hb: no $hex, skipped"; return; }
  local args="+UVM_TESTNAME=$test +HEX=$hex +TOHOST=80001000"
  [[ -f "$elf" ]] && args="$args +ELF=$elf"
  local tpc; tpc=$($NM "$elf" 2>/dev/null | grep -w park_forever | awk '{print $1}')
  [[ -n "$tpc" ]] && args="$args +TRUNC_PC=$tpc"
  rm -f coverage.dat
  ./$OBJ/sim_uvm $args > "$COV/$lbl.log" 2> "$COV/$lbl.err"
  if [[ -f coverage.dat ]]; then
    cp coverage.dat "$COV/$lbl.dat"
    printf "  %-12s %s\n" "$lbl" "$(grep -oE '^ CHECKED +[0-9]+' $OBJ/verdict.txt 2>/dev/null | awk '{print $2" compared"}')"
  else
    echo "  $lbl: NO coverage.dat -- the run wrote none, which is a failure, not an empty result"
  fi
}

run cpu_base_test      mh
run cpu_saturate_test  saturate
run cpu_contend_test   contend
run cpu_stress_test    stress
run cpu_share_test     share
run cpu_memconv_test   memconv
run cpu_lrsc_trap_test lrsc_trap
run cpu_timer_irq_test irq_mh
run cpu_base_test      min_sl
run cpu_misalign_test  misalign
run cpu_csrprobe_test  csrprobe
run cpu_base_test      rasx
run cpu_base_test      mdcorner
run cpu_base_test      memshape
run cpu_irq_ctx_test   irq_ctx
run cpu_axierr_test    buserr    buserr_slverr
run cpu_base_test      excl
run cpu_atomic_prog_test hazx
run cpu_atomic_prog_test lrscx
run cpu_atomic_prog_test lrsc_qtrap
run cpu_atomic_prog_test lrsc_conflict
run cpu_atomic_prog_test lrsc_diffline
run cpu_base_test      nomem
run cpu_base_test      satviol
run cpu_base_test      fencefull
run cpu_wstall_test    memconv   memconv_wstall
for l in lb lrsc mp mpf s sb; do run cpu_litmus_test litmus_$l; done

echo
echo "=== merging $(ls $COV/*.dat 2>/dev/null | wc -l | tr -d ' ') file(s) ==="
verilator_coverage --write "$COV/merged.dat" $COV/*.dat >/dev/null 2>&1 \
  || { echo "merge FAILED" >&2; exit 1; }

rc=0
./scripts/cov_report.sh "$COV/merged.dat"
echo
./scripts/cov_bin_audit.sh "$COV/merged.dat" || rc=1
echo
./scripts/cov_proof_audit.sh "$COV/merged.dat" || rc=1
echo
./scripts/cite_audit.sh "$COV/merged.dat" || rc=1

./scripts/antivacuous_proof.sh || rc=1

./scripts/docs_audit.sh "$COV/merged.dat" || rc=1

echo
if [[ $rc == 0 ]]; then
  echo "COV_SWEEP: pass -- bins, proofs and citations all agree with the union"
else
  echo "COV_SWEEP: FAIL -- see which audit above reported it"
fi
exit $rc
