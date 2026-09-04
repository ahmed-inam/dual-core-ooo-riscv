#!/bin/bash
# Sequential walk versus pointer chase at equal working set: isolates locality.
cd "$(dirname "$0")/.."
DELAY=${1:-10}
printf "%-6s | %-8s %-8s %-8s | %-8s %-8s %-8s | %s\n" \
  WS "seq IPC" "seq mis" "seq rate" "chase IPC" "chs mis" "chs rate" "penalty"
for kb in 1 2 4 8; do
  w=$((kb*256)); n=$((kb*64)); p=$((8192/w)); [ $p -eq 0 ] && p=1
  s=$(timeout 400 ./obj_ws/tb_sys +DELAY=$DELAY +HEX=asm/bench_ws.hex    +WS_WORDS=$w +WS_PASSES=$p    2>/dev/null)
  c=$(timeout 400 ./obj_ws/tb_sys +DELAY=$DELAY +HEX=asm/bench_chase.hex +WS_WORDS=$n +WS_PASSES=8192 2>/dev/null)
  sc=$(echo "$s" | sed -n 's/.*cycles=\([0-9]*\).*/\1/p'); si=$(echo "$s" | sed -n 's/.*instret=\([0-9]*\).*/\1/p'); sm=$(echo "$s" | sed -n 's/.*dmiss=\([0-9]*\).*/\1/p')
  cc=$(echo "$c" | sed -n 's/.*cycles=\([0-9]*\).*/\1/p'); ci=$(echo "$c" | sed -n 's/.*instret=\([0-9]*\).*/\1/p'); cm=$(echo "$c" | sed -n 's/.*dmiss=\([0-9]*\).*/\1/p')
  [ -z "$sc" ] || [ -z "$cc" ] && { printf "%-6s NO RESULT\n" "${kb}KB"; continue; }
  sipc=$(awk "BEGIN{printf \"%.3f\", $si/$sc}"); cipc=$(awk "BEGIN{printf \"%.3f\", $ci/$cc}")
  printf "%-6s | %-8s %-8s %-8s | %-8s %-8s %-8s | %s\n" "${kb}KB" \
    "$sipc" "$sm" "$(awk "BEGIN{printf \"%.0f%%\",100*$sm/8192}")" \
    "$cipc" "$cm" "$(awk "BEGIN{printf \"%.0f%%\",100*$cm/8192}")" \
    "$(awk "BEGIN{printf \"%.1fx\", $sipc/$cipc}")"
done
