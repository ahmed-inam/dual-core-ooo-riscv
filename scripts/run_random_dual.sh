#!/usr/bin/env bash
# Random dual-hart stress gate: generate, build and run self-checking two-hart
# programs on the cluster testbench across the memory-latency sweep.
#   BIN=obj_tb_dual_ooo/tb_dual_ooo SEEDS="1 2 3" NOPS=250 REPS=4 scripts/run_random_dual.sh
# Each body of NOPS random ops is repeated REPS times from a known state.
# Odd seeds run under a timer-interrupt storm on both harts. A run passes only
# when hart 0 reports DUAL DONE PASS, the SWMR monitor saw no violation, and
# nothing fatal or timed out.
cd "$(dirname "$0")/.."
BIN=${BIN:-obj_tb_dual_ooo/tb_dual_ooo}
SEEDS=${SEEDS:-1 2 3 4 5 6 7 8}
NOPS=${NOPS:-250}
REPS=${REPS:-4}
LATS=${LATS:-"0 0|10 1|20 3|40 7"}
W=obj_random_dual
mkdir -p $W
[ -x "$BIN" ] || { echo "RANDOM_DUAL: build $BIN first (run_regression.sh builds it)"; exit 1; }
p=0; f=0; fl=""
for s in $SEEDS; do
  irq=""; [ $((s % 2)) -eq 1 ] && irq="--irq"
  python3 scripts/gen_random_dual.py --seed $s --nops $NOPS --reps $REPS $irq -o $W/rd_$s.S || { f=$((f+1)); fl="$fl gen$s"; continue; }
  riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -static -mcmodel=medany \
    -nostdlib -nostartfiles -T asm/link.ld asm/crt0_multihart.S $W/rd_$s.S -o $W/rd_$s.elf \
    > $W/build_$s.log 2>&1 || { f=$((f+1)); fl="$fl build$s"; continue; }
  riscv64-unknown-elf-objcopy -O binary $W/rd_$s.elf $W/rd_$s.bin
  python3 - $W/rd_$s.bin $W/rd_$s.hex <<'PY'
import sys, struct
b = open(sys.argv[1], 'rb').read(); b += b'\0' * ((-len(b)) % 4)
with open(sys.argv[2], 'w') as f:
    for i in range(0, len(b), 4): f.write('%08x\n' % struct.unpack('<I', b[i:i+4])[0])
PY
  IFS='|' read -ra LL <<< "$LATS"
  for lat in "${LL[@]}"; do
    set -- $lat
    out=$("$BIN" +HEX=$W/rd_$s.hex +TOHOST=80001000 +DELAY=$1 +BEAT_DELAY=$2 2>&1)
    echo "$out" > $W/run_${s}_$1_$2.log
    if echo "$out" | grep -q "DUAL DONE PASS" && echo "$out" | grep -q "SWMR-VIOLATIONS cluster-wide: 0" \
       && ! echo "$out" | grep -qE "Fatal|DUAL TIMEOUT|DUAL FAIL"; then
      p=$((p+1))
    else
      f=$((f+1)); fl="$fl seed$s@$1/$2"
      echo "  seed $s DELAY=$1 BEAT=$2: $(echo "$out" | grep -E 'DUAL DONE|DUAL TIMEOUT|DUAL FAIL|Fatal' | head -1)"
    fi
  done
done
echo "RANDOM_DUAL: pass=$p fail=$f$( [ -n "$fl" ] && echo " failed:$fl")"
[ $f -eq 0 ]
