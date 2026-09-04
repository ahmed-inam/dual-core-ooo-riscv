#!/bin/bash
# Working-set sweep against the fixed 1 KB cache.
cd "$(dirname "$0")/.."
DELAY=${1:-10}
TOTAL=8192
printf "%-8s %-7s %-8s %-9s %-8s %-6s %-7s %-8s %s\n" \
  "WS" "ratio" "passes" "cycles" "instret" "IPC" "dmiss" "miss%" "checksum"
for w in 128 256 512 1024 2048 4096 8192; do
  kb=$((w*4/1024)); [ $kb -eq 0 ] && label="$((w*4))B" || label="${kb}KB"
  passes=$((TOTAL/w)); [ $passes -eq 0 ] && passes=1
  o=$(timeout 400 ./obj_ws/tb_sys +DELAY=$DELAY +HEX=asm/bench_ws.hex \
        +WS_WORDS=$w +WS_PASSES=$passes 2>/dev/null)
  c=$(echo "$o" | sed -n 's/.*cycles=\([0-9]*\).*/\1/p')
  i=$(echo "$o" | sed -n 's/.*instret=\([0-9]*\).*/\1/p')
  dm=$(echo "$o" | sed -n 's/.*dmiss=\([0-9]*\).*/\1/p')
  ck=$(echo "$o" | sed -n 's/.*checksum=\([0-9a-f]*\).*/\1/p')
  [ -z "$c" ] && { printf "%-8s NO RESULT\n" "$label"; continue; }
  ipc=$(awk "BEGIN{printf \"%.3f\", $i/$c}")
  rate=$(awk "BEGIN{printf \"%.1f%%\", 100*$dm/$TOTAL}")
  ratio=$(awk "BEGIN{printf \"1:%.0f\", ($w*4)/1024}")
  printf "%-8s %-7s %-8s %-9s %-8s %-6s %-7s %-8s %s\n" \
    "$label" "$ratio" "$passes" "$c" "$i" "$ipc" "$dm" "$rate" "$ck"
done
