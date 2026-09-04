#!/usr/bin/env bash
# Constrained-random programs against Spike; the coverage-closure loop.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

N=${1:-8}
SEED0=${SEED0:-1000}
LEN=${LEN:-400}
GEN_ARGS=${GEN_ARGS:-}
OUT=asm/rand
mkdir -p $OUT obj_uvm/rand

if [[ ! -x obj_uvm/sim_uvm ]]; then
  echo "!! no obj_uvm/sim_uvm. Build first:"
  echo "   HEX=asm/mh.hex ELF=asm/mh.elf ./scripts/run_uvm.sh cpu_base_test"
  exit 1
fi

./scripts/check_uvm_comments.sh >/dev/null 2>&1 || {
  echo "!! check_uvm_comments.sh failed -- a .S comment starting with a cpp"
  echo "   keyword is a directive. Fix before generating."; exit 1; }

pass=0; fail=0; built=0; FAILED_SEEDS=""
echo "=== $N seed(s) from $SEED0, length $LEN ${GEN_ARGS:+, constraints: $GEN_ARGS} ==="

for ((i=0; i<N; i++)); do
  s=$((SEED0 + i))
  S=$OUT/rand_$s.S; E=$OUT/rand_$s.elf; H=$OUT/rand_$s.hex

  python3 scripts/gen_random_prog.py --seed "$s" --length "$LEN" --out "$S" $GEN_ARGS >/dev/null || {
    echo "  seed $s: GENERATOR FAILED"; fail=$((fail+1)); continue; }

  riscv64-unknown-elf-gcc -march=rv32ima_zicsr -mabi=ilp32 -static \
    -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -O2 \
    -T asm/link_rvfi.ld asm/crt0_multihart.S "$S" -o "$E" -lgcc 2>/dev/null
  if [[ ! -f $E || ! $E -nt $S ]]; then
    echo "  seed $s: ASSEMBLE FAILED"; fail=$((fail+1)); continue
  fi
  riscv64-unknown-elf-objcopy -O binary "$E" /tmp/rand_$s.bin
  od -An -tx4 -w4 -v /tmp/rand_$s.bin | tr -d ' ' > "$H"
  built=$((built+1))

  tpc=$(riscv64-unknown-elf-nm "$E" | grep -w park_forever | awk '{print $1}')
  rm -f obj_uvm/verdict.txt
  timeout 900 ./obj_uvm/sim_uvm +UVM_TESTNAME=cpu_base_test \
      +HEX="$H" +ELF="$E" +TOHOST=80001000 ${tpc:+ +TRUNC_PC=$tpc} \
      > obj_uvm/rand/rand_$s.log 2>&1

  if [[ ! -f obj_uvm/verdict.txt ]]; then
    echo "  seed $s: NO VERDICT (timeout or crash)  <-- INVESTIGATE"
    fail=$((fail+1)); FAILED_SEEDS="$FAILED_SEEDS $s"; continue
  fi
  mis=$(grep -oE "^ mismatches +[0-9]+" obj_uvm/verdict.txt | awk '{print $2}')
  cmp=$(grep -oE "^ CHECKED +[0-9]+"    obj_uvm/verdict.txt | awk '{print $2}')
  if [[ "${mis:-x}" == "0" ]]; then
    printf "  seed %-6s ok      compared=%-7s mismatches=0\n" "$s" "${cmp:-?}"
    pass=$((pass+1))
  else
    printf "  seed %-6s FAIL    compared=%-7s mismatches=%s   <-- A FINDING\n" \
           "$s" "${cmp:-?}" "${mis:-?}"
    fail=$((fail+1)); FAILED_SEEDS="$FAILED_SEEDS $s"
  fi
  [[ -f coverage.dat ]] && mv coverage.dat obj_uvm/rand/cov_rand_$s.dat
done

echo
echo "RANDOM: built=$built pass=$pass fail=$fail"
[[ -n ${FAILED_SEEDS// /} ]] && {
  echo "SEEDS TO REPRODUCE:$FAILED_SEEDS"
  echo "  each asm/rand/rand_<seed>.S carries its exact generator command line."
}
echo
echo "Coverage files: obj_uvm/rand/cov_rand_*.dat"
echo "  Merge them with the BATTERY's files to see the union move. NEVER merge"
echo "  across builds -- the record key embeds the source line, so a covergroup"
echo "  that moved merges as TWO bins and the union reads LARGER, which looks"
echo "  like progress. One binary, all seeds."
exit 0
