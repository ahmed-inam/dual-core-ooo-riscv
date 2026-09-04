#!/usr/bin/env bash
# Declared coverage bins versus reported bins.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

DAT="${1:-coverage.dat}"
if [[ ! -f "$DAT" ]]; then
  echo "cov_bin_audit.sh: no $DAT" >&2
  echo "  It is written by the RUN, not the build. Check its timestamp." >&2
  exit 1
fi

echo "=== declared vs reported bins   ($DAT, $(date -r "$DAT" '+%Y-%m-%d %H:%M:%S')) ==="
echo

awk '
  BEGIN { SOH = sprintf("%c", 1); STX = sprintf("%c", 2) }
  /^#/ { next }
  {
    n = split($0, tok, " "); cnt = tok[n] + 0
    key = $0; sub(/^C ./, "", key); sub(/. *[0-9]+ *$/, "", key)
    delete F
    m = split(key, parts, SOH)
    for (i = 1; i <= m; i++) {
      if (parts[i] == "") continue
      p = index(parts[i], STX); if (p == 0) continue
      F[substr(parts[i], 1, p-1)] = substr(parts[i], p+1)
    }
    if (F["t"] != "covergroup") next
    h = F["h"]                      # __vlAnonCG_<group>.<coverpoint>.<bin>
    ng = split(h, a, ".")
    if (ng < 3) next
    grp = a[1]; sub(/^__vlAnonCG_/, "", grp)
    print grp, a[2], a[3], cnt, F["bin_type"]
  }' "$DAT" > /tmp/cov_reported.$$

awk '
  { sub(/\/\/.*$/, "") }
  /covergroup[ \t]+cg_/ { match($0, /cg_[A-Za-z0-9_]+/); grp = substr($0, RSTART, RLENGTH) }
  /coverpoint/          { match($0, /(cp_[A-Za-z0-9_]+)[ \t]*:/); if (RSTART) { cp = substr($0, RSTART, RLENGTH); sub(/[ \t]*:$/, "", cp) } }
  /bins[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\[/ {
    line = $0
    while (match(line, /bins[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\[[^]]*\][ \t]*=/)) {
      d = substr(line, RSTART, RLENGTH)
      line = substr(line, RSTART + RLENGTH)
      match(d, /bins[ \t]+[A-Za-z_][A-Za-z0-9_]*/); nm = substr(d, RSTART, RLENGTH)
      sub(/^bins[ \t]+/, "", nm)
      match(d, /\[[^]]*\]/); sz = substr(d, RSTART+1, RLENGTH-2)
      wantn = 0
      if (sz ~ /^[0-9]+$/) wantn = sz + 0
      else if (d ~ /\[\][ \t]*=/) {
        if (match(line, /\{[ \t]*\[[ \t]*[0-9]+[ \t]*:[ \t]*[0-9]+[ \t]*\]/)) {
          r = substr(line, RSTART, RLENGTH)
          gsub(/[^0-9:]/, "", r); split(r, e, ":")
          wantn = e[2] - e[1] + 1
        }
      }
      if (grp != "" && cp != "") print grp, cp, nm, wantn
    }
  }' tb/uvm/cov/cov_*.sv > /tmp/cov_declared.$$

awk '
  { sub(/\/\/.*$/, "") }
  /covergroup[ \t]+cg_/ { match($0, /cg_[A-Za-z0-9_]+/); grp = substr($0, RSTART, RLENGTH) }
  /:[ \t]*cross[ \t]/ {
    line = $0
    match(line, /(x_[A-Za-z0-9_]+)[ \t]*:/); if (!RSTART) next
    xn = substr(line, RSTART, RLENGTH); sub(/[ \t]*:$/, "", xn)
    sub(/^.*cross[ \t]+/, "", line); sub(/[;{].*$/, "", line)
    gsub(/[ \t]/, "", line)
    print grp, xn, line
  }' tb/uvm/cov/cov_*.sv > /tmp/cov_cross.$$

awk '
  { sub(/\/\/.*$/, "") }
  /covergroup[ \t]+cg_/ { match($0, /cg_[A-Za-z0-9_]+/); grp = substr($0, RSTART, RLENGTH) }
  /coverpoint/          { match($0, /(cp_[A-Za-z0-9_]+)[ \t]*:/); if (RSTART) { cp = substr($0, RSTART, RLENGTH); sub(/[ \t]*:$/, "", cp) } }
  {
    line = $0
    while (match(line, /(ignore_bins|illegal_bins)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
      d = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
      sub(/^(ignore_bins|illegal_bins)[ \t]+/, "", d)
      if (grp != "" && cp != "") print grp, cp, d
    }
    line = $0
    while (match(line, /bins[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*default/)) {
      d = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
      sub(/^bins[ \t]+/, "", d); sub(/[ \t]*=.*$/, "", d)
      if (grp != "" && cp != "") print grp, cp, d
    }
  }' tb/uvm/cov/cov_*.sv > /tmp/cov_srcdef.$$

awk -v rep=/tmp/cov_reported.$$ -v dec=/tmp/cov_declared.$$ -v xr=/tmp/cov_cross.$$ -v srcd=/tmp/cov_srcdef.$$ '
BEGIN {
  while ((getline l < srcd) > 0) { split(l, d, " "); src_default[d[1] SUBSEP d[2] SUBSEP d[3]] = 1 }
  while ((getline l < rep) > 0) {
    split(l, f, " ")
    nbin[f[1] SUBSEP f[2]]++
    if (f[3] ~ /\[[0-9]+\]$/) narr[f[1] SUBSEP f[2]]++
    else                      plain[f[1] SUBSEP f[2] SUBSEP f[3]] = 1
    # A default / ignore / illegal bin cannot take part in a cross, so it must
    # not be counted into the expected product -- otherwise every group holding
    # one reads short and the real short-falls are lost in the noise.
    # Verilator does not tag every default bin (cg_exception.cp_cause.other is
    # untagged while cg_csr.cp_csr.other is), so the SOURCE is consulted too --
    # the declaration is the authority, not the annotation. (No apostrophes
    # in this awk program: it is single-quoted in the surrounding shell, and one
    # apostrophe ends the quote and hands awk source to bash. Same trap
    # cov_report.sh records against itself.)
    if (f[5] == "default" || f[5] == "ignore" || f[5] == "illegal")
      ndef[f[1] SUBSEP f[2]]++
    else if ((f[1] SUBSEP f[2] SUBSEP f[3]) in src_default)
      ndef[f[1] SUBSEP f[2]]++
    seen_cp[f[1] SUBSEP f[2]] = 1
  }

  print "--- 1. ARRAY-BIN EXPANSION ------------------------------------------------"
  print "    a coverpoint whose `bins n[]` produced ONE bin called `n` has COLLAPSED:"
  print "    it reads fully covered while distinguishing nothing."
  printf "%-20s %-16s %-12s %8s %8s   %s\n", "group", "coverpoint", "bins", "declared", "reported", "verdict"
  bad = 0; unk = 0
  while ((getline l < dec) > 0) {
    split(l, f, " ")
    g = f[1]; cp = f[2]; nm = f[3]; want = f[4] + 0
    k = g SUBSEP cp
    got = narr[k] + 0
    collapsed = ((k SUBSEP nm) in plain)
    if (!(k in seen_cp)) { verdict = "NOT IN .dat (group absent from this run)"; unk++ }
    else if (collapsed && got == 0) { verdict = "*** COLLAPSED to 1 bin ***"; bad++ }
    else if (want > 0 && got != want) { verdict = "*** " got " of " want " ***"; bad++ }
    else verdict = "ok"
    printf "%-20s %-16s %-12s %8s %8d   %s\n", g, cp, nm "[]", (want ? want : "?"), (collapsed ? 1 : got), verdict
  }
  printf "\n    %d array-bin coverpoint(s) WRONG.\n\n", bad

  print "--- 2. CROSS CARDINALITY --------------------------------------------------"
  print "    a cross must report the PRODUCT of its coverpoints reported bin counts."
  print "    fewer means bins were dropped -- which this tool does silently to every"
  print "    cross-level illegal_bins/ignore_bins (%Warning-COVERIGN)."
  printf "%-20s %-22s %8s %8s   %s\n", "group", "cross", "expect", "report", "verdict"
  xbad = 0
  while ((getline l < xr) > 0) {
    split(l, f, " ")
    g = f[1]; xn = f[2]
    ncp = split(f[3], cps, ",")
    want = 1; ok = 1
    for (i = 1; i <= ncp; i++) {
      c = nbin[g SUBSEP cps[i]] - ndef[g SUBSEP cps[i]]
      if (c <= 0) ok = 0
      want *= c
    }
    got = nbin[g SUBSEP xn] + 0
    if (!ok || got == 0) { verdict = "?? (coverpoint or cross absent)"; }
    else if (got != want) { verdict = "*** " got " of " want " ***"; xbad++ }
    else verdict = "ok"
    printf "%-20s %-22s %8d %8d   %s\n", g, xn, want, got, verdict
  }
  printf "\n    %d cross(es) with a bin count the declaration does not explain.\n", xbad
}' </dev/null

rm -f /tmp/cov_reported.$$ /tmp/cov_declared.$$ /tmp/cov_cross.$$ /tmp/cov_srcdef.$$
