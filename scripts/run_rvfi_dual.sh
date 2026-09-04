#!/bin/bash
# Per-hart RVFI versus Spike on the dual-core cluster.
set -u
cd "$(dirname "$0")/.."
HEX=${1:-asm/mh.hex}
ELF=${2:-asm/mh.elf}
DELAY=${3:-10}
BEAT=${4:-1}
SPIKE=${SPIKE:-/opt/spike/bin/spike}
RISCV_DV=${RISCV_DV:-${RISCV_REFS:-/opt/refs}/riscv-dv}
ISA=${RVFI_ISA:-rv32im_zicsr}
MIN_MATCH=${MIN_MATCH:-30}   # hart0 measures 41; 30 leaves margin without being vacuous
NM=riscv64-unknown-elf-nm

BIN=obj_tb_dual_ooo/tb_dual_ooo
[ -x "$BIN" ] || { echo "RVFI-DUAL: build $BIN first (run_regression.sh)"; exit 1; }

BARRIER=$($NM "$ELF" 2>/dev/null | grep -w "_f3_barrier_begin" | awk '{print $1}')
PARK=$($NM "$ELF" 2>/dev/null | grep -w "park_forever"      | awk '{print $1}')
[ -n "$BARRIER" ] && [ -n "$PARK" ] || {
  echo "RVFI-DUAL: need _f3_barrier_begin and park_forever in $ELF"; exit 1; }

timeout 300 "$BIN" +HEX="$HEX" +TOHOST=80001000 \
  +DELAY="$DELAY" +BEAT_DELAY="$BEAT" > /tmp/dual_rvfi.log 2>&1
if ! grep -q "DUAL DONE PASS" /tmp/dual_rvfi.log; then
  echo "RVFI-DUAL: RTL run did not finish clean"
  grep -oE "DUAL TIMEOUT|DUAL DONE FAIL[^$]*" /tmp/dual_rvfi.log | head -1
  exit 1
fi

RC=0
SUMMARY=""
for h in 0 1; do
  awk -v hh="$h" -v b="$BARRIER" -v p="$PARK" '
    $1=="H" && $2==hh {
      pc = tolower($4)
      if (pc == tolower(b) || pc == tolower(p)) exit
      printf "V %s %s %s %s %s\n", $3, $4, $5, $6, $7
    }' /tmp/dual_rvfi.log > /tmp/rtl_h$h.txt
  python3 scripts/rvfi_to_csv.py /tmp/rtl_h$h.txt /tmp/rtl_h$h.csv > /dev/null

  rm -f /tmp/sp_h$h.log
  timeout 4 "$SPIKE" -p1 --hartids=$h --isa="$ISA" --log-commits -l \
    --log=/tmp/sp_h$h.log "$ELF" > /dev/null 2>&1
  awk -v b="0x$BARRIER" -v p="0x$PARK" '
    index($0, b) > 0 || index($0, p) > 0 { exit } { print }' \
    /tmp/sp_h$h.log > /tmp/sp_h${h}_cut.log
  python3 "$RISCV_DV/scripts/spike_log_to_trace_csv.py" \
    --log /tmp/sp_h${h}_cut.log --csv /tmp/sp_h$h.csv > /dev/null 2>&1
  rm -f /tmp/sp_h$h.log /tmp/sp_h${h}_cut.log   # hart0's is ~100 MB

  # ---- 4. compare ---------------------------------------------------------
  rm -f /tmp/dual_cmp_h$h.log
  ( cd "$RISCV_DV/scripts" && python3 - "$h" << 'EOF'
import sys
from instr_trace_compare import compare_trace_csv
h = sys.argv[1]
compare_trace_csv('/tmp/rtl_h%s.csv' % h, '/tmp/sp_h%s.csv' % h,
                  'rtl_h%s' % h, 'spike_h%s' % h, '/tmp/dual_cmp_h%s.log' % h)
EOF
  ) > /dev/null 2>&1

  V=$(grep -E "\[(PASSED|FAILED)\]" /tmp/dual_cmp_h$h.log | tail -1)
  N=$(echo "$V" | grep -oE "[0-9]+ matched" | grep -oE "[0-9]+")
  N=${N:-0}
  SUMMARY="$SUMMARY  hart$h: $V"
  echo "RVFI-DUAL hart$h :: $V"
  if ! echo "$V" | grep -q "\[PASSED\]"; then RC=1; fi
  # a pass on a near-empty trace is not a pass
  if [ "$N" -lt "$MIN_MATCH" ]; then
    echo "RVFI-DUAL hart$h :: ONLY $N matched (< $MIN_MATCH) -- treating as FAIL"
    RC=1
  fi
done

if [ "$RC" = "0" ]; then echo "RVFI-DUAL PASS"; else echo "RVFI-DUAL FAIL"; fi
exit $RC
