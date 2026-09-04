#!/usr/bin/env bash
# Every source-level audit, in one command.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
run () {
  local name=$1; shift
  printf "\n===== %s =====\n" "$name"
  if "$@"; then printf "  -> ok\n"; else
    local rc=$?
    if [[ $rc == 2 ]]; then
      printf "  -> SKIPPED (exit 2: a mutation is applied; not a verdict)\n"
    else
      printf "  -> FAILED\n"; fail=1
    fi
  fi
}

run "comment pragmas"      ./scripts/check_uvm_comments.sh
run "asm freshness"        ./scripts/check_asm_fresh.sh
run "gate criteria copies" ./scripts/gate_criteria_check.sh
run "gate criteria cover" ./scripts/gate_criteria_check.sh --coverage
run "checker roster"       ./scripts/checker_audit.sh
run "4d citations"         ./scripts/cite_audit.sh --anchors-only
run "document figures"     ./scripts/docs_audit.sh
run "anti-vacuous (mined)" ./scripts/antivacuous_proof.sh --mine
run "audits can fail"      ./scripts/audit_selftest.sh

printf "\n"
[[ $fail == 0 ]] && { echo "AUDIT_ALL: pass"; exit 0; }
echo "AUDIT_ALL: FAIL"; exit 1
