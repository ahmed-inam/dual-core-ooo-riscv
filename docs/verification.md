# What the verification claims, and what it does not

This is the closing position of the verification stage. It states the claim the
work ships with, and the residue it explicitly does **not** claim, so that no
later reader has to reconstruct which was which.

The stage was closed here by decision, not by exhaustion.

> **A note on provenance.** This document is `UVM_BUILD.md` §5, §5.1 and §5.2,
> preserved. That file was the forward-looking build specification for the UVM
> environment; it was retired once the environment existed, but its section 5 is
> the acceptance criteria that every plan since was written against, so it is
> kept rather than deleted. Several script comments in `scripts/` cite the
> working documents of that stage by their original names - `SESSION_BRIEF.md`,
> `VERIFICATION_STATUS.md`, `CHECKER_INVENTORY.md`, `COVERAGE_REVIEW.md` and
> others. Those files are not published here. Where a comment describes a defect
> those documents once contained, it is a **historical account and accurate as
> such**; renaming the subject would falsify it.

---

## 1. The acceptance criteria

The environment is done when:

* it reproduces the results of the 7 cluster-level gates it overlaps, at four
  memory latencies - agreeing with them, not replacing them;
* every checker it adds is **mutation-proven** - break the design deliberately
  and require the checker to go red. A green suite that cannot fail is worth
  nothing, and this project has shipped two checkers that could not fail;
* every checker reads **clean on a known-good run first**. A metric only ever
  read on a failing run is a hypothesis. This is the most expensive lesson in
  `defects_and_lessons.md` - it produced a confident published root cause that
  had to be withdrawn;
* functional coverage reports a number, and the uncovered bins are explained
  rather than ignored;
* the full battery still passes with **zero failures at its new, larger total**,
  with `EXPECT_GATES` and `gate_roster.txt` updated together.

Bullets 2 and 3 are **two separate criteria on purpose.** Treating them as one
is how a checker that fires 404 times on a correct design got recorded as
proven.

---

## 2. Why bullet 2 was narrowed

**Bullet 2 as written is not achievable, and the arithmetic that shows it was
not available when it was written.**

When it was written the environment had a handful of checkers. It now has 154
`uvm_*` sites, and `checker_roster.txt` classifies every one:

```
STRUCT 65   VACUOUS 31   INSTR 8   PROGARG 7   REF 6   DESIGN 37
```

**65 of them are testbench-configuration guards** - a null virtual interface, a
missing `cpu_cfg`, a `do_copy` type mismatch. No RTL change provokes one, ever.
"Break the design deliberately and require the checker to go red" asks, for
those 62, that a missing testbench connection be caused by an RTL edit. That is
a category error in the specification, not a shortfall in the work.

**And the obvious wider argument is wrong, so it is not made here.** For a stage
this claim read *"three of the six classes cannot be provoked by ANY RTL change
… 62 STRUCT, 29 VACUOUS, 6 INSTR"*, which overstates by roughly 3×. A VACUOUS
checker detects **absence**, and absence has two causes - missing stimulus *or*
broken RTL. `cov_lrsc.sv`'s "every SC succeeded" is fired by mutation m3, whose
description is "every SC succeeds regardless of the reservation";
`snoop_monitor`'s "observed NO coherence transactions" is m20's description word
for word. Roughly 18 of them are RTL-provokable in principle. The conclusion
survives on STRUCT alone; the arithmetic did not, and a false premise under a
true conclusion is worth deleting before somebody reuses it.

**Bullet 2 is therefore discharged as three claims, each machine-derived.** No
figure is typed into prose; each is produced by the script named, and
`scripts/docs_audit.sh` (battery gate `uvm_docs`) fails if a document states one
that does not match:

| claim | how it is proven | script | authority |
|---|---|---|---|
| **DESIGN mechanisms** shown able to fail by a mutation | break the RTL, require a checker to go red, and record **the checker's own message** | `checker_audit.sh --figures` | `checker_roster.txt`, `mutation_roster.txt` |
| **VACUOUS checkers** shown able to fail by stimulus removal | take the stimulus away, require the fire, and require SILENCE on the control | `antivacuous_proof.sh` | `obj_uvm/antivacuous.txt` |
| **STRUCT / INSTR / PROGARG / REF**, 86 sites | out of scope for both routes. **Named, never counted** | `checker_audit.sh` | `checker_roster.txt` |

**A `mut` cell is a proof only if a log contains the checker's own words.** This
is the operative sentence, and it is the one the stage got wrong. The roster
shipped for four sessions crediting mutation `m14` with proving
`axi: RLAST vs AxLEN`; that checker reads ARLEN off the bus and compares it to
the beats the slave returned, m14 shortens the master's ARLEN, the slave honours
it, and the two agree - **the checker is silent by construction.** What reddened
the gate was the resulting hang. `grep RLAST` over that run's log returns
nothing, in any session. An attribution that is never checked against a log is
indistinguishable from a proof until somebody checks.

This amendment is a **stronger** criterion than the sentence it narrows, not a
weaker one: every part of it is re-derivable by a script, and the original was
not checkable at all.

---

## 3. What is claimed

```
make regression            92 gates, 0 failures
retirement comparison      ~189,000 instructions against Spike, 0 mismatches
coverage                   763 bins, 632 hit, 131 unhit, every one with a
                           machine-checked written proof or an explicit
                           statement that no program forces it
memory latency             both sides, four latencies, regimes proven to DIFFER
                           rather than merely to pass
DESIGN mechanisms          13 of 26 shown able to fail (11 under section 4's strict reading)
battery reach              24 of 26 mechanisms CAN fail a gate; 2 cannot,
                           and both are named below
register model             uvm_reg over the machine CSRs, back-door read,
                           reset + access-policy + mirror checks
VACUOUS checkers           9 of 32 shown able to fail by stimulus removal
audits                     9, of which 8 are proven able to fail; the ninth
                           IS the self-test harness
```

The live figures are in the `CURRENT FIGURES` block in `README.md`, which the
battery diffs against the artefacts that own them.

---

## 4. Three corrections to earlier claims

**The revision is the point.** The version before this one said *"12 of 24 shown
able to fail, EVERY credit backed by a log line containing the checker's own
words."* Three things were wrong with that sentence, and all three are the class
section 2 was written for. They are recorded rather than quietly corrected.

### Fourteen of the mechanisms could not fail the battery

`uvm_gate`'s design-finding allowlist held eight `(ID, phrase)` pairs, and
`[SB_COH]`, `[SNOOP_MON]`, `[RVFI_MON]` and `[MEM_MON]` were not among them.
Under mutation m6 - a SHARED line left un-invalidated by a remote GetM, the
exact defect `check_swmr` exists for - the battery read `pass=75 fail=11` and
**three gates that logged `[SB_COH] SWMR violated` PASSED**. Every gate that did
redden reddened for another reason.

Twelve patterns were added, three checkers promoted `uvm_warning` → `uvm_error`
to be reachable at all, and `gate_criteria_check.sh --coverage` (gate
`uvm_criteria`) now JOINS the allowlist to `checker_roster.txt` so this cannot
silently return.

**Two identical allowlists can both be incomplete**, and the guard that existed
only checked that they were identical.

### Two of the credits are not discriminating

`[SB_COH] cache tag_q holds` fires **404 times on the clean `uvm_fencefull` gate
and 404 times under m6** - identical output on a correct design and a broken
one. `[COV_COH] implying it held` fires on the clean `uvm_satviol` gate. Both
mechanisms are credited to m6 and m9.

Section 1 states mutation-proven and reads-clean-on-a-known-good-run as two
criteria on purpose. **Under bullet 3 read strictly the count is 11 of 26, not
13.** The credits are retained on a COUNT DIFFERENCE - `uvm_satviol` 2 clean /
174 mutated, `uvm_stress` 0 / 21 - which is a weaker and more honest claim than
"the checker fired". These are the two mechanisms no gate can fail on, because
gating a checker that is not silent on a good run would fail a correct battery.

### "A log contains the checker's own words" was not satisfiable

`run_uvm_gate` writes `obj_uvm/mut_<gate>.log`, which every subsequent gate of
every subsequent mutation overwrites, and the control run overwrites before each
campaign. The campaign logs named in `mutation_roster.txt` existed nowhere on
the machine. Before the m6 re-run, the string `SWMR violated` appeared in
**zero** files anywhere - including for the headline result recorded
earlier. What survives is the roster's transcription, truncated at 160
characters. The rule stands; the evidence for it has to be kept.

---

## 5. What is NOT claimed, and how strong each reason is

Graded, because "the decision was taken deliberately, with reasons" is only
checkable if the reasons are legible.

**strong** = defensible under scrutiny. **adequate** = holds, but the reason
previously given was wrong or thin. **weak** = a real gap being accepted.
**none** = a decision, not a justification.

| not claimed | reason | strength |
|---|---|---|
| `snoop: ordering-point atomicity`, `snoop: install timeout`, `coh: ordering-point self-report`, `coh: response/request encoding` | Redundant nets over ground the backdoor comparison already covers, which is proven. All four are now GATED even though unproven, so a firing would fail the battery | **strong** |
| `isa: malformed byte mask`, `axi: orphan response bookkeeping`, `isa: AXI constants vs axi_adapter` | The previous text said "redundant over SWMR and C1-equivalence". **That is the wrong instrument** - none of these is in the coherence domain and SWMR says nothing about byte lanes or AXI responses. The real net is the Spike retirement comparison, which does catch all three | **adequate, reason corrected** |
| `coh: illegal C1 cell`, `isa: access outside the linked image` | Gated, never provoked; each has a second net. Reachable if anyone changes their mind | **adequate** |
| `axi: RLAST vs AxLEN` (`m14-REFUTED`) | Needs a SLAVE-side mutation; the master-side one cannot provoke it, which is section 2's worked example. It is also the cheapest proof left - the slave is testbench code, so it needs no RTL change | **adequate** |
| `isa: serialising op in commit slot 1` (`m11-INERT`) | A STIMULUS gap. No mutation can close it | **strong** |
| `sys: tohost ownership` | Unprovable by this harness: `SYS_MON` has one bundled `red_by` pattern that keeps `head -1`, so no campaign can distinguish it from `sys: the program's own verdict`. It is a testbench-convention check, not a design property | **weak, harmless** |
| `csr: reset value` | New with the register model. Every register reads its declared reset value; no mutation has been aimed at it. Its sibling `csr: read-only field policy` WAS closed, so this one is cheap and simply not done | **adequate** |
| 23 of the 31 anti-vacuous checkers | They fire on a disconnected monitor or a dead tap. No program can disconnect a monitor | **strong** |
| 86 STRUCT / INSTR / PROGARG / REF sites | No RTL change reaches them. Out of scope for both proof routes, per section 2 | **strong** |
| `csr: predicted value vs hardware` (the register-model mirror) | New DESIGN checker: `sb_csr` predicts every machine CSR from the retirement stream and compares. Demonstrably fires on a prediction gap, reads clean on the finished tree, and is left as a hypothesis because its intended `mret` mutation needs a full-battery escalation this host could not finish | **adequate** |
| **A hart dropping a MODIFIED line without writing it back** | The UVM environment still has no independent check: `check_backdoor`'s eviction inference is unconditional on what the model held, so a lost `M` line is absorbed exactly like a clean `S` eviction, and the load-value deferral is now gated on a real peer writer but remains one-way. One concrete instance was found by reading, a flush writeback capturing a same-cycle snoop's data, and is pinned by `tb_dcache_flush_snoop` at unit level. m23 is another instance of this class | **weak** |
| Formal verification, an SVA layer, an AXI VIP, >2 harts, 100% code coverage (319 of 2,082 line/branch points never execute) | Out of scope for this stage by decision. All four would be mandatory for a commercial sign-off on a coherent multicore, and none of them is a UVM gap | **strong for this stage, absent for sign-off** |

---

## 6. Two changes that were not bookkeeping

**The register model earned its place on the first mutation aimed at it.** `m13`
makes `mstatus.MPP` writable, breaking `csr_regfile.sv`'s WARL-zero rule. The
battery read `pass=86 fail=2` and both witnesses reddened, with their own words
and sharing no code:

```
uvm_csrprobe <- [SYS_MON] program reported ...   (csrprobe.S's own verdict)
uvm_ral      <- [RAL] hart 0: mstatus.mpp is declared RO with reset
```

`csr: read-only field policy` is proven. That is what a register model is FOR on
a core: the architectural rule is stated once, as an access policy, and the
check reads the policy rather than re-deriving the constant.

**`sb_coherence::check_swmr` was rewritten** to read the cache tag arrays
instead of the shadow model. It fires 179 times across 7 gates under m6. But the
claim around it was overstated in three ways, and the corrected version is worth
more than the original: *"could not produce a true positive"* is refuted by a
double grant reaching the model, which m8 is exactly; *"four mutations confirm
it"* is two, since m8 and m20 never sampled; and *"an INDEPENDENT witness"* is
not achieved, because `check_backdoor` runs first over the same harts at the
same instant and leaves model == tags unless it has already errored - so
**`check_swmr` cannot fire on a sample where `check_backdoor` is silent.** It is
a corroborating second voice on a failure the backdoor already reports, which is
worth having and is not what was claimed.

---

**These corrections changed documents and instruments, not the design.**
