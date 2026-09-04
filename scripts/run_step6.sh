#!/usr/bin/env bash
# Reproduce the seven overlapped cluster gates at four memory latencies.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

OBJ=obj_uvm
NM="${NM:-riscv64-unknown-elf-nm}"
[[ -x $OBJ/sim_uvm ]] || { echo "run_step6.sh: no $OBJ/sim_uvm -- build first" >&2; exit 1; }

OUT=$OBJ/step6; rm -rf "$OUT"; mkdir -p "$OUT"
FAIL=0

CRITERIA=(
  "STRESS counter=128  SC-OK h0=64 h1=64"
  "SC-ON-UNOWNED-LINE h0=0 h1=0"
  "SWMR-VIOLATIONS cluster-wide: 0"
)
for c in "${CRITERIA[@]}"; do
  grep -qF "$c" scripts/run_regression.sh || {
    echo "!! CRITERION DRIFT: run_regression.sh no longer contains"
    echo "   \"$c\""
    echo "   This script would be checking something the battery does not."
    exit 1; }
done

[[ -x obj_tb_dual_ooo/tb_dual_ooo ]] || {
  echo "!! no obj_tb_dual_ooo/tb_dual_ooo -- the CLUSTER half cannot run."
  echo "   Inside the battery it is built before this gate; standalone, run"
  echo "   'make regression' once first. Refusing to report a UVM-only result"
  echo "   as if it were the cluster comparison."
  exit 1; }

ROWS=(
  "mh:cpu_base_test:200"
  "share:cpu_share_test:100"
  "contend:cpu_contend_test:20000"
  "stress:cpu_stress_test:3000"
  "litmus_lrsc:cpu_litmus_test:0"
)
LATS=("0 0" "10 1" "20 3" "40 7")

printf "%-14s %-10s %10s %8s %8s %8s   %s\n" \
       PROGRAM REGIME COMPARED MISMATCH UVM CLUSTER "AXI lat min/max"
printf "%s\n" "-------------------------------------------------------------------------------------------"

for row in "${ROWS[@]}"; do
  IFS=: read -r prog test floor <<< "$row"
  hex="asm/$prog.hex"; elf="asm/$prog.elf"
  [[ -f $hex ]] || { echo "  -- $prog: no $hex, skipped"; continue; }
  args="+UVM_TESTNAME=$test +HEX=$hex +TOHOST=80001000"
  [[ -f $elf ]] && args="$args +ELF=$elf"
  tpc=$($NM "$elf" 2>/dev/null | grep -w park_forever | awk '{print $1}')
  [[ -n $tpc ]] && args="$args +TRUNC_PC=$tpc"

  for lat in "${LATS[@]}"; do
    set -- $lat; d=$1; b=$2
    log="$OUT/${prog}_d${d}.log"

    rm -f $OBJ/verdict.txt
    timeout 900 ./$OBJ/sim_uvm $args +DELAY=$d +BEAT_DELAY=$b > "$log" 2>&1
    cmp=$(grep -oE "^ CHECKED +[0-9]+"    $OBJ/verdict.txt 2>/dev/null | awk '{print $2}')
    mis=$(grep -oE "^ mismatches +[0-9]+" $OBJ/verdict.txt 2>/dev/null | awk '{print $2}')
    lat_s=$(grep -oE "latency: min [0-9]+ cycles, max [0-9]+" "$log" | head -1 \
            | sed -E 's/latency: min ([0-9]+) cycles, max ([0-9]+)/\1\/\2/')
    uvm=OK
    [[ -f $OBJ/verdict.txt ]]  || uvm=NOVERDICT
    [[ -n $mis && $mis == 0 ]] || uvm=MISMATCH
    grep -q "UVM_FATAL :    0" "$log" || uvm=FATAL
    if [[ $floor -gt 0 ]]; then
      [[ -n $cmp && $cmp -ge $floor ]] 2>/dev/null || uvm=FLOOR
    else
      grep -q "tohost <= " "$log" || uvm=NOTERM
    fi

    cout=$(timeout 300 ./obj_tb_dual_ooo/tb_dual_ooo +HEX=$hex \
             +TOHOST=80001000 +DELAY=$d +BEAT_DELAY=$b 2>&1)
    clu=OK
    echo "$cout" | grep -q "SWMR-VIOLATIONS cluster-wide: 0" || clu=SWMR
    echo "$cout" | grep -q "DUAL TIMEOUT"                    && clu=TIMEOUT
    if [[ "$prog" == "stress" ]]; then
      echo "$cout" | grep -q "STRESS counter=128  SC-OK h0=64 h1=64" || clu=COUNTER
      echo "$cout" | grep -q "SC-ON-UNOWNED-LINE h0=0 h1=0"          || clu=UNOWNED
    fi

    [[ $uvm == OK && $clu == OK ]] || FAIL=$((FAIL+1))
    printf "%-14s %-10s %10s %8s %8s %8s   %s\n" \
           "$prog" "D=$d/B=$b" "${cmp:-n/a}" "${mis:-?}" "$uvm" "$clu" "${lat_s:-n/a}"
  done
done

echo
echo "=== FORBIDDEN litmus, judged by herd across its own latency sweep ==="
if ./scripts/run_litmus.sh lrsc mpf s > "$OUT/litmus.log" 2>&1; then
  echo "  litmus lrsc/mpf/s: ok"
else
  echo "  litmus lrsc/mpf/s: FAIL -- see $OUT/litmus.log"
  FAIL=$((FAIL+1))
fi

echo
echo "=== DID THE FOUR REGIMES ACTUALLY DIFFER? ==="
for lat in "${LATS[@]}"; do
  set -- $lat; d=$1
  vals=$(grep -ho "latency: min [0-9]* cycles, max [0-9]*" "$OUT"/*_d${d}.log 2>/dev/null \
         | sed -E 's/latency: min ([0-9]+) cycles, max ([0-9]+)/\1..\2/' | sort -u | tr '\n' ' ')
  printf "  DELAY=%-3s observed first-beat latency %s\n" "$d" "${vals:-none}"
done

echo
if [[ $FAIL -eq 0 ]]; then
  echo "STEP6: pass -- every overlap reproduces at all four latencies"
else
  echo "STEP6: FAIL -- $FAIL run(s) did not reproduce"
fi
exit $(( FAIL > 0 ))
