# Defects and Meta-Lessons

A consolidated catalog of the defects found building this core and the
verification practices that emerged from them. The defects are grouped by
*shape* rather than by stage, because the recurring shapes are the actual
lesson: most bugs here are one of a handful of patterns, and recognizing the
pattern is what caught the later instances quickly. Each entry gives the
symptom, the root cause, what caught it, and the fix.

> **On documents named here that are not in this repository.** Some entries name
> the working documents of the verification stage - `SESSION_BRIEF.md`,
> `VERIFICATION_STATUS.md`, `REMAINING_WORK.md`, `CHECKER_INVENTORY.md` and
> others. Those were session-scoped and are not published. Where an entry names
> one, it is describing **a defect that document contained, or a claim it made
> at the time** - a historical account, accurate as such. Renaming the subject
> would falsify the record, so the names stand. The current statements of the
> same facts live in `verification.md` and in `README.md`'s figures block.

The design has six stages and the verification environment is the seventh.
Stages 1-5 are single-core; Stage 6 adds the dual-core MESI coherence material
(classes 7 and 8, and additions throughout). The grouping held up across that
boundary, which is itself evidence for it: the coherence blockers were mostly
*old shapes in new places* --- an event-vs-level handshake, a false-green
harness, a checker that could not fail --- and the two genuinely new shapes
(permission/ownership, and circular dependency) each recurred twice within the
stage.

---

## 1. Speculation and recovery (the out-of-order class)

**Ghost completion (Stage 5, Gate A).** A load launched down a wrong path during
the recovery quiesce window and completed into a ROB entry that recovery had
already squashed. Root cause: the load-store queue's launch signals were not
gated by the recovering state, so a load could go in flight the same cycle the
quiesce logic sampled the memory FSM idle. Caught by a fresh compiled-C audit
(a bubble sort) that no directed test, the retired twin, or randomized
instruction streams had exercised. Fix: a `recovering` input on the LSQ, ANDed
into both launch paths; the store drain was deliberately left ungated.
Counter-proved by a test that fails by name on the un-gated RTL.

---

## 2. Event versus level (the frozen-pipeline class)

Five separate Stage-4 defects share one shape: a signal that means *this is
happening* is read by a consumer that means *this happened*. While the producing
stage runs, the two are indistinguishable; while it is frozen by a stall, the
level-held signal re-announces the same event on every frozen cycle.

The instances were: the branch predictor's speculative update pushing the same
return address repeatedly while the fetch address was held; branch resolution
retraining the predictor once per frozen cycle; the flush counter reporting 124
events against 112 actual mispredicts; the fetch queue re-flushing on a
persistent redirect and destroying the repair fetches it had just issued; and
instruction retirement counting a single fence hundreds of times. The last was
visible only because a fence *holds* the writeback stage while a memory stall
*drains* it to bubbles --- holding is what exposed the latent hazard the drains
had hidden. The standing rule adopted: any redirect, train, count, or commit
signal sourced from a freezable stage gets an advance-gate by default.

Stage 6 supplied the INVERTED case, requester -> ordering point rather than the
other way round. `coherence_mgr` pulses `cmp_valid` in `O_CMPL` and only begins
sampling `req_installed` the NEXT cycle, in `O_HOLD`. The fill path satisfied
that by accident, because `D_FILL` is entered after completion and lasts several
cycles; the Upgrade path reported from `(D_UPG_WAIT && coh_done)` --- the SAME
cycle as `cmp_valid` --- so the pulse was gone before `O_HOLD` looked, and the
cluster deadlocked at 33 retirements (S6-6.7/2.7e). Fix: an explicit
`D_UPG_DONE` state so the report lands in the window the consumer watches.

---

## 3. Latency-exposed (the parameter-sweep class)

**Fetch duplication (Stage 4).** The fetch path advanced its address on grant; a
fetch granted while the address was frozen by a stall left that address still
offered after its response was consumed, and nothing stopped it being granted
and delivered a second time --- so the instruction retired twice. At zero
latency the duplicate happened to align with a buffer release that discarded it;
at any latency of two or more it was delivered. Caught by sweeping memory
latency. Fix: a fetch queue with an address generator that advances per accepted
request and registered-occupancy backpressure --- which also dissolved the
program-counter-as-fetch-address fiction that made freezing it seem natural.

---

## 4. Verification-harness defects (the false-green class)

These are the most dangerous, because a broken check reports success. They are a
class, not incidents, and the lesson is to never trust a harness verdict without
confirming it can fail.

- **The verdict grep could not see two testbenches (S6, late).** The battery scored a
  TB as PASS unless its log matched `FAIL|%Fatal|Assertion failed|%Error`.
  `tb_mesi_coh` ends `TB_MESI_COH BROKEN` with `17 checks, 7 error(s)`, and marks
  failures `[BAD ]` --- none of which match. It had been RED for an unknown
  number of sessions while the battery reported green, and `tb_race_directed`
  was silently broken the same way. This is the same shape as the %Fatal-as-pass
  defect above, which is the point: **a per-TB verdict word is only as good as
  the grep that reads it.** Fix: added `BROKEN`, `[BAD `, and lowercase
  `error(s)` to the pattern.
- **A gate counted twice (S6-3.6).** Two byte-identical blocks both ran
  `./run_xbar.sh` and both incremented the pass count, while the comment on each
  said *"21 directed + 2 random configs count as ONE gate."* The battery total
  was inflated by one and had been for some time. Found the first time a gate
  ROSTER was printed --- a total cannot reveal a duplicate, an enumeration can.
- **A probe that never compiled (S6-6.11).** An onset probe indexed `g_hart[h]` with a
  loop variable inside a hierarchical reference, which Verilator cannot
  elaborate. It never built, so it never emitted a line --- and "the probe didn't
  fire" reads exactly like "no bug here". The silent-no-op trap, in the
  testbench rather than the RTL.
- **A checker validated only against a BAD run (S6-6.10).** `SC-ON-UNOWNED-LINE`
  read 48/43, was believed, and produced a published conclusion --- "91 of 128
  successful SCs fired on a line the hart did not own" --- that was later
  WITHDRAWN. The SC acquires the line as part of its store, so the metric was
  measuring normal behaviour; a passing baseline would have read non-zero too.
  **An invariant never shown to hold on a known-good run is a hypothesis, not an
  invariant.** The same discipline applied later caught a real over-sensitivity:
  the first cluster SWMR checker read 1609 violations on a run whose invariant
  HELD, because it sampled in-flight transients rather than settled state.
- **A reference model that had stopped, reported as keeping up (UVM stage).**
  `spike_dpi.cc`'s `spike_step()` returned 1 whenever the hart existed and no
  C++ exception escaped --- it never asked whether Spike had executed anything.
  Both its own header and `ref_spike.sv`'s insisted the return value must be
  truthful; neither was implemented. On `mh.hex` both harts end in
  `crt0_multihart.S`'s park loop (`wfi ; j -4`), which the DUT retires forever
  because it decodes `wfi` as a NOP, while Spike parks with its pc frozen
  (`decode_macros.h` advances the pc then throws `wait_for_interrupt_t`;
  `execute.cc` re-throws before the fetch on every later step). Against a DUT
  alternating `wfi`/`j`, a frozen reference **MATCHES HALF THE TIME**: the run
  reported ~160 errors on ODD orders only, and the even ones were counted as
  successes against a reference that was dead. Fixed by testing
  `is_waiting_for_interrupt()` before and after the step. Three lessons, all
  earned: **(a)** the obvious counter was the wrong instrument --- `minstret`
  bumps on the parked step too (`n = ++instret` in the catch), so reading it
  would have confirmed the bug rather than found it; **(b)** a checker producing
  *matches* while its oracle is dead is worse than one producing errors, because
  errors get investigated and matches get counted; **(c)** the errors were all
  AFTER the tohost store --- the program had already finished --- and eight
  months of "the `wfi` diverges" was really "nobody checked what was at that
  address". The address was `park_forever`, and `run_rvfi_dual.sh` had solved
  the same problem years earlier by cutting both traces there.
- **A MUTATION CAMPAIGN THAT COULD NOT PRODUCE A MISS (UVM stage, step 7).**
  Step 7 grades a checker by breaking the design and requiring the checker to go
  red. Grading each mutation with the full battery is ~60 minutes, so a FAST
  path was added: build once, then run only the gates the mutation is predicted
  to redden. Its red-detector included

      grep -qE "UVM_ERROR.*\[(COV_LRSC|COV_COH|COV_ISA|SYS_MON)\]"

  which also matches the **anti-vacuous** errors -- `COV_LRSC: NO LR executed`
  on a program with no atomics, `SB_COH: only 9 quiescent samples` on a short
  one. Those fire on CORRECT runs BY DESIGN; it is exactly why `uvm_gate` refuses
  to gate on `UVM_ERROR : 0` and uses an allowlist of specific messages instead.

  So the very first mutation reported **CAUGHT** on a run whose own verdict read
  `252 compared, 0 mismatches`, and the campaign would have reported all sixteen
  the same way: a step-7 result of 16/16 that measured nothing.

  The tell was small and it was in the output: the red list printed
  `uvm_base uvm_base`, twice, because the expectation and the control were both
  "firing". A control that fires is not a control.

  **THE SHAPE IS THE WORST ONE IN THIS FILE, AIMED AT THE INSTRUMENT MEANT TO
  DETECT IT.** Step 7 exists because a green suite that cannot fail is worth
  nothing; a mutation campaign that cannot report a miss is that same defect one
  level up, and it would have retired the whole question with a perfect score.

  Fixed by matching the battery's exact patterns rather than its error IDs --
  and, more importantly, by adding the step that was skipped: **the grader is now
  required to read GREEN on the UNMUTATED design before any mutation is graded
  with it.** That is `SC-ON-UNOWNED-LINE` again (S6-6.10: a metric believed on a
  bad run, published as a root cause, withdrawn), and this file's own rule --
  *an invariant never shown to hold on a known-good run is a hypothesis* -- was
  written for it. Six gates now run unmutated first, and the campaign refuses to
  start if any reads red.

  Second lesson, about the FAST path itself: a fast grade can only ever save time
  on a CAUGHT mutation. A mutation that survives it is escalated to the full
  battery automatically, because "the named gates did not catch it" and "the
  battery did not catch it" are different claims -- which is the ambiguity m4 was
  recorded for, and a shortcut that blurred them would have re-created it.


---

## 4z. THE UVM STAGE'S OBSERVATION-CHANNEL DEFECTS

Eight defects found during the UVM stage, all of one shape.

> **This section used to reference rather than copy.** The detailed accounts
> lived in `VERIFICATION_STATUS.md`, and the reason given was the rule
> this project earned six times over: *one authority per fact*, because two
> copies of one thing drift and the second drifts silently. That working
> document is not published with the repository, so the accounts are inlined
> here instead. The rule is not violated - there is still exactly one copy.

What matters is the SHAPE each one taught, and those are already in sections 4
and 6 above. The eight, in one line each:

| defect | shape it taught |
|---|---|
| `rvfi_trap` tied to `1'b0` since it was written | a dead OUTPUT: computed and never brought out. Fifth instance |
| `trp_clr` tied to `1'b0` | same, and the battery read 56/0 through both for a whole phase |
| `mret` reporting `pc+4` instead of `mepc` | an observation channel nothing consumed |
| every store reporting `wmask=1111` | same |
| the FIRST store losing its record to a double registration stage | same |
| a failed SC reporting a store it never made (31 witnesses) | same |
| `rvfi_intr` on every dual-issue slot-1 retirement (45 of 45) | same |
| store and forwarded-load data in the wrong byte lane | 2d-3/2d-4, and the coverage axis that would have seen it did not exist |

**ALL EIGHT WERE INVISIBLE TO A GREEN BATTERY**, because none of them changes
what the CPU computes -- they change what it REPORTS, and nothing read the
reports. That is the single most useful sentence the UVM stage produced, and it
is why step 12 (plumb the channels) had to come before step 9 (gate on them).

**DEFECT 3 HAS NO WITNESS AND CANNOT HAVE ONE HERE**, which is worth stating
plainly rather than leaving it to look like the others. Spike's commit log
stores `reg_from_bytes()`, also right-justified, so the DUT and the reference
AGREED and no run could separate them. It was found by having to write a
CONSUMER -- comparing the field forces the question "which bytes?", and no
answer was consistent with both a lane-positioned mask and right-justified data.
Settled against CVA6, which implements RVFI and does both halves:
`be_gen_32(vaddr[1:0], size)` for the mask and `data_align(vaddr[2:0], data)`
for the data, under the comment *"re-align the write data to comply with the
address offset"*.

The comparison now uses the lane mask on both sides, so it still cannot catch
this defect returning -- all three parties agree on the correct convention where
they used to agree on the wrong one -- but it CAN catch one of them moving
alone, which is what a regression looks like.

**A defect that no run can witness is not a defect you find by running.** It is
one you find by building the thing that has to have an opinion.

## 5. Coverage gaps (the untested-path class)

**Misalignment computed and discarded (Stage 3).** The load-store unit computed
misalignment exceptions that were then left unconnected --- correct-looking RTL
with a dead output.

**The litmus suite cannot detect a stale sharer (S6-3.6).** Mutating the C1
table's `S + Snoop-GetM -> inv` cell --- a sharer that answers a remote GetM but
KEEPS its copy --- turned six gates red, but **`litmus` was not among them.** It
passed with the coherence protocol visibly broken. The reason was already
recorded in the runner: MP/SB/LB are herd-Allowed in ALL FOUR states, so *"they
can never fail and serve as coverage, not as gates"*, and the three Forbidden
tests in the suite do not exercise a stale sharer. The suite is a
memory-**ordering** oracle, not a coherence-**violation** detector, and the
stage plan had assumed otherwise. Only 3 of the 24 Forbidden variants are
implemented; this is the argument for the other 21.

---

## 6. Reading-the-instrument errors (mistaking the measurement for the thing)

Recorded because they were real detours and the lessons generalize.

**"N matched" is not an instruction count (S5-I.6).** The trace comparator
reported "31,035 matched"; I briefly read that as the program's instruction count
and suspected the RTL was over-emitting when it produced ~49,877 retirements. It
was not: 31,035 is the post-filter state-change count (register writes, minus
same-value rewrites, dropped symmetrically on both sides). The true totals agree
--- both machines produce identical register-write counts and identical totals
to within the halt boundary --- and the perfect-memory harness emits the same
figures. A comparison statistic is defined by its filters, never assumed to be
the raw count.

- **A VERDICT MUST BE COMPUTED FROM WHAT RAN, NEVER FROM THE ABSENCE OF
  FAILURES (UVM stage, phase E).** Three guards written in one session to catch
  the false-green class each shipped with a path that PASSED ON NOTHING:

    `docs_audit.sh`        the CURRENT FIGURES block deleted -> green, zero
                           figures checked
    `antivacuous_proof.sh` the VACUOUS class reclassified away -> green, zero
                           checkers examined
    `audit_selftest.sh`    every case skipped -> green, zero cases run

  All three had the same shape and none was found by writing them; each was
  found by someone asking, afterwards, "what does this do when its input is
  empty?" **That question is not the same as "does it work"**, and hand-testing
  answers only the second.

  The fix is not "check for empty" -- that is the symptom. It is that a verdict
  computed as `if (no failures) pass` is wrong whenever "no failures" and "no
  attempts" are the same state, which is most guards. Compute the verdict from
  the POSITIVE count: `docs_audit` has `MIN_DECLARED`, `antivacuous_proof` has
  `MIN_VACUOUS`, `audit_selftest` refuses at `pass == 0` and reports PARTIAL
  when anything was skipped.

  Fourth, fifth and sixth instances here after the mutation grader that could not
  report a miss, the dead-line pre-flight whose grep matched zero records, and
  `gate_criteria_check`'s extractor -- which caught ITSELF by having the clause
  the other three lacked. **The one guard that had the check is the one that
  survived its author's refactor**, which is the whole argument for writing it
  first.


---

## 7. Permission and ownership (the coherence class)

Every S6 blocker that resisted for more than one session turned out to be a
*missing or mis-timed permission*, not a protocol-table error. The C1 table was
right almost every time; what was wrong was who was allowed to write, and when.

**LR was not write-intent (S6-6.10).** Six sessions of reservation-side and
ordering-side hypotheses failed because the bug was in neither place. rocket's
`Consts.scala:91` puts `M_XLR` in `isWriteIntent`, and `Metadata.scala`'s
`growStarter` makes an LR on a Shared line a miss that grows BtoT --- **an LR
cannot leave the line Shared.** Our dcache had no `is_lr` port at all, so an LR
issued GetS and parked the line in S; the SC then stored into a line both harts
held shared, and increments collapsed. The measured symptom
(`SCST h1tag=LINE_S h0tag=LINE_S`) was visible for sessions before the missing
*category* was recognised. Fix: `wintent = we || is_lr` plumbed to the dcache,
LR issues GetM and installs E.


---

## 8. Circular dependencies (the ring class)

Twice, a fix could not be placed *anywhere* because the constraints formed a
cycle. Recognising the shape is what ended each search; hunting for a better
point inside the ring is what wasted the sessions before it.

**S6-6.8.** complete -> commit -> release -> drain -> verdict -> complete.

**S6-6.10.** The SC's verdict had to be taken where the line was writable; write
permission was only requested by the store; the store was gated behind the
verdict. Four repairs failed in four different directions before the ring was
stated: *any verdict instant late enough to guarantee write permission is
downstream of the store, and the store is downstream of the verdict.*

The resolution in both cases was not to find a point inside the ring but to
**remove one of its edges.** For 6.10 the edge was removed one level up, by
making the LR acquire permission --- after which the previously-deadlocking
"verdict at the grant" repair simply worked, because the SC no longer needed an
Upgrade at all. A fix that failed earlier is worth re-testing after the frame
changes.

---

## 9. CPU defects the instruments could not see

A close read of the design, rather than a run, found CPU defects in exactly the
places sections 4 and 4z predicted an instrument would be blind. Each is listed
with the shape it belongs to and the fix that landed with it.

- **Upgrade loses its line (class 7).** A store's Upgrade waited at the ordering
  point while the peer's GetM, ordered first, invalidated the line. On
  completion the cache installed M over the stale data array. Fix: `dcache.sv`
  latches `upg_lost` and turns a lost Upgrade into a fill. Test:
  `tb_dcache_upg_race`. Why nothing saw it: litmus reads registers, the Spike
  comparison deferred shared loads, and the coherence scoreboard tracks state,
  not data.
- **Flush writeback captures a snoop's SRAM read (class 7, and the `none` row
  in verification.md).** A dirty snoop in the same cycle as the flush scan's
  writeback read wins the data-array port, so the writeback carried the snooped
  line and the victim was marked clean. Fix: a snoop does not start on a
  writeback-read cycle. Test: `tb_dcache_flush_snoop`.
- **Two address domains (class 6).** The caches saw 18-bit addresses and the
  LR/SC unit saw 32-bit ones, so the protection window compared unequal values
  forever and the CLINT could not be addressed by software. Fix: one address
  domain end to end, `is_mmio` decodes only the CLINT window, and the crossbar's
  decoder does the split. The gate-roster comment for `uvm_lrsc_conflict` had
  already recorded the block as never taken.
- **Prediction dropped on every I-cache miss (class 2, event versus level).**
  The BTB's hit was gated by a one-cycle read pulse while the fetch queue
  sampled the prediction when the line arrived. Fix: `bp_top` holds the
  prediction until the next read; the BTB keeps its valid bits in flops and
  clears them on `fence.i`. Expect the mispredict column of `results.md`
  section 2 to fall on miss-heavy programs when re-measured.
- **Stale BTB entry after self-modifying code (class 5).** A non-control-flow
  instruction predicted taken was never detected. Fix: it retires, everything
  younger is walked, fetch resumes at pc+4, and the entry is invalidated.
- **Architectural surface (class 6).** Interrupt priority was MEI, MTI, MSI;
  `misa` omitted M; `mstatus.MPP` read 00 in a machine-only core and the
  register model enshrined it; CSRRS with a zero-valued rs1 skipped the write
  attempt; `time`, `mcountinhibit` and the mhpm range trapped; `mie` kept
  unimplemented bits; reserved MISC-MEM encodings decoded as fences. All fixed,
  with `csrprobe.S` and the RAL updated.
- **Bus errors were data.** The adapter ignored RRESP and BRESP. They now reach
  the core as instruction and load access faults; a faulted fill is not
  installed.
- **A memory load landing on a held completion skid (class 1).** A forwarded
  load waits in the one-entry completion skid while a run of independent
  multiplies holds the writeback lane, and `ld_go` launched the next memory
  load regardless. Its response overwrote the skid, the forwarded load never
  completed, and the core hung at it. 51 of 80 random load, store and multiply
  programs hung on a perfect-memory core. Fix: `ld_go` requires an empty skid;
  forwarding already requires an idle memory FSM, so nothing can refill it
  before the response lands. Why nothing saw it: the directed M tests are short,
  the random gate runs eight seeds, and the cluster programs use soft multiply.
- **A divide finishing under a CSR or SC completion (class 1).** Completion
  lane 0 prefers an SC verdict, then a CSR at the head, then the divider, but
  the divider advanced on `done` regardless of who took the lane. A divide that
  finished in the cycle a CSR executed at the head was consumed and never
  written to the ROB. Fix: the divider advances only when lane 0 takes it.
  Both this and the item above were found by reading `core.sv` and confirmed by
  directed programs; the fixes were checked against the ctest retirement trace,
  which did not change by a single entry.
- **A faulted store fill retried forever (class 8, the ring class).** A
  retired store cannot fault, so the cache retried its fill on every SLVERR.
  Against a persistent fault that never ended, and because the ordering point
  keeps the line busy until the requester installs, the other hart's requests
  to that line waited behind it. Fix: `dcache.sv` retries a faulted store fill
  fifteen times, then completes without installing, which drops the store and
  releases the line. The loss is not architecturally visible; a precise store
  fault would need the store to wait for its fill before retiring.
- **An LR during the back-off restarted the back-off (class 8).** After an SC,
  or after an intervening access, a hart backs off for eight cycles before it
  may reserve again, and every LR that arrived inside those cycles reset the
  count. A retry loop whose LR-to-LR period was under eight cycles could never
  re-acquire. Latent today because the SC path is slow. Fix: `lrsc_unit.sv`
  lets the back-off run down under an LR; the LR gets no reservation, its SC
  fails, and the next LR after the back-off succeeds. Test: `tb_lrsc_unit`.
- **LR.W with rs2 != x0 decoded as a normal LR (class 6).** The encoding is
  reserved. Fix: `decoder.sv` marks it illegal. Test: `tb_decode_lrsc`.
- **The crossbar waited for AWREADY before driving WVALID (class 8).**
  `wr_port_ctrl.sv` released W beats only after the AW handshake, which AXI4
  A3.3.1 forbids because a slave may wait for W before accepting AW; the two
  would deadlock. None of the attached slaves does. Fix: W beats flow once the
  AW is presented, and a burst that finishes ahead of its AW is remembered so
  the owed-beat count cannot underflow and no second burst runs ahead.
- **A speculative LR opened the reservation window (class 1, and the worst
  of this batch).** Any LR that launched opened or renewed the window, including
  an LR younger than a pending SC or on a wrong path. Hart 0's write snooped
  hart 1 and cleared its window; two cycles later hart 1's next-iteration LR,
  fetched past the SC that had not yet executed, launched and reopened it; the
  older SC then succeeded on stale data and one increment of `stress.c`'s
  counter was lost. Reachable at three of eight memory latencies on the tree
  with the completion-skid fix, and hidden by timing on the tree before it.
  Fix: an LR launches only when it is the ROB head with every committed store
  drained, and never takes its value by forwarding, so the window always
  belongs to the LR the next SC pairs with. Found with an LR/SC retirement
  trace on `tb_dual_ooo`; the checks that should have seen it read only
  cache state and SC counts, and both were consistent with the lost update.
- **An SC drained before it executed (class 1).** `hs_drain` launched the
  store-queue head as soon as the SC was the ROB head, without checking that
  the SC had filled its address. An SC dispatched into an empty ROB, which any
  I-cache line boundary just before it produces, is the head at once and went
  out with address zero; the cache then filled line zero, which decodes to the
  CLINT slave, and the word slave's burst assertion ended the run. Reproduced
  in the first iteration of a plain LR/SC loop at every memory latency. Fix:
  the SC path of `hs_drain` requires `addr_known`. Why nothing saw it: the
  committed programs happen to have their SC and the instruction before it in
  one fetch line, so the SC never reached the head before its fill.
- **An SC squashed after performing its store (class 1).** A timer interrupt
  recognised while an SC was at the head let the SC finish its store during
  the quiesce and then walked it, so it re-executed as a failure with the
  store already in memory. Fix: `trig_irq` waits while the head is an SC,
  which the SC's own actor path then commits, and `sc_head_go` requires
  `recovery_idle` so no SC store starts inside a recovery. Test: a timer
  interrupt every few ticks over an LR/SC loop that reloads the word after
  every failed SC.
- **Stale `sc_is` and `lr_is` bits on slot-1 allocations (class 5).** Both
  arrays were written only for dispatch slot 0, so an op allocated in slot 1
  inherited the bit of the entry's previous occupant. A stale `sc_is` at the
  head fired `trig_actor` and flushed the pipeline for an ordinary ALU op, and
  raised `sc_head_go` for a younger SC still in the store queue. Fix: slot 1
  clears both, as `refetch_is` already did.
- **The snoop search matched one word of the line (class 8, the width
  class).** The load queue compared bits 31:2 of a load's address with the
  snoop address, and the snoop carries the line base, so an executed load to
  words 1, 2 or 3 of an invalidated line was never squashed. A directed test
  with the older load's address held back by a divide and the peer storing
  showed 454 same-address load reorderings at word offsets 4, 8 and 12 and
  none at offset 0. Fix: the compare is line-granular and the byte-mask port is
  gone. `tb_lsq_snoop` had used a word-0 address and passed.
- **The snoop search flagged the head load, and livelocked (class 8, the ring
  class).** The same search flagged any executed load, including the oldest
  one, and a load still waiting on the cache. With a peer keeping a store
  queued at the ordering point, that store is ordered the cycle our fill
  releases the line and its snoop lands one cycle after our data, between the
  head load completing and committing; the load was squashed, refetched,
  missed again, and the ring closed. The same directed test at offset 0 timed
  out on the tree before the width fix, so the ring predates it. Fix: a load
  is flagged only when its value is bound and an older load's is not, which
  is the only shape a same-address reordering can take; the oldest in-flight
  load and a load still waiting on the cache are never flagged.
- **The stress verdict was a race (class 4).** `stress.c` returned each
  hart's own read of the shared counter and the runtime ORed the two, so the
  expected exit code assumed hart 0 read the counter after hart 1's last
  increment. The tree before the fixes above already returned 127 from hart 0
  at zero memory latency; the gate passed on timing. Once the snoop search
  stopped squashing the head load, hart 0 finished first under the UVM
  latency model and reported 120 with the counter at 128 and zero Spike
  mismatches. Fix: each hart waits, bounded, until the counter reaches
  `ITERS * NUM_HARTS` before returning, so the verdict is the final count.
- **An Upgrade decided in the cycle its line was taken (class 7).** The
  D-cache picks the Upgrade path from `upg_needed` in `D_IDLE`, and a snoop
  that invalidates the same S line in that same cycle is applied to the tag at
  once, but the `upg_lost` latch that turns a lost Upgrade into a fill listens
  only while the Upgrade is already pending. So a store or LR whose request
  first meets an idle cache in the very cycle the peer's GetM or Upgrade snoop
  lands went out as an Upgrade for a line the cache no longer held, and on
  completion the cache set the way to M over the stale data array. The peer's
  words in that line were lost; the peer read its own counter stepping back
  after our next snoop response or writeback carried the stale line. Reached
  by two harts counting in different words of one line at every memory
  latency (`upg_race`, `fence_race`, `bytes_race`; the byte-lane program fails
  inside 1300 cycles), and never by the committed gates because their
  contended lines are LR/SC words that the SC path serialises. Fix:
  `upg_needed` is masked by a same-cycle invalidating snoop on the requested
  way, so the request re-arbitrates next cycle as an ordinary GetM miss. Why
  nothing saw it: the SWMR check reads the two tag arrays only when both
  caches and the ordering point are idle, and at that instant one M copy over
  stale data looks exactly like a legal M copy.
- **A line fill to an address that is not memory (class 6, the address
  class).** The caches treated every address outside the CLINT window as
  cacheable and asked the crossbar for a four-beat line, and the crossbar
  routes the whole low prefix to the word-granular CLINT slave, which can
  answer one beat. A wrong-path load reaches that path from a correct program:
  a pointer that is usually valid and once null, guarded by a branch the
  predictor has learned, issues its load with address zero before the branch
  resolves, and the burst ended the simulation at the slave's assertion (in
  silicon the slave would return one beat against a four-beat burst, an AXI
  violation). A jump or an architectural load to a low unmapped address did
  the same, where the design raises an access fault for every other unmapped
  prefix. Fix: `mem_pkg::is_ram` names the one region a line may target;
  under the `line_ram_only_i` input, which only `cluster.sv` ties high because
  only its crossbar has that decode, `dcache.sv` answers a cacheable access
  outside it with a load access fault from a new `D_BAD` state and never
  fills, and `icache.sv` returns the fetch as an instruction access fault
  without a line request. The single-core system keeps its low-address map.
  Stores to such addresses are dropped, as a faulted store fill already is.
  Tests:
  `null_spec` (the guarded null pointer, dual-hart) and `badjump` (jump, load
  and store to low and high unmapped addresses with cause and tval checks).
  Why nothing saw it: every committed program keeps its pointers in RAM, and
  a wrong-path address only exists between issue and squash.
- **The instruments (class 4).** The retirement scoreboard patched Spike with
  the DUT's load value whenever only the load differed, up to fifty times, even
  when the word the DUT read agreed with the reference. It now defers only when
  the word differs and another hart has stored to that line. The reference saw
  interrupts rise and never fall. Gates read counters and not the verdict's
  termination line. `asm_fresh` compared mtimes, which git does not keep. All
  fixed; `+REF=1` re-enables the reference on the one interrupt test that ran
  without it.

## 10. Later microarchitecture changes

Not defects: deferred items from section 9, done once the battery was green
again, each with the instrument that watches it.

- **Out-of-order loads.** `lsq.sv` picks the oldest load that has its address
  instead of the oldest load, so a younger load no longer waits on an older
  one's operands. The store-fill and snoop violation searches were already
  written against per-entry state; only the pick and the in-flight index
  changed. Watched by the Spike comparison and `tb_lsq`.
- **The ordering point releases at completion.** `coherence_mgr.sv` keeps a
  busy line per hart from grant until that hart installs, and orders requests
  to other lines meanwhile. A snoop is now held until the cache acknowledges
  it, so a refused cycle can no longer drop one; `cluster.sv` turns the held
  snoop into a one-cycle pulse for the load queue. `snoop_monitor` tracks one
  pending install per hart and errors on a second grant to a busy line or a
  busy hart. `tb_coherence_mgr`'s mock responder had modelled the pulse and
  was rewritten to the hold contract.
- **A real register-model mirror.** `sb_csr.sv` predicts every machine CSR
  from the retirement stream (CSR instructions, traps, interrupts, `mret`) and
  checks each CSR read value and the final back-door value against it;
  `cpu_ral_test` now seeds its mirror from that prediction instead of from the
  value it just read. The checker is demonstrably not silent: while it was being
  brought up it fired on every real prediction gap, including `mstatus.MPP`
  reading 11 where a draft model still expected 0, and it reads clean (0
  `[SB_CSR]` errors) on the finished tree. It is classified DESIGN and left
  unproven by a mutation: a `mret`-clears-MPIE mutation is the intended proof,
  and it needs a full-battery escalation this host had no disk to finish.
- **A registered execute stage.** Select and execute were one combinational
  cycle: issue-queue pick, register-file read, ALU, branch resolve and
  write-back between two edges. `core.sv` now latches the selected ops and
  executes them the next cycle. A single-cycle ALU op wakes its consumers when
  it is selected, so dependent instructions still issue back to back; a load,
  multiply or divide wakes them at completion as before. The stage holds while
  a CSR, divide or SC owns completion lane 0, and an op loaded behind a
  mispredicted branch is dropped unexecuted rather than started. Cost on the C
  program at DELAY=10: 56,975 to 59,103 cycles. The change exposed a fetch
  queue hole the battery had never reached (class 2, event versus level): a
  recovery redirect arriving in the cycle a pended redirect was being applied
  hit a `$fatal`; the younger redirect now wins.

- **The mutation grader could not start on the published tree (class 4).**
  `run_mutations.sh`'s pre-flight proves the dead-line detector can tell DEAD
  from LIVE by reading four fixed RTL line numbers out of the coverage union.
  One of them, `lrsc_unit.sv:237`, is past the end of a 106-line file: the
  numbers date from before the comment strip that preceded publication. The
  pre-flight therefore refused every campaign on the tree as shipped, which
  is the correct behaviour for a self-test and the same stale-artefact shape
  as the citation drift in section 4. The four lines are now re-derived from
  the current tree and named by their code in the script.

## Meta-lessons (the verification method that emerged)

1. **Retirement-sequence comparison** finds what pass/fail tests cannot: the
   correct instructions in the wrong order or the wrong number of times.
2. **An independent reference model beats a second implementation.** Comparing
   every retirement against a reference ISA simulator is stricter than comparing
   against a second in-order core, because a shared misconception cannot survive
   it. This is why the in-order twin was retired as an oracle.
3. **Parameter sweeping is not optional.** Three distinct defects existed only
   off the default configuration. A suite that exercises only defaults tests
   only the default.
4. **Width is a parameter to sweep.** Width does not add new logic so much as it
   reaches into logic that was correct only because width one could not test it.
   Rebuild and re-measure at every width.
5. **Closed-form attribution.** Assert that a cycle count equals a formula whose
   terms are read from hardware counters, not that it equals a plausible number.
   A count that looks right still fails if its components do not account for it.
6. **Survey the reference cores before writing RTL.** Repeatedly, minutes of
   reading RSD, BOOM, Ibex, or CVA6 overturned an approach or surfaced a defect
   not yet observed. The unified-PRF choice, the fetch-queue redesign, and the
   per-slot commit guard all came from the survey.
7. **Adversarial workload class as an exit rule.** No stage closes until it
   survives a class of programs it was not tuned for. Compiled-C workloads found
   the two hardest Stage-5 bugs after directed tests, the twin, and randomized
   streams had all passed.
8. **Never trust a harness verdict; prove it can fail.** False greens are a
   class. Seed the data, remove stale logs, rebuild per configuration, and treat
   a %Fatal as a failure.
9. **Predict before measuring, and record the prediction.** A wrong prediction
   is the most informative outcome; the chase control being flat is worth as much
   as the memory curve moving.
10. **Record full invocations.** A measurement whose exact command is not written
    down is not reproducible, and IPC data that lives only in a terminal is lost.
11. **Every punt ships with a counter.** Partial-overlap forwarding, the blocking
    cache, snapshot exhaustion --- each deferral carries a measured number, so the
    next stage's motivation is quantified rather than asserted.
12. **Survey the reference BEFORE writing RTL, and AGAIN the moment you are
    stuck.** The trigger is the SECOND identical failure, not the fifth. Stage
    6's three biggest wins came from survey; its two worst time sinks came from
    surveying late. Sometimes the reference does not hand over a patch but tells
    you your design carries a REQUIREMENT theirs sidesteps structurally --- which
    is still the useful answer.
13. **Verify the edit landed before interpreting its result.** `grep -c` the
    marker immediately after every edit. Several edits during the S6 coherence work were silent
    no-ops from unmatched anchors, and their "results" were nearly taken as
    evidence.
14. **Validate a checker against a KNOWN-GOOD run before trusting it on a bad
    one.** A metric that has only ever been read on a failing run is a
    hypothesis. This is the single most expensive lesson in the catalogue: it
    produced a published, confident, and wrong root cause that had to be
    withdrawn.
15. **Enumerate gates; do not count them.** A total cannot show you a gate that
    VANISHED or one that is counted TWICE --- both happened. Print every gate name
    with its verdict, archive the roster, and fail on a change in roster size.
16. **Verify in proportion to the blast radius.** The corollary of the above, and
    the opposite error: after being burned twice by the apparatus, the instinct
    is to re-run everything after touching anything. That is not the lesson. The
    lesson is to check per-gate logs instead of trusting a summary --- quality of
    verification, not quantity. A comment edit needs a syntax check, not a
    fifteen-minute battery.
17. **A fix that failed may deserve re-testing after the frame changes.** The
    "verdict at the grant" repair deadlocked when it was first tried and worked
    unchanged once the LR acquired permission. Keep failed attempts, with a note
    on what each RULES OUT, precisely so they can be revisited rather than
    re-derived.
