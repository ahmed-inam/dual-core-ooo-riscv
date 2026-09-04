#!/usr/bin/env bash
# Litmus sweep, checked against herd's allowed-outcome sets.
set -u
cd "$(dirname "$0")/.."

BIN=obj_tb_dual_ooo/tb_dual_ooo
HERD="${HERD:-${RISCV_REFS:-/opt/refs}/litmus-tests-riscv/model-results/herd.logs}"
TESTS="${*:-mp sb lb}"

[ -x "$BIN" ] || { echo "LITMUS: build $BIN first (run_regression.sh)"; exit 1; }
[ -f "$HERD" ] || { echo "LITMUS: oracle $HERD missing -- clone litmus-tests-riscv"; exit 1; }

if [ "${LITMUS_FULL:-0}" = "1" ]; then
  SWEEP="0:0 1:0 2:0 4:1 10:1 16:2 20:3 32:5 40:7"
  SKEWS="0:0 0:3 0:8 3:0 8:0 1:1 0:17 17:0"
else
  SWEEP="0:0 2:0 10:1 20:3"
  SKEWS="0:0 5:0 0:5 0:17 17:0"
fi

pass=0; fail=0; failed=""

for t in $TESTS; do
  HEX=asm/litmus_$t.hex
  [ -f "$HEX" ] || { echo "  [$t] missing $HEX -- skipped"; continue; }

  OBS=""
  for cfg in $SWEEP; do
   d=${cfg%%:*}; b=${cfg##*:}
   for sk in $SKEWS; do
    s0=${sk%%:*}; s1=${sk##*:}
    out=$(timeout 280 ./$BIN +HEX=$HEX +TOHOST=80001000 +DELAY=$d +BEAT_DELAY=$b \
           +SKEW0=$s0 +SKEW1=$s1 2>&1)
    line=$(echo "$out" | grep -oE "LITMUS obs h0=[0-9]+ h1=[0-9]+" | tail -1)
    memln=$(echo "$out" | grep -oE "LITMUS mem x@0x3100=[0-9]+ y@0x3140=[0-9]+" | tail -1)
    mx=$(echo "$memln" | sed -E 's/.*x@0x3100=([0-9]+).*/\1/')
    my=$(echo "$memln" | sed -E 's/.*y@0x3140=([0-9]+).*/\1/')
    if [ -z "$line" ]; then
      echo "  [$t] DELAY=$d BEAT=$b SKEW=$s0/$s1 -- NO OUTCOME (hang/crash) *** HARD FAIL ***"
      fail=$((fail+1)); failed="$failed $t"; continue
    fi
    h0=$(echo "$line" | sed -E 's/.*h0=([0-9]+).*/\1/')
    h1=$(echo "$line" | sed -E 's/.*h1=([0-9]+).*/\1/')
    OBS="$OBS $h0,$h1,${mx:-0},${my:-0}"
   done
  done

  case "$t" in
    mp)  TESTNAME="MP" ;;
    sb)  TESTNAME="SB" ;;
    lb)  TESTNAME="LB" ;;
    mpf)  TESTNAME="MP+fence.w.w+fence.tso" ;;
    s)    TESTNAME="S+fence.w.w+fence.tso" ;;
    lrsc) TESTNAME="LR-SC-diff-loc3" ;;
    *)   TESTNAME=$(echo "$t" | tr 'a-z' 'A-Z') ;;
  esac
  RESULT=$(HERD="$HERD" TESTNAME="$TESTNAME" OBS="$OBS" python3 - <<'PY'
import os, re, sys

herd  = os.environ["HERD"]
name  = os.environ["TESTNAME"]
obs   = os.environ["OBS"].split()

# ---- parse the allowed set out of herd.logs -----------------------------
allowed, grab = [], False
for ln in open(herd):
    ln = ln.rstrip("\n")
    if ln.startswith("Test %s " % name):
        grab = True; continue
    if grab:
        if ln.startswith("States"):      continue
        if ln.startswith(("Ok","No","Witnesses","Condition","Observation","Time","Hash")):
            break
        # registers: `0:x5=1`   AND bare memory locations: `x=2`
        # The memory form matters for conditions like S+fence.w.w+fence.tso's
        # `~exists (x=2 /\\ 1:x5=1)`, which constrains the FINAL VALUE OF x.
        # A register-only parser silently drops that term and the forbidden
        # state becomes inexpressible -- the check would pass vacuously.
        regs = re.findall(r"(\d):(x\d+)=(\d+)", ln)
        # NOT [a-wyz]: excluding 'x' to dodge register names also excluded the
        # VARIABLE x, which is exactly what this class of test constrains.
        # Registers are always "N:"-prefixed, and the ^/; anchors already
        # exclude them, so [a-z] is both safe and correct.
        mems = re.findall(r"(?:^|;\s*)([a-z]\w*)=(\d+)", ln)
        if regs or mems:
            d = {(int(h), r): int(v) for h, r, v in regs}
            for nm, v in mems: d[("mem", nm)] = int(v)
            allowed.append(d)
if not allowed:
    print("ORACLE_MISSING"); sys.exit(0)

# ---- decode this design's (h0,h1) into the herd's register naming --------
# Each hart's main() returns the registers the test's condition names.
#   MP: only P1 observes; h1 packs (x5<<1)|x7
#   SB: each hart returns its own x7
#   LB: each hart returns its own x5
def decode(name, h0, h1, mx=0, my=0):
    if name.startswith("S+fence"):
        return {(1,"x5"): h1 & 1, ("mem","x"): mx}
    if name.startswith("MP"): return {(1,"x5"): (h1>>1)&1, (1,"x7"): h1&1}
    if name == "SB": return {(0,"x7"): h0&1,      (1,"x7"): h1&1}
    if name == "LB": return {(0,"x5"): h0&1,      (1,"x5"): h1&1}
    # LR-SC-diff-loc3: each hart returns (x8<<1)|x5. herd's state line also
    # carries x=0; y=0, but those have no "N:" prefix so the parser above does
    # not capture them -- and they are implied anyway: if both SCs fail,
    # neither location can have been written.
    if name.startswith("LR-SC"):
        # herd's state also carries x=0; y=0, and now that bare memory terms ARE
        # parsed the decoder must supply them or the observed dict can never
        # match the allowed one. They are not redundant: "both SCs failed" and
        # "neither location was written" are separate claims, and a failed SC
        # that still stores would break exactly the second one.
        return {(0,"x5"): h0&1, (0,"x8"): (h0>>1)&1,
                (1,"x5"): h1&1, (1,"x8"): (h1>>1)&1,
                ("mem","x"): mx, ("mem","y"): my}
    return None

seen = []
for o in obs:
    parts = o.split(",")
    h0, h1 = int(parts[0]), int(parts[1])
    mx = int(parts[2]) if len(parts) > 2 else 0
    my = int(parts[3]) if len(parts) > 3 else 0
    d = decode(name, h0, h1, mx, my)
    if d is None: print("NO_DECODER"); sys.exit(0)
    if d not in seen: seen.append(d)

def fmt(d):
    out = []
    for k, v in sorted(d.items(), key=lambda kv: str(kv[0])):
        out.append(("%s=%d" % (k[1], v)) if k[0] == "mem"
                   else ("%d:%s=%d" % (k[0], k[1], v)))
    return " ".join(out)

forbidden = [d for d in seen if d not in allowed]
unseen    = [a for a in allowed if a not in seen]

print("ALLOWED %d | OBSERVED %d | UNSEEN %d" % (len(allowed), len(seen), len(unseen)))
for d in seen:
    print("   obs  %s%s" % (fmt(d), "   *** FORBIDDEN ***" if d in forbidden else ""))
for a in unseen:
    print("   --   %s   (allowed, never observed -- not a failure)" % fmt(a))
print("VERDICT " + ("FORBIDDEN_OBSERVED" if forbidden else "OK"))
PY
)
  echo "  [$t]"
  echo "$RESULT" | sed 's/^/     /'
  case "$RESULT" in
    *FORBIDDEN_OBSERVED*) fail=$((fail+1)); failed="$failed $t" ;;
    *ORACLE_MISSING*|*NO_DECODER*) fail=$((fail+1)); failed="$failed $t(oracle)" ;;
    *) pass=$((pass+1)) ;;
  esac
done

echo "LITMUS: pass=$pass fail=$fail$failed"
[ "$fail" -eq 0 ] || exit 1
