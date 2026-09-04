#!/usr/bin/env bash
# Read coverage.dat, and report the two kinds of coverage in it separately.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

MODE=summary
DAT=coverage.dat
for a in "$@"; do
  case "$a" in
    --bins) MODE=bins ;;
    --dead) MODE=dead ;;
    *)      DAT="$a" ;;
  esac
done

if [[ ! -f "$DAT" ]]; then
  echo "cov_report.sh: no $DAT." >&2
  echo "  It is written by the RUN, not the build -- a failed build leaves the" >&2
  echo "  PREVIOUS one on disk, so check its timestamp against the run you mean." >&2
  exit 1
fi

echo "=== $DAT   ($(date -r "$DAT" '+%Y-%m-%d %H:%M:%S'), $(grep -c '' "$DAT") records) ==="
echo "    Check that timestamp against the run you think you are reading."
echo

parse() {
  awk -v mode="$1" '
  BEGIN { SOH = sprintf("%c", 1); STX = sprintf("%c", 2) }
  /^#/ { next }
  {
    # count is the last whitespace-separated token; the key is inside the quotes
    n = split($0, tok, " "); cnt = tok[n] + 0
    key = $0
    sub(/^C '"'"'/, "", key); sub(/'"'"' *[0-9]+ *$/, "", key)

    delete F
    m = split(key, parts, SOH)
    for (i = 1; i <= m; i++) {
      if (parts[i] == "") continue
      p = index(parts[i], STX)
      if (p == 0) continue
      F[substr(parts[i], 1, p-1)] = substr(parts[i], p+1)
    }

    t = F["t"]; f = F["f"]

    if (t == "covergroup") {
      grp = F["h"]; sub(/\..*$/, "", grp); sub(/^__vlAnonCG_/, "", grp)
      # CROSS-BUILD MERGE DETECTOR. The record key embeds the SOURCE LINE, so a
      # covergroup that moved -- because something was inserted above it -- has
      # a different key in the new build and verilator_coverage merges the two
      # as SEPARATE bins rather than as one. The union then reads LARGER than
      # the model actually defines and every percentage below it is wrong.
      # Measured: inserting cg_onset above cg_issue turned 11 bins into 22.
      # Identical bin name at two different lines is the fingerprint.
      if ((F["h"] in seen_line) && (seen_line[F["h"]] != F["l"])) dup_bins++
      else seen_line[F["h"]] = F["l"]
      cg_tot[grp]++; cg_tot_all++
      if (cnt > 0) { cg_hit[grp]++; cg_hit_all++ }
      bt = F["bin_type"]
      if (bt != "") { il_tot[bt]++; if (cnt > 0) il_hit[bt]++ }
      if (mode == "bins")
        printf "%-9s %-26s %-34s %s\n", (cnt>0 ? cnt : "."), grp, F["h"], \
               (bt == "" ? "" : "[" bt "]")
    } else if (t == "line" || t == "branch") {
      ln_tot[f]++; ln_tot_all++
      if (cnt > 0) { ln_hit[f]++; ln_hit_all++ }
      else if (mode == "dead") printf "%-40s %6s  %-6s %-10s %s\n", f, F["l"], F["t"], F["o"], F["h"]
    } else {
      other[t]++
    }
  }
  END {
    if (mode == "bins" || mode == "dead") exit
    if (dup_bins > 0) {
      printf "!! %d DUPLICATE BINS -- this file merges .dat from DIFFERENT BUILDS.\n", dup_bins
      printf "!! The record key embeds the source line, so a covergroup that moved\n"
      printf "!! merges as two bins instead of one. Re-run every test against ONE\n"
      printf "!! build before reading any number below.\n\n"
    }
    printf "FUNCTIONAL  (--coverage-user, the hand-written cov_*.sv bins)\n"
    printf "  %d bins, %d hit, %d unhit\n", cg_tot_all, cg_hit_all, cg_tot_all - cg_hit_all
    for (g in cg_tot)
      printf "    %-28s %4d bins  %4d hit  %4d unhit\n", g, cg_tot[g], cg_hit[g]+0, cg_tot[g]-cg_hit[g]
    # THE ALARM MUST MEAN ONE THING. A hit on an illegal or ignore bin is a
    # FINDING: putm_never_issued firing would mean the cache issued a request
    # the design says it cannot. A hit on a default bin is NORMAL, because
    # default is the catch-all for values outside the enumerated set, and the
    # deliberate all-zero illegal instruction in lrsc_trap lands in cg_opcode
    # on every run. Printing all three under one warning is how a working alarm
    # gets dismissed as noisy.
    #
    # NOTE: this awk program is SINGLE-QUOTED in the surrounding shell, so an
    # apostrophe anywhere in a comment terminates it and the shell then tries to
    # parse awk syntax. That is what happened writing this block.
    for (b in il_tot) {
      printf "  %s bins: %d, of which HIT: %d", b, il_tot[b], il_hit[b]+0
      if (b == "default")
        printf "%s\n", (il_hit[b]+0 > 0 ? "   (a value outside the enumerated set occurred -- expected here)" : "")
      else
        printf "%s\n", (il_hit[b]+0 > 0 ? "   <-- an ILLEGAL/IGNORE bin was HIT: this is a finding" : "")
    }
    printf "\n"
    printf "CODE  (--coverage-line, derived from the RTL -- NOT a percentage target)\n"
    if (ln_tot_all == 0) {
      printf "  no line/branch records. Either --coverage-line is off, or\n"
      printf "  cov_scope.vlt is excluding more than it should.\n"
    } else {
      printf "  %d line/branch points, %d executed, %d NEVER EXECUTED\n", \
             ln_tot_all, ln_hit_all, ln_tot_all - ln_hit_all
      printf "  per file, worst first -- these are the blocks no test reached:\n"
      for (f in ln_tot) if (ln_tot[f] - ln_hit[f] > 0)
        printf "@@%08d    %6d never / %6d  %s\n", ln_tot[f]-ln_hit[f], ln_tot[f]-ln_hit[f], ln_tot[f], f
    }
    for (t in other) printf "\n  (%d records of unrecognised type \"%s\")\n", other[t], t
  }' "$DAT"
}

case "$MODE" in
  bins)    echo "count     covergroup                 bin"; parse bins | sort -k2,2 -k3,3 ;;
  dead)    echo "NEVER EXECUTED -- file, line, record type, KIND, hierarchy"
           echo
           echo "  READ THE KIND COLUMN. A zero at line L does NOT mean line L is dead."
           echo "  For an if, the zero carried at L is its ELSE arm: kind=else or"
           echo "  cond_else means the code that never ran is the arm BENEATH the"
           echo "  condition, not the condition. This column was missing, and reading"
           echo "  the output as a dead-LINE list is how lrsc_unit's same-line REFRESH"
           echo "  -- 3,007 executions -- came to be recorded in five documents as a"
           echo "  line that never executes, and a mutation on it as VACUOUS rather"
           echo "  than INERT. Same family as the RAS lesson (a zero on a STATEMENT"
           echo "  record says nothing about the condition under it), one level in."
           echo
           parse dead | sort ;;
  summary) parse summary | { grep -v '^@@' || true; } 
           parse summary | { grep '^@@' || true; } | sort -r | sed 's/^@@[0-9]*//'
           echo
           echo "  ./scripts/cov_report.sh --bins    every functional bin"
           echo "  ./scripts/cov_report.sh --dead    every zero-execution block" ;;
esac
