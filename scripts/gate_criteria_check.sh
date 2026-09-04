#!/usr/bin/env bash
# The gate's design-finding allowlist lives in three files; they must agree.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

pairs () {  # pairs <file>
  grep -hE '^[^#]*(grep -qE|red_by) "UVM_ERROR' "$1" \
  | grep -oE 'UVM_ERROR[^"]*' \
  | while read -r pat; do
      id=$(echo "$pat" | sed -n 's/.*\\\[\([A-Z_|()]*\)\\\].*/\1/p')
      rest=$(echo "$pat" | sed 's/.*\\\][.*]*//')
      [[ -z $id ]] && continue
      for i in $(echo "$id" | tr -d '()' | tr '|' ' '); do
        if [[ -z $rest ]]; then
          echo "$i|*"
        else
          for p in $(echo "$rest" | sed 's/^(//; s/)$//' | tr '|' '\n' | sed 's/^ *//; s/ *$//' | tr ' ' '~'); do
            echo "$i|$(echo "$p" | tr '~' ' ')"
          done
        fi
      done
    done | sort -u
}

EXPECT_BLIND=${EXPECT_BLIND:-2}
if [[ "${1:-}" == "--coverage" ]]; then
  if ls rtl/**/*.mutorig >/dev/null 2>&1 || ls rtl/*/*.mutorig >/dev/null 2>&1; then
    echo "!! A MUTATION IS APPLIED (a .mutorig exists). --coverage reads SOURCE;"
    echo "   wait for the campaign to finish before trusting its verdict."
    exit 2
  fi
  tmp=$(mktemp)
  pairs scripts/run_regression.sh > "$tmp"
  if [[ ! -s $tmp ]]; then
    echo "!! the allowlist extractor produced NOTHING. Same clause as the copy"
    echo "   check above: an empty extraction is a broken normaliser, not a"
    echo "   design with no criteria."
    rm -f "$tmp"; exit 1
  fi
  python3 scripts/lib/gate_coverage.py "$EXPECT_BLIND" "$tmp"
  rc=$?; rm -f "$tmp"; exit $rc
fi

A=$(pairs scripts/run_regression.sh)
B=$(pairs scripts/run_mutations.sh)

echo "=== gate design-finding allowlist, normalised to (ID, phrase) pairs ==="
echo
printf '  run_regression.sh : %d pair(s)\n' "$(echo "$A" | grep -c .)"
printf '  run_mutations.sh  : %d pair(s)\n' "$(echo "$B" | grep -c .)"
echo

if [[ -z $A || -z $B ]]; then
  echo "!! one side produced NOTHING. This check cannot pass by finding nothing;"
  echo "   an empty extraction means the pattern shape changed, not that the"
  echo "   copies agree."
  exit 1
fi

d=$(diff <(echo "$A") <(echo "$B"))
if [[ -z $d ]]; then
  echo "$A" | sed 's/^/    /'
  echo
  echo "  GATE_CRITERIA: pass -- the copies admit the same set"
  exit 0
fi

echo "!! GATE CRITERIA DRIFT. '<' is in run_regression.sh only (the battery"
echo "   catches it and a fast mutation grade does NOT); '>' is in"
echo "   run_mutations.sh only (a mutation is graded on something the battery"
echo "   does not gate)."
echo "$d" | sed 's/^/    /'
echo
echo "  Both are failures, and the first is the one that has already happened."
echo "  GATE_CRITERIA: FAIL"
exit 1
