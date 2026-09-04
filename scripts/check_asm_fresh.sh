#!/usr/bin/env bash
# Every asm/*.hex must match the source it was built from, by content hash.
# git does not keep mtimes, so a timestamp check is vacuous after a clone.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SIDECAR=asm/SOURCES.sha256
MODE=check
[[ "${1:-}" == "--record" ]] && MODE=record

hash () {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

if [[ $MODE == record ]]; then
  {
    echo "# name  source-sha256  hex-sha256   (regenerate: scripts/check_asm_fresh.sh --record)"
    for src in asm/*.S asm/csrc/*.c; do
      [[ -f "$src" ]] || continue
      base=$(basename "$src"); base="${base%.*}"
      hex="asm/$base.hex"
      [[ -f "$hex" ]] || continue
      echo "$base $(hash "$src") $(hash "$hex")"
    done
  } > "$SIDECAR"
  echo "recorded $(grep -vc '^#' "$SIDECAR") program(s) in $SIDECAR"
  exit 0
fi

[[ -f $SIDECAR ]] || { echo "!! no $SIDECAR: run scripts/check_asm_fresh.sh --record after rebuilding"; exit 1; }

stale=0
for src in asm/*.S asm/csrc/*.c; do
  [[ -f "$src" ]] || continue
  base=$(basename "$src"); base="${base%.*}"
  hex="asm/$base.hex"
  [[ -f "$hex" ]] || continue
  rec=$(awk -v b="$base" '$1==b {print $2" "$3; exit}' "$SIDECAR")
  if [[ -z $rec ]]; then
    echo "  STALE: $hex has no record in $SIDECAR"; stale=$((stale+1)); continue
  fi
  set -- $rec
  if [[ "$(hash "$src")" != "$1" ]]; then
    echo "  STALE: $src changed since $hex was recorded"; stale=$((stale+1))
  elif [[ "$(hash "$hex")" != "$2" ]]; then
    echo "  STALE: $hex changed without a matching --record"; stale=$((stale+1))
  fi
done

if [[ $stale -eq 0 ]]; then
  echo "asm freshness: clean -- every .hex matches the recorded hash of its source"
  exit 0
fi
echo "!! $stale stale .hex file(s). Nothing in the flow rebuilds a program's hex from"
echo "   its source, so an edited program runs as its OLD self. Rebuild per"
echo "   asm/REBUILD.md, then run scripts/check_asm_fresh.sh --record."
exit 1
