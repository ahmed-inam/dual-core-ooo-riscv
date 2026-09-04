import sys, os, re, collections
expect_blind = int(sys.argv[1])
pairs = collections.defaultdict(set)
for line in open(sys.argv[2]):
    line = line.strip()
    if not line or '|' not in line: continue
    i, ph = line.split('|', 1)
    pairs[i].add(ph)

def sites(path):
    L = open(path, errors='replace').read().splitlines()
    out = []
    for i, raw in enumerate(L):
        if raw.strip().startswith('//'): continue
        m = re.search(r'`uvm_(error|fatal|warning)\s*\(', raw)
        if not m: continue
        blob = ' '.join(x.strip() for x in L[i:i+12])
        blob = blob[blob.index(m.group(0)) + len(m.group(0)):]
        qs = re.findall(r'"([^"]*)"', blob)
        cid = qs[0] if qs and re.fullmatch(r'[A-Z_][A-Z_0-9]*', qs[0]) else '?'
        msg = ''
        for q in qs:
            if q == cid or len(q) < 6: continue
            msg = q; break
        fp = re.sub(r'\s+', ' ', msg).strip()[:42] or '<no literal>'
        out.append((cid, fp, ' '.join(qs)))
    return out

# GATED, BUT NOT BY AN ERROR-ID PATTERN. Two mechanisms fail a gate through the
# criteria that sit ABOVE the allowlist, and an audit that only knows about the
# allowlist reports them as blind -- a false negative in the instrument, which is
# the class this whole script exists for. Named, with the criterion, rather than
# silently counted either way.
OTHER_GATED = {
    "retire: architectural + memory comparison":
        "uvm_gate's `mismatches == 0`; the site has no literal to match",
    "test: run did not terminate":
        "the floor timeout ends the run, so CHECKED falls below the gate's floor",
}

cache = {}
mech = collections.defaultdict(list)
for line in open('docs/checker_roster.txt'):
    if line.startswith('#') or not line.strip(): continue
    f = (line.rstrip('\n').split('|') + ['']*6)[:6]
    if f[3] != 'DESIGN' or not f[4]: continue
    mech[f[4]].append((f[0], f[1], f[2], f[5]))

def visible(path, cid, fp):
    if cid not in pairs: return False
    if '*' in pairs[cid]: return True
    if path not in cache: cache[path] = sites(path)
    for c, fpp, full in cache[path]:
        if c == cid and fpp.startswith(fp[:30]):
            for ph in pairs[cid]:
                if ph in full: return True
    return False

blind, seen = [], []
for m in sorted(mech):
    ok = any(visible(p, c, fp) for p, c, fp, _ in mech[m])
    muts = ",".join(sorted({x[3] for x in mech[m] if x[3]})) or "-"
    if not ok and m in OTHER_GATED:
        seen.append((m, muts + "   [via " + OTHER_GATED[m] + "]"))
    else:
        (seen if ok else blind).append((m, muts))

print()
print("=== can a battery gate fail on this mechanism? ===")
print()
for m, mu in seen:  print("    yes   %-46s %s" % (m, mu))
print()
for m, mu in blind: print("    NO    %-46s %s" % (m, mu))
print()
print("  %d of %d DESIGN mechanism(s) are gate-visible; %d cannot fail any gate."
      % (len(seen), len(seen)+len(blind), len(blind)))
if len(blind) > expect_blind:
    print()
    print("!! %d blind, EXPECT_BLIND=%d. A mechanism became unreachable by the" % (len(blind), expect_blind))
    print("   battery, or a new DESIGN row arrived with no gate criterion. Add the")
    print("   pattern to uvm_gate/uvm_cov_gate AND run_mutations.sh, or raise")
    print("   EXPECT_BLIND on purpose and record why.")
    print("  GATE_COVERAGE: FAIL")
    sys.exit(1)
if len(blind) < expect_blind:
    print()
    print("  note: %d blind, below EXPECT_BLIND=%d. Lower it to lock the gain in." % (len(blind), expect_blind))
print("  GATE_COVERAGE: pass")
