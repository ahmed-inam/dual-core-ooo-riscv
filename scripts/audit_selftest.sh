#!/usr/bin/env bash
# Every audit must be shown able to fail; this breaks each one on purpose.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

BAK=$(mktemp -d)
RESTORE=""
cleanup () {
  local f
  for f in $RESTORE; do
    [[ -f "$BAK/$(basename "$f")" ]] && cp -p "$BAK/$(basename "$f")" "$f"
  done
  rm -rf "$BAK"
}
trap cleanup EXIT INT TERM

pass=0; fail=0; skip=0

case_run () {
  local name=$1 file=$2 mut=$3 cmd=$4
  cp -p "$file" "$BAK/$(basename "$file")"
  RESTORE="$RESTORE $file"
  python3 - "$file" <<PY
import sys, re
p = sys.argv[1]
s = open(p).read()
$mut
open(p, 'w').write(s)
PY
  $cmd >/dev/null 2>&1; local rc=$?
  if [[ $rc == 2 ]]; then
    printf '  %-46s skipped (audit unavailable: exit 2)\n' "$name"
    skip=$((skip+1))
    cp -p "$BAK/$(basename "$file")" "$file"
    return 0
  fi
  if [[ $rc == 0 ]]; then
    printf '  %-46s !! STILL PASSES\n' "$name"; fail=$((fail+1))
  else
    printf '  %-46s red\n' "$name"; pass=$((pass+1))
  fi
  cp -p "$BAK/$(basename "$file")" "$file"
  $cmd >/dev/null 2>&1; local rrc=$?
  if [[ $rrc != 0 && $rrc != 2 ]]; then
    printf '  %-46s !! DID NOT RECOVER -- tree may be dirty\n' "  (restore of $(basename "$file"))"
    fail=$((fail+1))
  fi
}

echo "=== every audit must be able to fail ==="
echo

echo "cite_audit.sh"
case_run "a citation drifts off its line" docs/coverage_proofs.md \
  "m = re.search(r'rtl/ooo/rob\.sv:(\d+)', s)
assert m, 'rob.sv is not cited -- this case has decayed into a no-op'
s = s.replace(m.group(0), 'rtl/ooo/rob.sv:9' + m.group(1), 1)" \
  "./scripts/cite_audit.sh --anchors-only"
case_run "a shape is unclassified" docs/coverage_proofs.md \
  "s2 = re.sub(r'(rtl/ooo/rob\.sv:\d+\s+)guard', r'\\\\1?    ', s, count=1)
assert s2 != s, 'no guard-shaped rob.sv row -- this case has decayed into a no-op'
s = s2" \
  "./scripts/cite_audit.sh --anchors-only"

echo "checker_audit.sh"
case_run "a checker vanishes from the roster" docs/checker_roster.txt \
  "s = '\\n'.join(l for l in s.split('\\n') if 'SWMR violated on line' not in l)" \
  "./scripts/checker_audit.sh"
case_run "a roster row has no live checker" docs/checker_roster.txt \
  "s = s.rstrip() + '\\ntb/uvm/sb/sb_coherence.sv|SB_COH|a checker that was deleted|DESIGN|ghost|\\n'" \
  "./scripts/checker_audit.sh"

echo "gate_criteria_check.sh"
case_run "the copies disagree" scripts/run_mutations.sh \
  "s = '\\n'.join(l for l in s.split('\\n') if 'deferrals exceeds the ceiling\\\" ' not in l)" \
  "./scripts/gate_criteria_check.sh"
case_run "a mechanism loses its only gate" scripts/run_regression.sh \
  "s = s.replace('SWMR violated', 'SWMR_VIOLATED_DISABLED')" \
  "./scripts/gate_criteria_check.sh --coverage"


echo "docs_audit.sh"
case_run "a declared figure goes stale" README.md \
  "s2 = re.sub(r'(?m)^(gates\\s+)\\d+$', r'\\g<1>999', s)
assert s2 != s, 'the gates figure was not found -- this case has decayed into a no-op'
s = s2" \
  "./scripts/docs_audit.sh"
case_run "the figures block is DELETED" README.md \
  "s = re.sub(r'<!-- BEGIN CURRENT FIGURES.*?<!-- END CURRENT FIGURES -->', '', s, flags=re.S)" \
  "./scripts/docs_audit.sh"

echo "check_uvm_comments.sh"
case_run "a pragma collision in a .sv" tb/uvm/cov/cov_core.sv \
  "s = '// verilator this line is a metacomment, not a comment\n' + s" \
  "./scripts/check_uvm_comments.sh"
case_run "a cpp directive in a .S comment" asm/nomem.S \
  "s = '#  line coverage cannot see it\n' + s" \
  "./scripts/check_uvm_comments.sh"

echo "check_asm_fresh.sh"
case_run "a source edited without a rebuild" asm/nomem.S \
  "s = s + '\n# selftest: one changed byte is a changed hash\n'" \
  "./scripts/check_asm_fresh.sh"

echo "antivacuous_proof.sh"
case_run "the VACUOUS class is emptied" docs/checker_roster.txt \
  "s = s.replace('|VACUOUS|', '|STRUCT|')" \
  "./scripts/antivacuous_proof.sh --mine"

echo
printf '  %d case(s) produced a red, %d did not, %d skipped\n' "$pass" "$fail" "$skip"
[[ $skip -gt 0 ]] && echo "  (skipped cases could not run -- a mutation is applied. NOT a pass for them.)"
echo
if [[ $pass == 0 ]]; then
  echo "  AUDIT_SELFTEST: FAIL -- NOT ONE case actually ran."
  echo "  Every audit was unavailable (a mutation is applied?). Zero failures out"
  echo "  of zero attempts is not evidence."
  exit 1
fi
if [[ $fail == 0 && $skip -gt 0 ]]; then
  echo "  AUDIT_SELFTEST: PARTIAL -- $pass case(s) proven, $skip could not run."
  echo "  Re-run on an unmutated tree before treating this as complete."
  exit 0
fi
if [[ $fail == 0 ]]; then
  echo "  AUDIT_SELFTEST: pass -- every audit here can report the answer it exists for"
  exit 0
fi
echo "  AUDIT_SELFTEST: FAIL"
echo "  A case that stopped failing means an audit stopped checking. That is the"
echo "  same finding as a checker that stopped firing, and it is silent."
exit 1
