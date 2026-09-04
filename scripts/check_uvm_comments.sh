#!/usr/bin/env bash
# A comment starting with the word "verilator" is a metacomment and kills elaboration.
set -uo pipefail
hits=$(grep -rn --include="*.sv" --include="*.svh" --include="*.vlt" "^[[:space:]]*//[[:space:]]*[Vv]erilator " tb/uvm/ rtl/ 2>/dev/null || true)
if [[ -n "$hits" ]]; then
  echo "pragma collision -- these comments START with 'verilator':"
  echo "$hits"
  exit 1
fi
asm_hits=$(grep -rn --include="*.S" \
  "^[[:space:]]*#[[:space:]]\+\(line\|error\|warning\|define\|include\|if\|ifdef\|ifndef\|else\|endif\|pragma\)\b" \
  asm/ 2>/dev/null || true)
if [[ -n "$asm_hits" ]]; then
  echo "pragma collision -- these .S comments START with a preprocessor keyword:"
  echo "$asm_hits"
  echo "Reword so the keyword is not the first word after the hash."
  exit 1
fi

echo "comment pragma check: clean"
