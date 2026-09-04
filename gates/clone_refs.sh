#!/usr/bin/env bash
# Clone the two repositories the battery needs at run time, pinned by full SHA.
set -uo pipefail

mkdir -p /opt/refs && cd /opt/refs

# Abbreviated SHAs are rejected by the wire protocol, so a 7-char pin silently
# falls through to tip-of-branch. These are full 40-char object names.
REPOS=(
  "riscv-dv|https://github.com/chipsalliance/riscv-dv.git|b7a0b4b0b51346a3c64f159f81ea262d867c14a9"
  "litmus-tests-riscv|https://github.com/litmus-tests/litmus-tests-riscv.git|08728edcd99c7e1819d2d4c6789df6d5299ccb69"
)

FAILED=0
for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url sha <<< "$entry"
  echo "=== $name ==="
  rm -rf "$name"; mkdir -p "$name"
  pushd "$name" > /dev/null
  git init -q .
  git remote add origin "$url"
  if git fetch --depth 1 -q origin "$sha" 2>/dev/null; then
    git checkout -q FETCH_HEAD
    echo "  pinned at ${sha:0:7} ($(git log -1 --format=%ad --date=short))"
  else
    echo "  !! pinned SHA ${sha:0:7} unreachable -- falling back to tip"
    FAILED=1
    git fetch --depth 1 -q origin HEAD && git checkout -q FETCH_HEAD
  fi
  git log -1 --format="  head=%h %s" 2>/dev/null | cut -c1-90
  popd > /dev/null
done

echo
echo "=== content checks ==="

# Both files below are read by a gate, so a clone that lacks them produces a
# battery failure much later and further away. Say so here instead.
ORACLE=$(find /opt/refs/litmus-tests-riscv -name "herd.logs" 2>/dev/null | head -1)
if [[ -n "$ORACLE" ]]; then
  echo "  OK      herd.logs                 $(du -h "$ORACLE" | cut -f1)"
else
  echo "  MISSING herd.logs                 <-- run_litmus.sh has no oracle"; FAILED=1
fi

for f in instr_trace_compare.py spike_log_to_trace_csv.py; do
  if [[ -f /opt/refs/riscv-dv/scripts/$f ]]; then
    echo "  OK      $f"
  else
    echo "  MISSING $f  <-- gate ctest_rvfi_ooo imports it"; FAILED=1
  fi
done

echo
du -sh /opt/refs 2>/dev/null
[[ $FAILED -eq 0 ]] && echo "REFS: both pinned, both gate inputs present" \
                    || echo "REFS: DEGRADED -- see !! and MISSING lines above"
exit 0
