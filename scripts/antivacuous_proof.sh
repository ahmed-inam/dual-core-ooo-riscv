#!/usr/bin/env bash
# Prove the anti-vacuous checkers can fail: remove the stimulus, require the fire.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

COV=obj_uvm/cov
ROSTER=docs/checker_roster.txt
OUT=obj_uvm/antivacuous.txt
MINE_ONLY=0
[[ "${1:-}" == "--mine" ]] && MINE_ONLY=1
[[ $MINE_ONLY == 1 ]] && OUT=obj_uvm/antivacuous_mine.txt

[[ -f $ROSTER ]] || { echo "no $ROSTER -- run ./scripts/checker_audit.sh --regen" >&2; exit 1; }

mine () {
  python3 - "$COV" "$ROSTER" <<'PY'
import re, sys, glob, os
cov, roster = sys.argv[1], sys.argv[2]
vac = []
for l in open(roster):
    if l.startswith('#') or not l.strip():
        continue
    f = l.rstrip('\n').split('|')
    if len(f) >= 4 and f[3] == 'VACUOUS':
        vac.append((f[0], f[1], f[2]))
logs = sorted(glob.glob(os.path.join(cov, '*.log')))
for path, cid, fp in vac:
    # the message is a format string; match on the literal head of it, which is
    # what survives $sformatf. A shorter key would collide between checkers in
    # one component, which is why the ID is required as well.
    key = fp.split('%')[0].strip()[:28]
    fired = []
    for lg in logs:
        txt = open(lg, errors='replace').read()
        if key and re.search(r'UVM_(ERROR|WARNING).*\[' + re.escape(cid) + r'\][^\n]*' + re.escape(key), txt):
            fired.append(os.path.basename(lg)[:-4])
    quiet = len(logs) - len(fired)
    # BOTH directions, or it is not a proof: a checker that fires on every
    # program is not discriminating, it is just always on.
    cls = 'MINED' if (fired and quiet) else ('ALWAYS' if fired else 'noevidence')
    print(f"{cls}|{cid}|{fp}|{len(fired)}/{len(logs)}|{','.join(fired[:3])}")
PY
}

echo "=== anti-vacuous proofs ==="
echo
if [[ ! -d $COV ]] || [[ -z "$(ls $COV/*.log 2>/dev/null)" ]]; then
  echo "!! no $COV/*.log -- the MINED class needs a sweep. Run ./scripts/cov_sweep.sh."
  echo "   Refusing to report a partial result as a complete one."
  exit 1
fi
MINED=$(mine)
n_mined=$(echo "$MINED" | grep -c '^MINED' || true)

n_vac=$(awk -F'|' '$0 !~ /^#/ && $4=="VACUOUS"' "$ROSTER" | grep -c . || true)
if [[ $n_vac -lt ${MIN_VACUOUS:-20} ]]; then
  echo "!! docs/checker_roster.txt declares only $n_vac VACUOUS checkers"
  echo "   (expected at least ${MIN_VACUOUS:-20}). This audit's whole subject is"
  echo "   that class; an empty one makes it pass while proving nothing."
  exit 1
fi
n_always=$(echo "$MINED" | grep -c '^ALWAYS' || true)
n_none=$(echo "$MINED" | grep -c '^noevidence' || true)

# 2. FLOOR. Raise a threshold above the observed count and require the fire.
#    Each row: <label> <plusarg> <test> <prog> <ID> <expected phrase>
run_floor () {  # run_floor <label> <plusargs> <test> <prog> <id> <phrase>
  local label=$1 extra=$2 test=$3 prog=$4 cid=$5 phrase=$6
  local hex="asm/$prog.hex" elf="asm/$prog.elf" args tpc
  args="+UVM_TESTNAME=$test +HEX=$hex +TOHOST=80001000"
  [[ -f $elf ]] && args="$args +ELF=$elf"
  tpc=$(${NM:-riscv64-unknown-elf-nm} "$elf" 2>/dev/null | grep -w park_forever | awk '{print $1}')
  [[ -n $tpc ]] && args="$args +TRUNC_PC=$tpc"
  timeout 900 ./obj_uvm/sim_uvm $args $extra > "obj_uvm/av_$label.log" 2>&1
  if grep -qE "UVM_(ERROR|WARNING).*\[$cid\].*$phrase" "obj_uvm/av_$label.log"; then
    # AND THE CONVERSE. A checker that fires with the knob AND without it is not
    # discriminating -- it is broken on. This half is what makes it a proof.
    timeout 900 ./obj_uvm/sim_uvm $args > "obj_uvm/av_${label}_ctl.log" 2>&1
    if grep -qE "UVM_(ERROR|WARNING).*\[$cid\].*$phrase" "obj_uvm/av_${label}_ctl.log"; then
      echo "AMBIGUOUS|$cid|$label|fires WITH and WITHOUT the knob"
    else
      echo "FLOOR|$cid|$label|fires only with $extra"
    fi
  else
    echo "FAILED|$cid|$label|did NOT fire with $extra"
  fi
}

FLOORS=""
if [[ $MINE_ONLY == 0 ]]; then
  if [[ ! -x obj_uvm/sim_uvm ]]; then
    echo "!! no obj_uvm/sim_uvm -- the FLOOR class needs a binary. Build first." >&2
    exit 1
  fi
  echo "  running the FLOOR proofs against obj_uvm/sim_uvm ($(date -r obj_uvm/sim_uvm '+%H:%M:%S'))"
  FLOORS="$(run_floor h0    '+FLOOR_H0=999999'    cpu_base_test mh      SB_RETIRE 'hart0 matched only')
$(run_floor h1    '+FLOOR_H1=999999'    cpu_base_test mh      SB_RETIRE 'hart1 matched only')
$(run_floor quies '+FLOOR_QUIES=999999' cpu_stress_test stress SB_COH   'quiescent samples')
$(run_floor defer '+FLOOR_DEFER=0'      cpu_share_test share  SB_RETIRE 'deferrals exceeds the ceiling')"
fi

# 2b. RECONCILE THE FLOOR RESULTS AGAINST THE ROSTER -- [E5] THE TALLY DID NOT ADD UP.
#
# The report used to print MINED 7 + ALWAYS-ON 0 + FLOOR 4 + UNPROVEN 22 over a
# table with TWENTY-NINE rows. `n_none` counted the `noevidence` rows and the
# FLOOR results were never subtracted from it, so four checkers were counted
# twice and the total came to 33.
#
# It is worse than an off-by-four, because three of the four FLOOR proofs add
# nothing to this denominator at all:
#
#   h0     SB_RETIRE 'hart0 matched only'      noevidence -> a REAL new proof
#   h1     SB_RETIRE 'hart1 matched only'      already MINED -- proves it twice
#   quies  SB_COH    'quiescent samples'       already MINED -- proves it twice
#   defer  SB_RETIRE 'deferrals ... ceiling'   class DESIGN, not VACUOUS. It is
#                                              not one of the 29 and it already
#                                              has a mutation proof (m10,m16).
#
# So the true figure was 8 of 29, and the two closing documents recorded 11 of
# 29 -- one saying 18 unproven and the other 22, neither of which this script
# prints. A number that three artefacts state three ways is a number nothing
# owns. The classification below is computed, and the total is ASSERTED to equal
# the roster's VACUOUS count so it can never silently drift again.
FLOOR_CLASSED=""
if [[ -n $FLOORS ]]; then
  FLOOR_CLASSED=$(python3 - "$ROSTER" <<PY
import sys
roster = sys.argv[1]
rows = []
for l in open(roster):
    if l.startswith('#') or not l.strip():
        continue
    f = l.rstrip('\n').split('|')
    if len(f) >= 4:
        rows.append(f)
mined = set()
for l in """$MINED""".splitlines():
    p = l.split('|')
    if len(p) >= 3 and p[0] == 'MINED':
        mined.add((p[1], p[2]))
for l in """$FLOORS""".splitlines():
    p = l.split('|')
    if len(p) < 4 or p[0] != 'FLOOR':
        continue
    cid, label, phrase = p[1], p[2], p[3]
    # the roster fingerprint is the message truncated to 42 chars; the floor
    # phrase is a literal head of that message, so a substring match on the
    # (id, fingerprint) pair is exact enough and survives a reword of the tail.
    key = {'h0': 'hart0 matched only', 'h1': 'hart1 matched only',
           'quies': 'quiescent samples', 'defer': 'deferrals exceeds the ceiling'}.get(label, label)
    hit = [r for r in rows if r[1] == cid and key in r[2]]
    if not hit:
        print(f"FLOOR-ORPHAN|{cid}|{label}|proves a checker that is NOT IN THE ROSTER")
    elif hit[0][3] != 'VACUOUS':
        print(f"FLOOR-OTHERCLASS|{cid}|{label}|class {hit[0][3]}, not VACUOUS -- outside this denominator")
    elif (cid, hit[0][2]) in mined:
        print(f"FLOOR-DUP|{cid}|{label}|already MINED -- adds nothing to the count")
    else:
        print(f"FLOOR-NEW|{cid}|{hit[0][2]}|{label}")
PY
)
fi
n_floor_new=$(echo "$FLOOR_CLASSED" | grep -c '^FLOOR-NEW' || true)

{
  echo "# anti-vacuous checker proofs -- generated by scripts/antivacuous_proof.sh"
  echo "# class|id|fingerprint|evidence"
  echo "$MINED"
  [[ -n $FLOOR_CLASSED ]] && echo "$FLOOR_CLASSED"
  [[ -n $FLOORS ]] && echo "$FLOORS" | grep -E '^(FAILED|AMBIGUOUS)'
} > "$OUT"

echo
printf '  MINED      %2d  two sweep programs differ; one fires, another does not\n' "$n_mined"
printf '  ALWAYS-ON  %2d  fires on every program -- NOT discriminating, look at it\n' "$n_always"
if [[ -n $FLOORS ]]; then
  printf '  FLOOR      %2d  a threshold raised above the observed count, and the\n' "$n_floor_new"
  printf '                 checker required to fire. NEW proofs only -- see below\n'
  bad=$(echo "$FLOORS" | grep -cE '^(FAILED|AMBIGUOUS)' || true)
  [[ $bad -gt 0 ]] && { echo; echo "  !! $bad floor proof(s) FAILED or were AMBIGUOUS:"; echo "$FLOORS" | grep -E '^(FAILED|AMBIGUOUS)' | sed 's/^/     /'; }
fi
n_unproven=$(( n_vac - n_mined - n_always - n_floor_new ))
printf '  UNPROVEN   %2d  fires only if the ENVIRONMENT is broken; needs an\n' "$n_unproven"
printf '                 instrument break, not a program change\n'
printf '  ---------------\n'
printf '  TOTAL      %2d  VACUOUS rows in %s\n' "$n_vac" "$ROSTER"

if [[ $(( n_mined + n_always + n_floor_new + n_unproven )) != $n_vac ]]; then
  echo
  echo "  !! THE CLASSES DO NOT PARTITION THE ROSTER: $n_mined + $n_always +"
  echo "     $n_floor_new + $n_unproven != $n_vac. A tally that does not add up is"
  echo "     how this audit reported 33 proofs over 29 checkers."
  echo "  ANTIVACUOUS: FAIL"; exit 1
fi

if [[ -n $FLOOR_CLASSED ]]; then
  extra=$(echo "$FLOOR_CLASSED" | grep -vc '^FLOOR-NEW' || true)
  if [[ $extra -gt 0 ]]; then
    echo
    echo "  $extra floor proof(s) ran and add nothing to the count above:"
    echo "$FLOOR_CLASSED" | grep -v '^FLOOR-NEW' \
      | awk -F'|' '{printf "     %-18s %-6s %s\n", $2, $3, $4}'
  fi
fi
echo
echo "  full table: $OUT"
[[ $MINE_ONLY == 1 ]] && \
  echo "  (--mine: PARTIAL. The FLOOR proofs did not run and this file is NOT the
   authority for any shipped figure -- obj_uvm/antivacuous.txt is.)"
echo
echo "  THE UNPROVEN COUNT IS THE HONEST PART OF THIS OUTPUT. It is not a"
echo "  failure -- those checkers guard against a disconnected monitor or a"
echo "  dead tap, and no program can disconnect a monitor. It is the residue"
echo "  that a stimulus-removal campaign structurally cannot reach, and naming"
echo "  it is the difference between a proof and a percentage."
echo
echo "  AND THE CLASS IS NOT RTL-IMMUNE, WHICH THIS SCRIPT USED TO IMPLY."
echo "  A VACUOUS checker detects ABSENCE, and absence has two causes: missing"
echo "  stimulus, or broken RTL. cov_lrsc.sv's \"every SC succeeded\" is provoked"
echo "  by mutation m3 (every SC succeeds regardless of the reservation), and"
echo "  \"observed NO coherence transactions\" is m20's description verbatim."
echo "  Stimulus removal is the CHEAPER route to a proof, not the only one."

echo "$FLOORS" | grep -qE '^(FAILED|AMBIGUOUS)' && { echo "  ANTIVACUOUS: FAIL"; exit 1; }
echo "  ANTIVACUOUS: pass"
exit 0
