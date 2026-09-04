#!/bin/bash
# Sweep an interrupt across every cycle of a program with every stall flavour.
cd "$(dirname "$0")/.."
FIRST=${1:-2}; LAST=${2:-60}
PASS=0; FAIL=0; FAILED=""
for at in $(seq $FIRST $LAST); do
  r=$(./obj_irq_stall/tb_irq_stall +IRQ_AT=$at 2>/dev/null | grep IRQSTALL)
  case "$r" in
    *PASS*) PASS=$((PASS+1));;
    *) FAIL=$((FAIL+1)); FAILED="$FAILED $at"; echo "$r";;
  esac
done
r=$(./obj_irq_stall/tb_irq_stall +IRQ_AT=9999 2>/dev/null | grep IRQSTALL)
case "$r" in *PASS*) PASS=$((PASS+1));; *) FAIL=$((FAIL+1)); FAILED="$FAILED ctrl";; esac
echo "IRQ SWEEP: pass=$PASS fail=$FAIL$FAILED"
