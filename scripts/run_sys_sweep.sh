#!/bin/bash
# Sweep memory distance and bandwidth; report the decomposition, not one IPC.
cd "$(dirname "$0")/.."
HEX=${1:-asm/bench_memory.hex}
printf "%-6s %-5s %-9s %-8s %-6s %-7s %-6s %-6s %-9s\n" \
  DELAY BEAT cycles instret IPC imiss dmiss dwb memstall
for d in 0 2 5 10 20 40; do
  for b in 0 1; do
    o=$(timeout 300 ./obj_sys/tb_sys +DELAY=$d +BEAT_DELAY=$b +HEX=$HEX 2>/dev/null)
    c=$(echo "$o" | sed -n 's/.*cycles=\([0-9]*\).*/\1/p')
    i=$(echo "$o" | sed -n 's/.*instret=\([0-9]*\).*/\1/p')
    im=$(echo "$o" | sed -n 's/.*imiss=\([0-9]*\).*/\1/p')
    dm=$(echo "$o" | sed -n 's/.*dmiss=\([0-9]*\).*/\1/p')
    wb=$(echo "$o" | sed -n 's/.*dwb=\([0-9]*\).*/\1/p')
    ms=$(echo "$o" | sed -n 's/.*memstall=\([0-9]*\).*/\1/p')
    if [ -z "$c" ] || [ "$c" = "0" ]; then
      printf "%-6s %-5s %-9s %s\n" $d $b "-" "NO RESULT"; continue
    fi
    ipc=$(awk "BEGIN{printf \"%.3f\", $i/$c}")
    printf "%-6s %-5s %-9s %-8s %-6s %-7s %-6s %-6s %-9s\n" \
      $d $b $c $i $ipc $im $dm $wb $ms
  done
done
