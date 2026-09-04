#!/usr/bin/env bash
# Every figure a document declares must match the artefact that owns it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

DAT=${1:-obj_uvm/cov/merged.dat}
MIN_DECLARED=${MIN_DECLARED:-8}
SELFTEST=0
[[ "${1:-}" == "--selftest" ]] && { SELFTEST=1; DAT=obj_uvm/cov/merged.dat; }

NOCOV=0
for a in "$@"; do [[ "$a" == "--no-coverage" ]] && NOCOV=1; done
[[ $NOCOV == 1 ]] && DAT=/nonexistent-by-design
[[ $NOCOV == 1 ]] && MIN_DECLARED=${MIN_DECLARED_NOCOV:-6}

DOCS="README.md docs/verification.md docs/results.md docs/coverage_proofs.md
      docs/defects_and_lessons.md docs/gate_roster.txt"

present () { for d in $DOCS; do [[ -f $d ]] && echo "$d"; done; }

fig_gates=$(grep -E '^GATES[[:space:]]*\?=' Makefile | grep -oE '[0-9]+' | head -1)
fig_roster=$(grep -c '^  ' docs/gate_roster.txt 2>/dev/null || echo 0)

fig_sites=""; fig_design=""; fig_mech=""; fig_proven=""; fig_vacuous=""
if CHK=$(./scripts/checker_audit.sh --figures 2>/dev/null) && [[ -n $CHK ]]; then
  fig_sites=$(awk '$1=="sites"{print $2}'      <<< "$CHK")
  fig_design=$(awk '$1=="design"{print $2}'    <<< "$CHK")
  fig_mech=$(awk '$1=="mechanisms"{print $2}'  <<< "$CHK")
  fig_proven=$(awk '$1=="proven"{print $2}'    <<< "$CHK")
  fig_vacuous=$(awk '$1=="vacuous"{print $2}'  <<< "$CHK")
fi

AV=obj_uvm/antivacuous.txt
fig_av_proven=""; fig_av_unproven=""
if [[ -f $AV ]]; then
  av_count () { awk -F'|' -v want="$1" '$0 !~ /^#/ && $1==want {n++} END{print n+0}' "$AV"; }
  n_av_mined=$(av_count MINED)
  n_av_new=$(av_count FLOOR-NEW)
  fig_av_proven=$(( n_av_mined + n_av_new ))
  fig_av_unproven=$(( $(av_count noevidence) - n_av_new ))
fi

MR=docs/mutation_roster.txt
fig_mut=""; fig_mut_caught=""; fig_mut_inert=""; fig_mut_missed=""
if [[ -f $MR ]]; then
  mr_count () { awk -F'|' -v want="$1" '$0 !~ /^#/ && NF>=2 && ($2==want || want=="") {n++} END{print n+0}' "$MR"; }
  fig_mut=$(mr_count "")
  fig_mut_caught=$(mr_count CAUGHT)
  fig_mut_inert=$(mr_count INERT)
  fig_mut_missed=$(mr_count MISSED)
  n_other=$(awk -F'|' '$0 !~ /^#/ && NF>=2 && $2!="CAUGHT" && $2!="INERT" && $2!="MISSED" && $2!="NOT-RUN" {n++} END{print n+0}' "$MR")
  if [[ $n_other -gt 0 ]]; then
    echo "!! $MR has $n_other row(s) with a verdict that is not CAUGHT/INERT/MISSED/NOT-RUN."
    fail_mut=1
  fi
fi

fig_bins=""; fig_hit=""; fig_unhit=""
if [[ -f $DAT ]]; then
  read -r fig_bins fig_hit fig_unhit < <(
    ./scripts/cov_report.sh "$DAT" 2>/dev/null \
      | sed -n 's/^ *\([0-9][0-9]*\) bins, \([0-9][0-9]*\) hit, \([0-9][0-9]*\) unhit.*/\1 \2 \3/p' | head -1)
fi
fig_unhit_roster=$(sed -n '/BEGIN UNHIT ROSTER/,/END UNHIT ROSTER/p' docs/coverage_proofs.md 2>/dev/null | grep -c '^cg_' || echo 0)

echo "=== load-bearing figures, derived from their authorities ==="
printf '  %-34s %s\n' "EXPECT_GATES (Makefile)"        "$fig_gates"
printf '  %-34s %s\n' "gate roster entries"            "$fig_roster"
printf '  %-34s %s\n' "uvm_* checker sites"            "$fig_sites"
printf '  %-34s %s\n' "DESIGN sites"                   "$fig_design"
printf '  %-34s %s\n' "DESIGN mechanisms"              "$fig_mech"
printf '  %-34s %s\n' "mechanisms shown able to fail"  "$fig_proven"
printf '  %-34s %s\n' "bins / hit / unhit"             "${fig_bins:-?} / ${fig_hit:-?} / ${fig_unhit:-?}"
printf '  %-34s %s\n' "unhit roster entries"           "$fig_unhit_roster"
printf '  %-34s %s\n' "VACUOUS checkers"               "${fig_vacuous:-?}"
printf '  %-34s %s\n' "  ... shown able to fail"       "${fig_av_proven:-?}"
printf '  %-34s %s\n' "  ... never shown able to fail" "${fig_av_unproven:-?}"
printf '  %-34s %s\n' "mutations run"                 "${fig_mut:-?}"
printf '  %-34s %s\n' "  ... caught / inert / missed"  "${fig_mut_caught:-?} / ${fig_mut_inert:-?} / ${fig_mut_missed:-?}"
echo

fail=${fail_mut:-0}

if [[ "$fig_gates" != "$fig_roster" ]]; then
  echo "!! EXPECT_GATES=$fig_gates but docs/gate_roster.txt lists $fig_roster."
  echo "   Adding a gate needs run_regression.sh, the Makefile and the roster in"
  echo "   ONE patch -- the divergence that has bitten four times."
  fail=1
fi
if [[ -n $fig_unhit && "$fig_unhit" != "$fig_unhit_roster" ]]; then
  echo "!! $fig_unhit bins unhit but the roster in COVERAGE_PROOFS.md lists"
  echo "   $fig_unhit_roster. cov_proof_audit.sh owns this; it is re-checked here"
  echo "   because the ACCOUNTING TABLE in that file is prose and drifted from"
  echo "   its own roster once already (142 against a measured 129)."
  fail=1
fi

FIGBEGIN='<!-- BEGIN CURRENT FIGURES -- checked by scripts/docs_audit.sh -->'
FIGEND='<!-- END CURRENT FIGURES -->'

echo "=== declared CURRENT figures vs their authorities ==="
declared=0; skipped=0
for d in $(present); do
  block=$(awk -v b="$FIGBEGIN" -v e="$FIGEND" '
    index($0,b){i=1;next} index($0,e){i=0;next} i && $0 !~ /^```/ && NF' "$d" 2>/dev/null)
  [[ -z $block ]] && continue
  while read -r key val; do
    [[ -z ${key:-} || $key == \#* ]] && continue
    declared=$((declared+1))
    want=""
    case "$key" in
      gates)      want=$fig_gates ;;
      sites)      want=$fig_sites ;;
      design)     want=$fig_design ;;
      mechanisms) want=$fig_mech ;;
      proven)     want=$fig_proven ;;
      bins)       want=$fig_bins ;;
      hit)        want=$fig_hit ;;
      unhit)      want=$fig_unhit ;;
      vacuous)    want=$fig_vacuous ;;
      av_proven)  want=$fig_av_proven ;;
      av_unproven) want=$fig_av_unproven ;;
      mut)         want=$fig_mut ;;
      mut_caught)  want=$fig_mut_caught ;;
      mut_inert)   want=$fig_mut_inert ;;
      mut_missed)  want=$fig_mut_missed ;;
      *) echo "  UNKNOWN KEY  $d: '$key' -- add it to docs_audit.sh or remove it"
         fail=1; continue ;;
    esac
    if [[ $NOCOV == 1 && ( $key == bins || $key == hit || $key == unhit ) ]]; then
      declared=$((declared-1)); skipped=$((skipped+1)); continue
    elif [[ -z $want ]]; then
      echo "  NO AUTHORITY $d: $key -- the measurement was unavailable this run"
      echo "               (a missing authority is not a pass; run cov_sweep.sh)"
      fail=1
    elif [[ "$val" != "$want" ]]; then
      echo "  STALE        $d: $key = $val, measured $want"
      fail=1
    fi
  done <<< "$block"
done
if [[ $declared -lt $MIN_DECLARED ]]; then
  echo "!! only $declared declared figure(s), expected at least $MIN_DECLARED."
  echo "   An empty or unreadable CURRENT FIGURES block makes this audit pass"
  echo "   while checking nothing. Raise MIN_DECLARED deliberately if figures"
  echo "   are genuinely retired; never let it drift to zero."
  fail=1
else
  echo "  $declared declared figure(s) checked (floor $MIN_DECLARED)"
  [[ $skipped -gt 0 ]] && \
    echo "  $skipped coverage figure(s) SKIPPED (--no-coverage); cov_sweep.sh checks those"
fi
echo

if [[ $SELFTEST == 1 ]]; then
  echo "  --selftest has been REMOVED from this script; it could not fail correctly."
  echo "  Use ./scripts/audit_selftest.sh, which tests this audit on a scratch copy."
  exit 2
fi

[[ $fail == 0 ]] && { echo "  DOCS_AUDIT: pass"; exit 0; }
echo "  DOCS_AUDIT: FAIL"
exit 1
