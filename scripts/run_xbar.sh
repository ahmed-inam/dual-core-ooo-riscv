#!/usr/bin/env bash
# AXI4 crossbar gates: 21 directed tests plus two random configurations.
cd "$(dirname "$0")/.."
BIN=obj_tb_xbar/tb_xbar
[ -x "$BIN" ] || { echo "XBAR: build $BIN first (run_regression.sh builds it)"; exit 1; }
p=0; f=0; fl=""
for t in smoke cross cross_rd decerr t7 t9 t10 t11 t13 t14 t15 t16 t17 t20 t21 t22 \
         rd_handover rstwin committed example bursts; do
  v=$(timeout 150 "$BIN" +TEST=$t 2>&1 | grep -oE "FINAL VERDICT: (PASS|FAIL)|GLOBAL TIMEOUT" | tail -1)
  case "$v" in *PASS*) p=$((p+1));; *) f=$((f+1)); fl="$fl $t";; esac
done
for cfg in "2000 262144" "2000 1024"; do
  set -- $cfg
  out=$(timeout 280 "$BIN" +TEST=random +NTXN=$1 +PARTITION=0 +AWCNT=$2 2>&1)
  v=$(echo "$out" | grep -oE "FINAL VERDICT: (PASS|FAIL)" | tail -1)
  case "$v" in *PASS*) p=$((p+1));; *) f=$((f+1)); fl="$fl random_aw$2";; esac
done
echo "XBAR: pass=$p fail=$f$fl"
