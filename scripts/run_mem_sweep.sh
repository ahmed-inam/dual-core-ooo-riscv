#!/bin/bash
# Sweep memory latency and bandwidth; check fill cost against the closed form.
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
printf "%-7s %-11s %-6s %s\n" "DELAY" "BEAT_DELAY" "fill" "result"
for d in 0 1 5 10 20 50; do
  for b in 0 1 2; do
    out=$(./obj_tb_sim_mem/tb_sim_mem +DELAY=$d +BEAT_DELAY=$b 2>/dev/null | grep SIMMEM)
    fill=$(echo "$out" | sed -n 's/.*fill=\([0-9]*\).*/\1/p')
    case "$out" in
      *PASS*) printf "%-7s %-11s %-6s ok\n" $d $b "$fill"; PASS=$((PASS+1));;
      *)      printf "%-7s %-11s %-6s FAIL\n" $d $b "$fill"; FAIL=$((FAIL+1));;
    esac
  done
done
echo "MEM SWEEP: pass=$PASS fail=$FAIL"
