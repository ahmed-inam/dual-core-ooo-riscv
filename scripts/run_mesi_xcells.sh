#!/usr/bin/env bash
# The eight illegal C1 cells each $fatal, so each needs its own run.
cd "$(dirname "$0")/.."
BIN=obj_tb_mesi_ctrl/tb_mesi_ctrl
[ -x "$BIN" ] || { echo "MESI-XCELLS: build $BIN first (run_regression.sh)"; exit 1; }
p=0; f=0
for n in 0 1 2 3 4 5 6 7; do
  if timeout 60 "$BIN" +XCELL=$n 2>&1 | grep -q "X-CELL REACHED"; then p=$((p+1));
  else f=$((f+1)); echo "  x-cell $n NOT DETECTED"; fi
done
echo "MESI-XCELLS: pass=$p fail=$f"
