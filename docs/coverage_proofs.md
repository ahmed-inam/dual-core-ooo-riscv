# 4d -- why the remaining bins cannot be hit

Step 4 is scoped as *every bin that CAN be hit IS hit by a program, and every bin
that cannot is PROVEN so*. This file is the second half. Each entry names the
RTL that forbids the bin, so the claim can be checked without re-deriving it.

**That citation is machine-checked.** `scripts/cite_audit.sh` (battery gate
`uvm_cites`) follows every citation to the line it names and fails if it has
drifted - which it had, for twelve of them, by up to 145 lines. The claims were
still true; the citations were not *checkable*, which is the whole of this
file's contract. An audit that reaches the right conclusion by re-deriving the
claim by hand does not test the artefact.

> A few entries name working documents of the verification stage -
> `CHECKER_INVENTORY.md`, `SESSION_BRIEF.md`, `REMAINING_WORK.md`,
> `COVERAGE_REVIEW.md`. Those were session-scoped and are not published here;
> where they appear, they are cited as the historical source of a claim made at
> the time.

---

<!-- BEGIN CURRENT FIGURES -- checked by scripts/docs_audit.sh -->
```
bins       763
hit        632
unhit      131
```
<!-- END CURRENT FIGURES -->

**THE THREE FIGURES ABOVE ARE CHECKED; THE PROSE BELOW IS NOT.** This file's
accounting table summed to 142 against a measured 129 for an unknown number of
sessions, and nothing in the repository could see it -- the document did not know
it was wrong and the measurement did not know it was being quoted. The totals
now sit in a declared block that `scripts/docs_audit.sh` diffs against
`cov_report.sh`, and they went stale AGAIN between two runs of this session
(751/630 against a measured 757/636) before that block existed.

## THE ACCOUNTING -- every unhit bin, in one table

The point of this file is that the denominator is CLOSED: no bin is left
unexplained. Sections below give the RTL for each row.

| group | bins | disposition | section |
|---|---|---|---|
| `cg_c1` | 45 | **proof** -- 36 by the requester-state rule, 1 by SWMR, 6 coverpoint-level, 2 by the `cmp_dirty` finding | 1 |
| `cg_mem_axi` | 13 | **proof** -- 6 `cp_len`, 3 `cp_lat` (a TESTBENCH property, see below), 3 DECERR, 1 illegal | 5, 7, 10 |
| `cg_memshape` | 10 | **proof** -- misaligned cells never reach the group | 3 |
| `cg_memshape` | 1 | **SENTINEL, not a proof** -- `cp_region.other`. Reachable; it must stay empty | 3a |
| `cg_trans` | 9 | **proof** -- E is unobservable on this bus | 2 |
| `cg_snoop` | 9 | **proof** -- 3 by `cmp_dirty`, 3 contradictions, `atomic_x_gets`, `cp_sn.none`, PutM | 10 |
| `cg_exception` | 7 | **proof** -- 6 encoding contradictions, 1 default arm | 8 |
| `cg_mstatus` | 6 | **proof** -- entry is defined as `!mie`, so 5 cells contradict; MPP is WARL-zero | 8 |
| `cg_window` | 4 | **proof** -- `sc_success` requires `rsv_valid`, so any SUCCESS paired with a dead reservation is impossible | 9a |
| `cg_branch` | 4 | **proof** -- a not-taken branch cannot be backward; misaligned targets trap | 8 |
| `cg_hazard` | 4 | **proof** -- a store and a branch write no register | 4 |
| `cg_onset` | 3 | **proof** -- the detecting instruction occupies a ROB entry | 10 |
| `cg_lsu_hazard` | 3 | **proof of the SAMPLER, not the design** -- `HZ_NONE` is never passed to `sample()` | 8 |
| `cg_distance` | 3 | **proof** -- the LSQ's LR->SC floor is exactly 4 cycles, derived and measured | 11 |
| `cg_interaction` | 1 | **proof** -- a back-off in the window guarantees that window's SC fails | 11 |
| `cg_occupancy` | 1 | **proof** -- commit is blocked throughout a mispredict recovery | 11 |
| `cg_onset`, `cg_occupancy` | 2 | **ONCE HIT, no proof** -- `full_x_violation` in both crosses; reachable, and no program forces it since the snoop search stopped flagging the oldest load | 11 |
| `cg_issue`, `cg_slot_class`, `cg_snapshot`, `cg_csr` | 4 | **proof**, one line of RTL each | 6, 8 |

    120 proven unreachable, with the RTL cited for each
      1 SENTINEL asserted unreachable and NOT -- cg_memshape.cp_region.other,
        which now has a procedural check behind it (section 3a)
    ---
    121 unhit, of 757.   636 hit.   make regression 91/0.
                         cov_bin_audit:   0 collapsed, 0 unexplained crosses.
                         cov_proof_audit: 0 unexplained, 0 stale roster entries.
                         code coverage:   2,082 points, 319 never executed.

    748 -> 745 is the HZ_NONE deletion (section 12); 745 -> 751 is the sign
    axes moving into cg_sign, because an `iff` on a coverpoint does not reach a
    CROSS of it on this tool (section 12). 621 -> 630 hit is
    cp_lat.immediate x3 becoming reachable once the bucket boundary was
    re-derived, plus two cg_interaction cells closed by asm/lrsc_conflict.S,
    less the cells the line-qualified snoop flag correctly stopped crediting.

**THE TWO OPEN BINS ARE CLOSED.** `cg_window.cp_kill.trap` and
`x_out_kill.failed_x_trap` are hit by `asm/lrsc_qtrap.S` -- section 9b. Every
`cp_kill` bin now has samples (none 211, snoop 23, trap 1, both 1) and
`cg_window` is 22 of 26 with the remaining four proven in 9a.

**THIS TABLE WAS WRONG IN FOUR PLACES AND IT IS WORTH SAYING HOW.** The previous
version added to **142** against a measured 129 in the paragraph beneath it, and
carried a fourth column -- "OPEN STIMULUS", 18 bins -- which is the category this
file says twice it will not have. Three rows described a state that had already
gone (`cg_irq_context` 10, closed at 100.00%; `cg_occupancy` 3, actually 1;
`cg_mem_axi`'s `long_lat_x_write`, closed by `cpu_wstall_test`) and one
mislabelled four proven bins as open (`cg_distance` 3 + `cg_interaction` 1). The
file's twelve SECTIONS were right throughout; only the index was stale.
A reader who trusted the table concluded 18 bins were unaccounted; a reader who
read every section concluded 2. **Nothing in the repository could tell them
apart**, because no check cross-referenced the two -- the same divergence as the
gate list versus the sweep list, which bit four times. That check now exists:
`scripts/cov_proof_audit.sh` and the roster below.

**AND ONE PROOF IS FALSE.** Section 1b claimed `upgrade_x_s_x_e` AND
`upgrade_x_s_x_m` unreachable by SWMR. `upgrade_x_s_x_m` is **HIT, 4 samples**,
on a union where `sb_coherence` reads 0 SWMR violations. The composition above is
corrected to 36 + 1 + 6 + 2; the old 36 + 2 + 5 + 2 summed to the same 45
because a second error cancelled it. See 1b.

**AND SIX ENTRIES NAME A TESTBENCH RATHER THAN THE RTL** -- `cp_lat.immediate`
and its two crosses (the latency WINDOW is `mem_monitor`'s and the floor is
`mem_driver`'s; no RTL forbids it), and `cg_lsu_hazard`'s three (the sampler
never passes `HZ_NONE`). Both are argued honestly where they appear and both are
filed under headings about the design. 4d's contract is *"each entry names the
RTL that forbids the bin"*, and six of them cannot.

## THE ROSTER -- the machine-checked half of the accounting above

The table is prose and explains WHY. **This block is the list**, and
`scripts/cov_proof_audit.sh` diffs it against the measured unhit set on every
battery run (gate `uvm_proofs`). Two directions, both failures: a bin unhit and
absent here is one nobody has explained; a bin present here and now HIT is a
proof the design has falsified, or one a program closed while the document went
on claiming it impossible. `upgrade_x_s_x_m` was exactly the second kind and no
check could see it.

It is a BLOCK rather than a grep of the prose because the prose says "3 `cp_lat`"
and "all six `x_lat_dir` cells" and never spells the cells out -- a name-grep
would have failed on its first run, and a guard that cries wolf gets deleted.
Same contract as `docs/gate_roster.txt`, for the same reason.

Regenerating is deliberate: `./scripts/cov_proof_audit.sh --regen <dat>`. **Read
the section before regenerating** -- the whole point is that a bin leaving this
list should require someone to notice.

<!-- BEGIN UNHIT ROSTER -- generated by scripts/cov_proof_audit.sh --regen -->
```
cg_branch.cp_tgt_align.mis[0]
cg_branch.cp_tgt_align.mis[1]
cg_branch.cp_tgt_align.mis[2]
cg_branch.x_branch.not_taken_x_backward
cg_c1.cp_r.putm_never_issued
cg_c1.cp_so.e
cg_c1.cp_so.reserved_o
cg_c1.cp_sr.e
cg_c1.cp_sr.m
cg_c1.cp_sr.reserved_o
cg_c1.x_c1.getm_x_e_x_e
cg_c1.x_c1.getm_x_e_x_i
cg_c1.x_c1.getm_x_e_x_m
cg_c1.x_c1.getm_x_e_x_s
cg_c1.x_c1.getm_x_i_x_e
cg_c1.x_c1.getm_x_m_x_e
cg_c1.x_c1.getm_x_m_x_i
cg_c1.x_c1.getm_x_m_x_m
cg_c1.x_c1.getm_x_m_x_s
cg_c1.x_c1.getm_x_s_x_e
cg_c1.x_c1.getm_x_s_x_i
cg_c1.x_c1.getm_x_s_x_m
cg_c1.x_c1.getm_x_s_x_s
cg_c1.x_c1.gets_x_e_x_e
cg_c1.x_c1.gets_x_e_x_i
cg_c1.x_c1.gets_x_e_x_m
cg_c1.x_c1.gets_x_e_x_s
cg_c1.x_c1.gets_x_i_x_e
cg_c1.x_c1.gets_x_m_x_e
cg_c1.x_c1.gets_x_m_x_i
cg_c1.x_c1.gets_x_m_x_m
cg_c1.x_c1.gets_x_m_x_s
cg_c1.x_c1.gets_x_s_x_e
cg_c1.x_c1.gets_x_s_x_i
cg_c1.x_c1.gets_x_s_x_m
cg_c1.x_c1.gets_x_s_x_s
cg_c1.x_c1.upgrade_x_e_x_e
cg_c1.x_c1.upgrade_x_e_x_i
cg_c1.x_c1.upgrade_x_e_x_m
cg_c1.x_c1.upgrade_x_e_x_s
cg_c1.x_c1.upgrade_x_i_x_e
cg_c1.x_c1.upgrade_x_i_x_i
cg_c1.x_c1.upgrade_x_i_x_m
cg_c1.x_c1.upgrade_x_i_x_s
cg_c1.x_c1.upgrade_x_m_x_e
cg_c1.x_c1.upgrade_x_m_x_i
cg_c1.x_c1.upgrade_x_m_x_m
cg_c1.x_c1.upgrade_x_m_x_s
cg_c1.x_c1.upgrade_x_s_x_e
cg_csr.cp_csr.other
cg_distance.cp_d.immediate
cg_distance.x_dist_snoop.immediate_x_quiet
cg_distance.x_dist_snoop.immediate_x_snooped
cg_exception.cp_cause.insn_fault
cg_exception.cp_cause.other
cg_exception.x_trap.exception_x_insn_fault
cg_exception.x_trap.exception_x_irq_soft
cg_exception.x_trap.exception_x_irq_timer
cg_exception.x_trap.interrupt_x_illegal_insn
cg_exception.x_trap.interrupt_x_insn_fault
cg_exception.x_trap.interrupt_x_insn_misaligned
cg_exception.x_trap.interrupt_x_load_fault
cg_exception.x_trap.interrupt_x_load_misaligned
cg_exception.x_trap.interrupt_x_store_misaligned
cg_hazard.x_hazard_class.war_x_branch
cg_hazard.x_hazard_class.war_x_store
cg_hazard.x_hazard_class.waw_x_branch
cg_hazard.x_hazard_class.waw_x_store
cg_interaction.x_atomic_snoop.write_intent_x_snooped_window
cg_interaction.x_backoff_outcome.backed_off_x_success
cg_irq_context.x_irq_ctx.jump_x_exit_
cg_irq_context.x_irq_ctx.other_x_exit_
cg_issue.x_w_trap.dual_x_trap
cg_mem_axi.cp_burst.reserved
cg_mem_axi.cp_len.long_burst
cg_mem_axi.cp_len.single
cg_mem_axi.cp_resp.decerr
cg_mem_axi.x_len_dir.long_burst_x_read
cg_mem_axi.x_len_dir.long_burst_x_write
cg_mem_axi.x_len_dir.single_x_read
cg_mem_axi.x_len_dir.single_x_write
cg_mem_axi.x_resp_dir.decerr_x_read
cg_mem_axi.x_resp_dir.decerr_x_write
cg_mem_axi.x_resp_dir.slverr_x_write
cg_memshape.cp_region.other
cg_memshape.x_shape.half_x_off1_x_load
cg_memshape.x_shape.half_x_off1_x_store
cg_memshape.x_shape.half_x_off3_x_load
cg_memshape.x_shape.half_x_off3_x_store
cg_memshape.x_shape.word_x_off1_x_load
cg_memshape.x_shape.word_x_off1_x_store
cg_memshape.x_shape.word_x_off2_x_load
cg_memshape.x_shape.word_x_off2_x_store
cg_memshape.x_shape.word_x_off3_x_load
cg_memshape.x_shape.word_x_off3_x_store
cg_mstatus.cp_mpp.unexpected
cg_mstatus.x_mstatus.disabled_x_one_x_exit_
cg_mstatus.x_mstatus.disabled_x_zero_x_entry
cg_mstatus.x_mstatus.disabled_x_zero_x_exit_
cg_mstatus.x_mstatus.enabled_x_one_x_entry
cg_mstatus.x_mstatus.enabled_x_zero_x_entry
cg_occupancy.x_rob_cause.empty_x_mispredict
cg_occupancy.x_rob_cause.full_x_violation
cg_onset.cp_o_rob.empty
cg_onset.x_onset.empty_x_mispredict
cg_onset.x_onset.empty_x_violation
cg_onset.x_onset.full_x_violation
cg_slot_class.x_slot_kind.slot1_x_serialising
cg_snapshot.x_snap_bpr.empty_x_mispredict
cg_snoop.cp_r_dup.putm_never_issued
cg_snoop.cp_sn.none
cg_snoop.cp_target_state.e
cg_snoop.x_atomic_req.atomic_x_gets
cg_snoop.x_snoop_result.to_i_x_clean_shared
cg_snoop.x_snoop_result.to_i_x_dirty_shared
cg_snoop.x_snoop_result.to_s_x_dirty_exclusive
cg_snoop.x_snoop_state.to_i_x_e
cg_snoop.x_snoop_state.to_s_x_e
cg_trans.cp_t.e_to_i
cg_trans.cp_t.e_to_m
cg_trans.cp_t.e_to_s
cg_trans.x_trans_hart.e_to_i_x_hart0
cg_trans.x_trans_hart.e_to_i_x_hart1
cg_trans.x_trans_hart.e_to_m_x_hart0
cg_trans.x_trans_hart.e_to_m_x_hart1
cg_trans.x_trans_hart.e_to_s_x_hart0
cg_trans.x_trans_hart.e_to_s_x_hart1
cg_window.x_out_kill.success_x_both
cg_window.x_out_kill.success_x_snoop
cg_window.x_out_kill.success_x_trap
cg_window.x_out_rsv.success_x_gone
```
<!-- END UNHIT ROSTER -->

---

## 0. THE SCOPE OF EVERY CLAIM IN THIS FILE

**These proofs are about the UVM environment's DUT, which is `cluster`.**
`tb_top.sv:70` instantiates `cluster`, not `soc_top`, and that decides what can
be reached at all:

  * 44 of the 63 RTL files under `rtl/common`, `rtl/ooo` and `rtl/mem` are
    instrumented. The other 19 emit no coverage records: eight are packages,
    `axi4_if.sv` is an interface, `core_cfg_check.sv` is elaboration-only, and
    **`soc_top.sv`, `clint.sv`, `sim_mem.sv`, `mem_arbiter.sv`,
    `axi4_xbar_top.sv`, `axi4_word_slv.sv`, `axi4_coreaxi_slv.sv`,
    `slave_rd_port.sv` and `slave_wr_port.sv` are compiled but never
    elaborated**: the CLINT and the memory are replaced by testbench AGENTS,
    which is how the environment was specified. `rtl/fpga/` is outside the UVM
    build altogether.
  * `run_regression.sh` passes no coverage flags, so the 42 unit testbenches
    contribute nothing. `tb_clint`, `tb_mesi_ctrl` and `tb_mesi_coh` certainly
    drive states the cluster-level programs never reach.

So "unreachable" here means **unreachable by the UVM environment**, and the
319-block code-coverage figure means the same. A claim about the RTL as a whole
would need the unit batteries instrumented and merged, which is not done and is
not proposed before step 7.

---

## 1. `cg_c1` -- 45 of 62, and the rule is one line of the MESI table

`x_c1` crosses the request type against the REQUESTER's line state and the OTHER
hart's line state: 3 x 4 x 4 = 48 cells.

### 1a. 36 cells: E and M ISSUE NO REQUESTS, and S issues only one

Read from `mesi_ctrl.sv`'s stable rows, which are a literal
`(state, event) -> (actions, next_state)` map:

| row | load | store | what it can request |
|---|---|---|---|
| `LINE_I` :119-120 | `REQ_GETS` | `REQ_GETM` | GetS, GetM |
| `LINE_S` :137-141 | `a.hit` | `REQ_UPGRADE` | Upgrade only |
| `LINE_E` :150-157 | `a.hit` | **`a.hit; ns=LINE_M`** -- silent | nothing |
| `LINE_M` :169-171 | `a.hit` | `a.hit` | nothing (PutM only on evict) |

So the requester's state is DETERMINED by the request:

    GetS    => requester was I      GetM => requester was I
    Upgrade => requester was S

Every cell whose requester state contradicts its request is unreachable:

  * `gets_x_{s,e,m}_x_*`      12 cells
  * `getm_x_{s,e,m}_x_*`      12 cells
  * `upgrade_x_{i,e,m}_x_*`   12 cells

**36 cells, and this is the same fact Phase 2b used to fix the state axis** --
"the requester's pre-state is PROVED by the request type". The bins were written
before that was understood.

### 1b. 1 cell, not 2: SWMR forbids `upgrade_x_s_x_e`. IT DOES NOT FORBID `upgrade_x_s_x_m`, AND THE DESIGN HITS THAT ONE 4 TIMES

This section used to read: *"`upgrade_x_s_x_e` and `upgrade_x_s_x_m`. The
requester holds S, so the line is shared; single-writer/multiple-reader forbids
any other hart holding E or M at the same time ... A hit on either cell would be
a coherence bug."*

**`upgrade_x_s_x_m` has 4 samples in the 29-file union**, on runs where
`sb_coherence::check_swmr` reports 0 violations. Two instruments, one invariant,
two answers -- and `sb_coherence` is the one to believe.

**THE CROSS IS NOT A SNAPSHOT.** `cov_coherence` derives the REQUESTER's state
from the request TYPE (Upgrade implies S -- Phase 2b's own fix, and the right
one) and the OTHER hart's state from the snoop RESPONSE. Those are read at
different instants: the requester was S when it ISSUED, the peer was M when the
request was ORDERED, and the peer's own GetM was ordered in between. SWMR
constrains one instant; this cell spans two, so it is not an SWMR violation and
never was.

**A cross of two axes sampled at different times cannot express a simultaneity
invariant.** Three entries in `defects_and_lessons` say a checker's SAMPLING
INSTANT is part of the checker; none of them had been applied to a coverage
CROSS, where the two axes can have different ones. A cross needs its axes to be
independent AND contemporaneous, and only the first question is anywhere in the
admission rule.

`upgrade_x_s_x_e` survives as a proof, and for the OTHER reason in this file
rather than for SWMR: `cp_so.e` cannot be produced at all, because `cmp_dirty`
is set by any TRUNK response (1d). So the E cell is unreachable for the
`cmp_dirty` reason and the M cell is reachable.

**THE ARITHMETIC HID IT.** The split was recorded as 36 + 2 SWMR + 5
coverpoint-level + 2 `cmp_dirty` = 45. The truth is 36 + 1 + 6 + 2 = 45: one
SWMR cell, and six coverpoint-level bins because `cp_so.e` belongs in that count
and was described in 1d's prose instead. Two errors cancelling to the right
total. **A total cannot reveal a mis-composition; an enumeration can** -- the
S6-3.6 lesson, applied to a proof instead of a gate roster.

### 1c. 6 coverpoint-level bins (five here, plus `cp_so.e` in 1d)

  * `cp_sr.e`, `cp_sr.m` -- the requester's own state E or M. Same proof as 1a:
    those rows issue no request, so no transaction can carry them.
  * `cp_sr.reserved_o`, `cp_so.reserved_o` -- the reserved state encoding.
    `coherence_pkg` defines four line states and `mesi_ctrl.sv:89` marks
    `LINE_O` unreachable outright: *"LINE_O is unreachable: S6-1 rules MESI"*.
  * `cp_r.putm_never_issued` -- an `ignore_bin` by design. `dcache.sv:18`
    routes fills and writebacks over the line port to memory, so `coh_req_type`
    is only ever UPGRADE / GETM / GETS and `REQ_PUTM` is never issued.
    Independently confirmed by line coverage: `mesi_ctrl.sv:80` and
    `coherence_mgr.sv:144` are both never executed.

### 1d. 3 of the remaining 6: E IS NOT OBSERVABLE ON THIS BUS

`gets_x_i_x_e`, `getm_x_i_x_e` and `cp_so.e`. **Found by writing the program for
them and having it fail** -- `asm/excl.S` puts hart0 in E and has hart1 read the
line, and the model recorded `m_to_s`, not `e_to_s`.

The other hart's state is not tracked speculatively; it is DERIVED from the
snoop response, which is the Phase 2b fix (`cov_coherence.sv:259`):

    RSP_TtoB, RSP_TtoN, RSP_TtoT: return t.cmp_dirty ? L_M : L_E;

so E requires a Trunk response with `cmp_dirty` clear. `coherence_mgr.sv:161`
makes that impossible:

    if (snp_rsp[h] == RSP_TtoB || snp_rsp[h] == RSP_TtoN) dty_d = 1'b1;

**`cmp_dirty` is set by any TRUNK response, whether or not the responder was
dirty.** Its own port comment (`:107`) says *"aggregate: a responder was
dirty"*, and the MESI table distinguishes the two cases perfectly well one level
down -- row E answers `RSP_TtoB` with NO writeback (`mesi_ctrl.sv:70`) while
row M answers `RSP_TtoB` with `a.wb=1` (`:176`). The ordering point discards
that distinction when it aggregates.

So a clean exclusive responder is reported as M, and **no program can ever make
`cp_so.e` true**. Same for `gets_x_i_x_e` and `getm_x_i_x_e`.

**THIS IS A FINDING ABOUT THE DESIGN, NOT ONLY ABOUT THE BINS**, and it is
recorded in `defects_and_lessons.md` section 6: a signal whose name and comment
say `dirty` and whose logic says `trunk`. It is an OBSERVABILITY defect -- the
battery is 80/0 and nothing here suggests the protocol misbehaves -- so it is
reported rather than fixed, the same way `acc_hit` was left alone once measured.
If it is ever narrowed to the writeback, these three bins become reachable and
`asm/excl.S` already produces the traffic that would close them.

### 1e. The 3 that were reachable, and are now hit

`gets_x_i_x_s`, `getm_x_i_x_s`, `upgrade_x_s_x_i` -- all closed by
`asm/excl.S`, which is the exclusive-handoff program written for exactly this.

---

## 2. `cg_trans` -- 3 of 9. E -> M IS INVISIBLE TO THIS INSTRUMENT

`cp_t.e_to_m` and its two `x_trans_hart` cells.

`cg_trans` is fed ENTIRELY from coherence transactions: the requester's new
state is derived from `t.req_type` (`cov_coherence.sv:247`) and the responder's
from `t.snp_rsp` (`:479`). Both need a transaction to exist.

E -> M does not produce one. `mesi_ctrl.sv:68`:

    EV_STORE: begin a.hit=1'b1; ns=LINE_M; end       // S6-C3: SILENT E->M

with no `req_valid` -- and the comment says why: *"we already hold the only copy,
so no other cache needs telling. Making this a bus request is the classic
MESI-loses-its-point mistake."*

**The transition happens in the design and cannot be observed by a
transaction-fed model.** Closing it would mean feeding `cg_trans` from the
backdoor tags instead, which re-introduces the sampling-instant question that
cost this project three separate defects. The bin is a proof, not a program.

`e_to_s` and `e_to_i` LOOK like a different class -- they arise from snoop
responses (`RSP_TtoB` :159, `RSP_TtoN` :160), so a transaction does exist. They
are nevertheless unreachable, for the reason in section 1d: the responder's FROM
state comes from `other_prestate()`, which cannot report E because
`coherence_mgr.sv:161` sets `cmp_dirty` on every Trunk response. A clean E
responder downgrading to S is recorded as `m_to_s`.

**MEASURED, not argued:** `asm/excl.S` hands an exclusively-held line from hart0
to hart1 and the model logged `m_to_s` 15 times and `e_to_s` zero times, with
`i_to_e` at 389 -- so E is entered constantly and can never be seen being left.

All three E transitions are therefore proofs, for two different reasons: `e_to_m`
because no transaction exists at all, `e_to_s` and `e_to_i` because the
transaction that does exist cannot carry the distinction.

---

## 3. `cg_memshape` -- 10 of the 11. A MISALIGNED ACCESS NEVER REACHES THIS GROUP

`x_shape` is size x offset x direction = 24 cells. `cg_memshape` samples only
when `rvfi_txn::touched_mem()` is true, i.e. when a memory access COMPLETED.

`core.sv:566` computes misalignment at execute:

    MEM_W:         mem_mis_ex = (alu_result[1:0] != 2'b00)
    MEM_H, MEM_HU: mem_mis_ex = alu_result[0]

and `core.sv:1031` turns that into an exception, so the access never completes,
both byte masks stay zero, and `touched_mem()` is false. Therefore:

    half x offset 1,3 x {load,store}    4 cells   UNREACHABLE
    word x offset 1,2,3 x {load,store}  6 cells   UNREACHABLE

**10 of 24.** The remaining 14 are reachable and `asm/memshape.S` covers them.

These events are not lost -- they are measured where they exist. `asm/misalign.S`
takes exactly these traps and `cg_exception` bins them as causes 4 and 6.

---

## 3a. `cg_memshape.cp_region.other` -- A SENTINEL, AND IT WAS FILED AS A PROOF

The accounting table used to say *"1 region unreachable"* and no section proved
it. It is not unreachable. `region_of()` (`cov_isa.sv:557`) returns 3 for any
address below `0x8000_0000`, and this DUT executes such an access without
complaint: `cluster.sv` masks the data address to eighteen bits, so it lands
somewhere inside the aliased 256 KB image. Two instructions would hit the bin.

**IT SHOULD NOT BE HIT, AND THAT IS ITS VALUE.** The bin fires exactly when a
data access leaves the linked image -- which on this platform is silently
ALIASED rather than faulted, and is what hung `irq_mh.S` for 4.6 million log
lines when its handler stored to the CLINT at `0x0200_4000`
(`defects_and_lessons` section 4, "the program cannot reach the CLINT"). Writing
a program to hit it deliberately would raise a percentage and destroy an alarm.

Its disposition is the category this file already uses for
`cg_csr.cp_csr.other`, `cp_r.putm_never_issued` and
`x_out_rsv.success_x_gone`: **a bin whose purpose is to stay empty.** Two
consequences worth recording.

  * **The reference could not follow it anyway.** Spike faults on an address the
    DUT aliases, so a deliberate hit is only possible under `use_ref_model = 0`.
  * **A sentinel with no procedural check behind it is the weaker half of 4a's
    rule** -- *an unhittable bin cannot fire, a check can*. It now has one:
    `cov_isa` counts data accesses outside the linked image (`n_region_outside`,
    sampled beside `cg_memshape`) and raises a `COV_ISA` error naming the first
    address; `uvm_gate` and `uvm_cov_gate` both fail on that message.

---

## 4. `cg_hazard` -- 4 cells. A STORE AND A BRANCH HAVE NO DESTINATION

`war_x_store`, `waw_x_store`, `war_x_branch`, `waw_x_branch`.

`core.sv:143`:

    rvfi_rd_addr[i] = (commit_o[i].rf_we && !(...)) ? commit_o[i].lrd : 5'd0;

A store and a branch do not write a register, so `rf_we` is 0 and `rd_addr` is
0. `cov_isa`'s hazard derivation requires `t.rd_addr != 5'd0` for both WAR and
WAW, so neither can ever be classified for those two instruction classes.

They are CROSS cells, and cross-level `ignore_bins` are dropped by this tool
(4a's finding), so they cannot be excluded declaratively. Restructuring the
cross to remove them would also lose `raw_x_store` -- a store depending on a
previous result -- which is one of the more interesting cells in the group.
**Four bins is the right price for keeping it.**

---

## 5. `cg_mem_axi` -- 4 cells, contingent on PARAMETERS rather than structure

`cp_len.single`, `cp_len.long_burst`, and the two `x_len_dir` cells that follow
from them.

  * `long_burst` is `[4:255]`. `axi_adapter.sv:49` is
    `axlen = word_q ? 8'd0 : 8'(BEATS - 1)` with `BEATS = BEATS_PER_LINE = 4`
    (`mem_pkg.sv:19`), so AxLEN is 0 or 3 and never 4 or more.
  * `single` is AxLEN 0, which needs `word_q`, an MMIO word access. `is_mmio`
    (`mem_pkg.sv`) is true only for the CLINT window at `0x0200_xxxx`, and no
    program in the UVM battery addresses it: interrupts are driven at the pins
    by the CLINT agent. `merge_d_mmio.sv`'s 8 never-executed line points say
    the same thing from the other direction. A program that writes `mtimecmp`
    through the cluster would hit both.

**These are kept rather than deleted** because both are contingent on a
parameter or a program, not on the structure of the design. A bin is the only
thing that would notice if `BEATS_PER_LINE` changed or a program reached the
CLINT.
Contrast the NINE bins deleted in the 4b finalisation -- `BURST_INCR` and
`AXI_SIZE_4B` are written as constants into the adapter and EXOKAY is documented
as never generated, so no input can change them.

---

## 6. Single bins, each with one line of RTL behind it

| bin | proof |
|---|---|
| `cg_slot_class.x_slot_kind.slot1_x_serialising` | `rob.sv:129` blocks `is_csr \|\| is_mret \|\| is_fence \|\| is_fence_i` from any slot but 0 and forces it to retire alone. A hit is a DESIGN finding, and the procedural check in `cov_isa` reports it. |
| `cg_snapshot.x_snap_bpr.empty_x_mispredict` | See section 11: commit is BLOCKED throughout a mispredict recovery, so the branch and everything older cannot leave the ROB. |
| `cg_csr.cp_csr.other` | The `default` arm. `csr_addr_e` (`rv32i_pkg.sv:166`) enumerates every address the design decodes, and `asm/csrprobe.S` reads all of them; a hit means the design grew a CSR nobody declared. **A bin whose purpose is to stay empty.** |
| `cg_snoop.cp_r_dup.putm_never_issued` | As 1c: `REQ_PUTM` is never issued. |

---

## 7. `cg_mem_axi` -- 3 more, and one that was NOT a proof

`cp_burst.reserved` is an `illegal_bins`: AxBURST 2'b11 is reserved and illegal
while AxVALID is high (`axi4_pkg.sv:33`). A hit is a protocol violation, not
coverage. Coverpoint-level illegal bins DO survive elaboration here, unlike
cross-level ones, so this one is a real check.

`cp_resp.decerr` and its two `x_resp_dir` cells need a DECERR, which the
crossbar's decerr responders raise for an access outside every mapped slave. The
core cannot generate one: `cluster.sv` masks the data address to eighteen bits,
so every access it can express lands inside the mapped region. Reachable only
from the testbench side, and no agent drives it today.

**`cp_lat` WAS NOT A PROOF, IT WAS A BUG, and it is fixed.** The three
non-`immediate` bins and all six `x_lat_dir` cells were unhittable because
`cov_isa` read `mem_txn::latency` -- a `rand` field describing the RESPONSE THE
DRIVER WAS TOLD TO PRODUCE, never assigned on a monitor-published transaction --
instead of `observed_latency()`, whose own comment says it exists "for
coverage". MEM_MON was reporting `latency avg 13 max 72 cycles` from that very
function on the same transactions this model was binning as zero.
**Nine bins moved from unreachable to reachable by changing one expression.**

---

## 8. Contradictions: bins whose two axes cannot both be true

### `cg_exception` -- 8 cells of `x_trap`, plus the fetch fault

`cp_kind` is `mcause[31]` and `cp_cause` is `mcause[30:0]`, so the cross asks
for an interrupt whose code is an exception code, or the reverse. `core.sv:1033`
assigns exception causes 0, 2, 4 and 6, `rob.sv` assigns 1 (a faulted fetch)
and the load completion lane assigns 5 (a faulted fill), and the platform can
raise interrupts 3 and 7 only (`cluster.sv` ties `.irq_ext(1'b0)`, there being
no PLIC). So:

    interrupt x {insn_misaligned, insn_fault, illegal_insn, load_misaligned,
                 load_fault, store_misaligned}
    exception x {irq_soft, irq_timer}

are eight combinations the encoding forbids. `cp_cause.other` is the `default`
arm and is the ninth: a cause outside the eight the design can produce.

`cg_interaction.x_atomic_snoop.write_intent_x_snooped_window` is a statement.
The protection window in `coherence_mgr.sv` now defers a peer's GetM or
Upgrade to the reserved line for as long as the reservation stands, so the
only snoop that can land on that line inside a window is a peer GetS. No
program in the sweep loads the reserved line from the other hart while a
window is open; one that did would hit the cell.

`cg_irq_context.x_irq_ctx.jump_x_exit_` and `other_x_exit_` are hit by
timing, not by design: they record the class of the instruction retiring as
the handler exits, which is whatever the interrupt landed on. Both were hit
before the execute stage was registered and stopped being hit after, because
the interrupt now lands one cycle later relative to the loop in `irq_ctx.S`.

`x_resp_dir.slverr_x_write` is a statement about the instrument. The driver
injects a faulted response only at or above `cpu_cfg.slverr_lo`, and its
write-response thread has no address to compare (the address was consumed with
the data beats), so with a floor set no write is ever faulted. The design side
is indifferent: `dcache.sv` ignores the response code of a writeback, which is
the only write the cluster makes.

`cp_cause.insn_fault` and `x_trap.exception_x_insn_fault` are a statement, not
a proof. The mechanism is live (`icache.sv` carries `line_rerr` into
`fetch_queue`, and `rob.sv` turns it into cause 1 at allocation), but the only
program that provokes bus errors, `asm/buserr.S` under `cpu_axierr_test`,
injects them on its data buffer alone so that the reset vector and the trap
handler cannot fault out from under it. A fetch fault therefore never happens
in the sweep. A program that faults a fetch and retries it would hit both.

### `cg_mstatus` -- 5 cells of `x_mstatus`, plus MPP

`cp_when` is not an independent axis: `cov_isa` samples this group ONLY on an
`mstatus.MIE` edge and derives `entry = !mie`. So at entry `mie` is 0 by
construction and at exit it is 1, which kills every cell pairing `enabled` with
`entry` or `disabled` with `exit_`. And at entry the hardware has just copied
the old MIE into MPIE, which was 1 or the interrupt could not have been taken,
so `disabled_x_zero_x_entry` cannot occur either.

`cp_mpp.unexpected` is the sixth. `csr_regfile.sv:113`'s `warl_mstatus` starts
from `MSTATUS_MPP_M` and copies back only the MIE and MPIE bits, so MPP reads
11 (machine mode, the only mode this core has) and every other field reads
zero. The bin `hardwired_m` is the value it always has; `unexpected` covers 00,
01 and 10 and cannot be reached.

### `cg_issue` -- `x_w_trap.dual_x_trap`

A trap retiring in the same cycle as a second instruction. `core.sv`'s 2c-A1
note is explicit: the RVFI record for a synchronous exception is emitted from
the RECOVERY path. Checked rather than recalled:
`rvfi_exc_emit = (rq_q == R_IDLE) && trig_exc && !trig_irq` (`:1702`), and
`recovery_idle = (rq_q == R_IDLE) && !(trig_irq || trig_exc || trig_actor)`
(`:1705`) is therefore 0 at that instant, so `commit_ready` (`:1711`) is 0 and
no slot retires. **The design guarantees a trap retires alone.**

### `cg_branch` -- `x_branch.not_taken_x_backward` and `cp_tgt_align.mis[*]`

`a_back` is derived as `pc_wdata < pc_rdata`. A NOT-TAKEN branch has
`pc_wdata == pc_rdata + 4`, so it can never be backward -- the two axes are not
independent. (The direction a not-taken branch WOULD have gone is knowable from
the immediate's sign; the model does not use it, and this is noted rather than
changed because altering the derivation changes what every already-hit cell in
the group means.)

`cp_tgt_align.mis[*]` needs a retired branch whose target is not 4-byte
aligned. Without the C extension that target traps at `branch_unit.sv:49`
(`target_misaligned = taken && (target[1:0] != 2'b00)`) before it is taken, so
no such branch ever retires.

### `cg_lsu_hazard` -- `cp_lsu_hazard.none` and its two `x_lsu` cells

`sample_lsu()` only calls `sample()` from inside the branch that FOUND a
same-word older access, and it `break`s out on load-after-load without
sampling. `HZ_NONE` is therefore never passed. This is deliberate -- 4a records
that binning the no-overlap case would bury the three real ones under the ~95%
of instruction pairs that touch no memory.

**THIS IS A PROOF ABOUT THE SAMPLER, NOT ABOUT THE DESIGN**, and it sat under a
heading that says otherwise. Nothing in the CPU forbids a load and a store that
miss each other; the testbench declines to bin it. Resolved in section 12 by
deleting the three bins and keeping the information as a counter -- because the
alternative, sampling every pair, would bury the three real hazard cells under
the 95% and is the `full_x_recovering` failure with the polarity reversed.

### `cg_snoop` -- `cp_sn.none`

A transaction with no snoop sent. `coherence_mgr.sv:148` snoops every hart
except the requester on every request, with `REQ_PUTM` the only exception -- and
PutM is never issued.

### `cg_onset` -- `cp_o_rob.empty` and its two crosses

ROB occupancy at the instant a mispredict or a violation is DETECTED. Both
events are raised by an instruction that is itself in the ROB, so the count
cannot be zero at that instant.

---

## 9. `cg_window` -- 4 PROOFS, AND THE 2 ONCE-OPEN BINS ARE CLOSED

An earlier draft filed all six of these as "owned by step 7". **That was a third
category invented to avoid saying the criterion was not met**, and four of them
are ordinary proofs. The remaining two are now closed by `asm/lrsc_qtrap.S`
(9b), so `cg_window` reads 22 of 26 with every `cp_kill` bin sampled.

### 9a. Four proofs, all from one expression

`lrsc_unit.sv:43`:

    sc_success[h] = sc_valid[h] && rsv_valid[h] && (addr match)

**Success implies the reservation was valid**, so every cell pairing a SUCCESS
with a dead reservation is impossible:

| bin | why |
|---|---|
| `x_out_rsv.success_x_gone` | `gone` IS `!rsv_valid`; success requires it |
| `x_out_kill.success_x_snoop` | a kill zeroes the counter (`:162`), so the SC fails |
| `x_out_kill.success_x_trap` | same |
| `x_out_kill.success_x_both` | same |

`success_x_gone` is also checked PROCEDURALLY by `check_sc_legality` (0
violations across 159 SCs), because it is the atomicity violation the
`sc.w`-writes-its-address bug lived in. A bin whose purpose is to stay empty.

### 9b. CLOSED -- `asm/lrsc_qtrap.S`, and the remedy had been written already

`cp_kill.trap` and `x_out_kill.failed_x_trap`: a trap being the SOLE cause of
the kill. **Both are now hit.** They were the last two bins in this model that
were neither hit nor proven.

**THE CAUSE, and it is worse than "not line-qualified":**

    lrsc_unit.sv:52   cnt_d[h] = '0  when snoop_clear[h] or trap_clear[h]
    cluster.sv:246     snp_clr[h] = dc_rsv_clear   (dcache: snp_valid && sn_act.rsv_clear)

Neither expression compares an address -- and `mesi_ctrl` raises `rsv_clear`
from **row I as well** (`:131`, *"nothing to invalidate, but [rc] still applies:
a reservation can outlive the line"*), while `coherence_mgr:286` snoops every
hart except the requester on every request. So the kill does not even require
this hart to HOLD the line: any GetM or Upgrade by the peer, to any address,
clears the reservation. MEASURED, not argued: `mesi_ctrl.sv:50` is taken
**6,521 times** across the coverage union.

`crt0_multihart`'s publish sequence gives hart 1 exactly two such stores,
`hart_result[1]` and `hart_done[1]`, and one of them lands inside case B's
window. That is why `cp_kill` read `both` while `SNOOP_MON` read zero snoops in
a window: the pin says a reservation-clearing snoop arrived, the monitor says
none of them targeted the reserved line, and **both were right about different
questions.**

**THE REMEDY WAS ALREADY IN THE FILE AND HAD NEVER EXECUTED.** `lrsc_trap.S`
carried a register-only `quiet_wait` delay, and this document recorded that it
"did NOT close the bins". It had not failed -- it had never run. The control
case branches `beqz t4, case_b`, and `case_b` is BELOW the delay, so the only
path that reaches case B jumps over it. Confirmed in the disassembly, not
inferred: `80002028 beqz t4,80002044 <case_b>` skipping `80002034-80002040`.
**A directed remedy aimed one label off is indistinguishable from no remedy** --
the same shape as the directed test aimed at `t1` instead of `t0`
(`defects_and_lessons` section 4), and it read as a refuted hypothesis rather
than as dead code.

Measured once it was reachable: the delay form closes the bins from ~200
iterations upward and reads `both` below ~50. So the diagnosis was right, the
remedy was right, and the branch was wrong.

**WHY IT IS A SEPARATE PROGRAM, AND THIS IS THE PART WORTH CARRYING FORWARD.**
The first fix made `lrsc_trap.S` itself go snoop-quiet. It worked -- and the
union still read **six** unhit bins in `cg_window`, because `lrsc_trap` was the
ONLY program producing `cp_kill.both` and `x_out_kill.failed_x_both`. Two bins
closed, two opened, net zero. That is the `cg_irq_context` shuffle again, where
moving one instruction only moved which cell was empty, and it was caught only
because the union was re-measured rather than assumed from the single-program
run. `both` and `trap` are different scenarios and cannot share a program.

So `asm/lrsc_trap.S` is UNCHANGED and keeps `both`; `asm/lrsc_qtrap.S` is new
and owns `trap`. It waits for an EVENT rather than counting cycles -- hart 1's
`hart_done[1]` becoming visible is the exact instant after which hart 1 can no
longer snoop, because everything it does afterwards is one fence (which writes
back over the LINE port and raises no coherence request) and an instruction-only
park loop. The wait is the barrier shape `crt0_multihart` already uses and that
`mh.hex` compares clean with.

    cpu_atomic_prog_test on lrsc_qtrap:
      cp_kill:  none=1 (case A)  snoop=0  trap=1 (case B)  both=0
      x_out_kill.failed_x_trap = 1
      COV_LRSC 0 snoops in window   SNOOP_MON 0 snoops in window   (they AGREE)
      tohost 00000001 PASS   266 compared   0 mismatches   UVM_ERROR : 0
    identical at +DELAY 0 / 10 / 20 / 40 -- CHECKED is 266 at every one, so the
    program is deterministic rather than winning a race.

**Spurious loss is architecturally legal** (`cluster.sv:248` says so), so the
missing line qualification is a PRECISION limit and not a correctness defect.
It stays recorded rather than fixed.

**WHAT THIS DOES AND DOES NOT SETTLE FOR STEP 7.** Its recorded prerequisite was
"reconcile `COV_LRSC` and `SNOOP_MON` before grading a new witness by either".
The two report the same number on this program, and the CAUSE of their earlier
disagreement is demonstrated rather than inferred. **The definitions were still
different at that point**; unifying them is section 12.

## 9c. (historical) STEP 7 OWNS THESE, NOT 4c AND NOT 4d

Six bins in `cg_window` are neither stimulus nor proof: `cp_kill.trap`,
`x_out_kill.failed_x_trap`, `success_x_trap`, `success_x_both`,
`success_x_snoop`, and `x_out_rsv.success_x_gone`.

`cp_kill.trap` -- the bin that would show a trap is SUFFICIENT ON ITS OWN to
kill a reservation -- **has never been hit in any run of this project**.
`asm/lrsc_trap.S`'s case B fails for THREE sufficient causes (the trap, the
handler's own memory traffic, and a snoop reaching the reserved line), and the
test only ever asked WHETHER the SC failed, never why. Measured baseline vs
mutated: `cp_kill` reads `both` with `trp_clr` wired and `snoop` with it tied
off, and `cp_out.failed` in BOTH.

**Superseded by 9b in every particular**, and kept only because the shape of the
error is worth carrying: four of the six were ordinary proofs nobody had
written, and "owned by step 7" was a third category invented to avoid saying the
criterion was not met.

---

## 10. The last group-level proofs

### `cg_snoop` -- `x_atomic_req.atomic_x_gets`

An ATOMIC request that is a GetS. `dcache.sv:202`:

    assign wintent = we || is_lr;

an LR carries WRITE INTENT, so it takes the store path and issues `REQ_GETM`
(or `REQ_UPGRADE` from S) -- never `REQ_GETS`. The atomic flag and the GetS
request type are mutually exclusive by that one line.

### `cg_snoop` -- three result cells that contradict their own snoop type

    to_i_x_clean_shared     to_i_x_dirty_shared     to_s_x_dirty_exclusive

`to_i` is the response to a GetM, which acquires the line exclusively, so the
completion cannot report `shared`. `to_s` is the response to a GetS with a
responder present, which by definition leaves the line shared, so it cannot
report `exclusive`. The snoop type and the completion flags are not independent
axes; the cross asks for combinations the protocol defines away.

### `cg_mem_axi` -- `cp_lat.immediate`, AND THE FIX INVERTED IT

Before the `observed_latency()` correction, `immediate` was the ONLY bin that
could be hit. After it, `immediate` was the only one that could NOT: the latency
is measured from request-accepted to first beat (`mem_monitor.sv:72`, `:131`),
and that was never the same cycle -- the memory model always takes at least one.

**The same nine bins were unreachable before and after, and they are a different
nine.** Which is the clearest possible statement of why the audit is worth
running: the group read a plausible number in both states.

**AND THAT WAS A PROOF ABOUT THE TESTBENCH, NOT THE DESIGN.** Both halves of it
are ours: the measurement WINDOW is `mem_monitor`'s definition and the floor is
`mem_driver`'s behaviour. No RTL forbids a slave from returning a beat in the
address cycle. Same shape as `x_lat_dir.long_lat_x_write`, which sat as
unreachable until someone noticed it needed a KNOB that did not exist.
**Resolved in section 12** by re-deriving the bucket boundary from what the axis
can actually take, rather than by building a zero-latency memory to light a lamp.

### `cg_onset` -- `cp_o_rob.empty` and its two crosses

ROB occupancy at the instant a mispredict or violation is DETECTED. Both events
are raised BY an instruction that is itself occupying a ROB entry, so the count
cannot be zero. `x_onset.full_x_violation` is NOT in this class -- it is
reachable, and `asm/csrc/satviol.c` closed it until the snoop search stopped
flagging the oldest load; see section 11.

### `cg_mem_axi` -- `cp_resp.decerr` and its two crosses

A DECERR needs an access outside every mapped slave. `cluster.sv` masks the
core's data address to eighteen bits, so every address it can express lands
inside the mapped region. Reachable only by driving the fabric directly, which
no agent does -- and unlike `slverr`, there is no `cpu_cfg` knob for it.

---

## 11. MODEL LIMITATIONS, AND THE ONCE-OPEN BINS

Every unhit bin has a proof, a sentinel disposition, or was closed by a program.
What remains in this section is a MODEL limitation that belongs here rather than
among the proofs, and the record of how the once-open bins fell.

**0a. `cov_isa::reads_rs2()` does not include the AMO opcode.**

    return (op inside {7'b0110011, 7'b0100011, 7'b1100011});   // R, store, branch

so an atomic's rs2 -- the DATA register of an `sc.w` -- is never compared, and a
RAW into an atomic through its data is invisible to `cg_hazard`. Measured:
`addi t5, t6, 1` followed by `sc.w t0, t5, (t3)` executed and `raw_x_other`
stayed unhit. `asm/hazx.S` closes the bin through rs1 (the ADDRESS register)
instead, which is a genuine RAW and is read. **The data dependency remains
unmeasured.** Not changed here because widening `reads_rs2` alters what every
already-hit cell in the group means, and that is a decision about the model's
denominator rather than a bug fix.

**`cg_occupancy.x_rob_cause.full_x_actor_fence` and `cg_occupancy.x_sq_lq.light_x_full`
-- hit by timing, not by design.** Both are coincidences: the reorder buffer
full at the moment a fence reaches the head, and the store queue nearly empty
while the load queue is full. They were unhit in one sweep after the predictor
began holding its prediction across an I-cache miss and hit again in the next,
because the seed the sweep records per run moved. No program forces either
shape; if they drop out of the union again, that is the reason.

**`cg_onset.x_onset.full_x_violation` and `cg_occupancy.x_rob_cause.full_x_violation`
-- ONCE HIT, reachable, and no program forces them.** Both ask for a
violation recovery while the reorder buffer is full. `asm/csrc/satviol.c` hit
them while the load queue's snoop search flagged every executed load to the
line, which made the oldest load a violator whenever the peer's store was
queued at the ordering point. That flag is gone: a load is stale only when an
older load has not bound its value yet (`lsq.sv`, the snoop search), so a
violation now needs a younger load executed past an older unbound one, and the
sweep's programs never do that with the buffer full. The bins are reachable in
principle. A program that forces them needs a long-latency older load, a
younger load to the same line, a peer store between the two, and thirty more
instructions dispatched behind them. None is written yet.

**`cg_occupancy.x_rob_cause.empty_x_mispredict` -- PROOF, and the mechanism
first recorded for it was WRONG.** The original proof read *"`core.sv:1154`
names three walk classes ... a mispredict walks the BRANCH'S YOUNGERS"*. **A
mispredict does not walk the ROB at all.** `core.sv:1151` is
`R_QUIESCE: if (quiet) rq_d = r_is_bpr_q ? R_REDIR : ...` -- the branch-recovery
path skips `R_WALK` entirely and repairs rename from a SNAPSHOT
(`snap_restore_fire`, `:1724`).

The conclusion survives with a better proof: `commit_ready` requires
`recovery_idle || rq_q == R_ACT` (`:1711`), and neither holds during a
mispredict's `R_QUIESCE`/`R_REDIR`, so nothing retires while the cause register
says `mispredict`. The branch and everything older cannot leave, and occupancy
cannot be zero. **The same one line proves `cg_snapshot.x_snap_bpr.empty_x_mispredict`**
and is stronger than the snapshot-slot argument used there. Corroborated rather
than asserted: `empty_x_trap` IS hit, and a trap is exactly the class that DOES
walk the ROB, popping it to zero.

**`cg_distance.cp_d.immediate` and its two crosses -- PROOF, DERIVED AND
MEASURED.** `cov_lrsc` was given a raw distance report, because a BUCKET cannot
distinguish "no program produced a short pair" from "this LSQ cannot". On
`asm/lrscx.S`, which puts `sc.w` in the instruction IMMEDIATELY after its `lr.w`:

    LR->SC distance: min 4 cycles, max 157        (63 samples in `near`)

The bucket asks for UNDER 4, and the floor is exactly 4 for a structural reason
read off `lsq.sv` rather than left as a measurement:

    lrsc_lr_valid = ld_go && hl.is_lr                            (:581)   cycle N
    hs_drain      = ... && (lm_q == M_IDLE) && !ld_go            (:504)   "loads first"
    sm_q          : S_IDLE -> S_REQ on hs_drain                  (:885)
    lrsc_sc_valid = (sm_q == S_REQ) && hs.is_sc && dgnt          (:590)

The LR's own load machine must return to `M_IDLE` before the SC may drain, and
`M_IDLE -> M_LREQ -> M_LRESP -> M_IDLE` is three cycles at the fastest, so
`hs_drain` cannot assert before N+3, `S_REQ` before N+4, and `sc_valid` before
N+4. **The derivation and the measurement agree at the boundary**, which is the
strongest form this kind of claim takes. One residue: `< 4` is a TESTBENCH
constant (`dist_bucket`, `cov_lrsc.sv:170`), so the RTL supplying 4 as well is a
coincidence rather than a derivation. **The instrumentation is kept**, so if the
LSQ ever gains a bypass the number moves and the proof is retired by measurement
rather than by memory.

**`cg_interaction.x_backoff_outcome.backed_off_x_success` -- PROOF.**
`asm/lrscx.S` produced 64 back-offs and 64 successful SCs and never put the two
on the same SC. `lrsc_unit.sv:42` says why in its own words:

    an SC attempted during the backoff phase FAILS, which is what forces the
    retry loop to re-execute its LR rather than sneak a store through a dead
    reservation

and success requires the reservation to be VALID, not merely non-zero (:144).
So a back-off inside a window guarantees that window's SC fails, and reaching a
success needs a NEW `lr.w` -- which is exactly where `cov_lrsc` clears
`backed_off_in_window` (:350). The two axes cannot both be true. Same class as
`x_out_rsv.success_x_gone`: a bin whose purpose is to stay empty.

**`cg_mem_axi.x_lat_dir.long_lat_x_write` -- CLOSED, and it needed a KNOB that
did not exist.** A write is timed AW-accept -> first W beat
(`mem_monitor.sv:72`, `:131`), which is decided by when the SLAVE raises
`wready` -- the request-latency window never touches it, and no program shape
does either. `mem_driver.sv:13` had `w_stall_pct = 25` as a PROTECTED field, so
the chance of twenty consecutive stalls was 0.25^20. It is now
`cpu_cfg.w_stall_percent`, read before the deterministic-regime override so a
gate reproducing a cluster gate still gets a flat slave, and `cpu_wstall_test`
sets 92%. **Exactly the shape `slverr_percent` had**: a path the design has,
reachable only through a knob no test could set.

**`cg_irq_context` -- CLOSED at 100.00%, and the three attempts are the lesson.**

  1. A store added after the `jal` closed `store_x_entry` and OPENED
     `jump_x_entry`.
  2. Moving the store to its dependency closed both entries and opened the two
     EXIT cells.
  3. That shuffle WAS the finding. The entry class is the LAST PUBLISHED
     retirement before the handler's first instruction, and `rvfi_monitor`
     publishes slot 0 then slot 1 within a cycle -- so rearranging one
     instruction only moves which cell is empty. What was missing was ARRIVALS,
     and the reason was arithmetic never done: the sequence sends 600 pulses
     over ~900,000 cycles while the loop at 2,000 iterations covered ~300,000,
     so the program exited with 341 pulses still to come. Sizing `OUTER`
     against the pulse train closed all sixteen cross cells.

**Third time in this work that an interrupt problem was arithmetic between the
sequence and the program rather than a mechanism** -- after the `mtimecmp` unit
mismatch (a wait measured in tenths of a tick against a step measured in tens)
and the `WANT_IRQ` cap (a knob on one side of an interface is not a knob).

**THE RULE THIS FILE FOLLOWS:** a bin gets a proof, a program, or an explicit
statement that it has neither. What it must never get is silence, because an
unexplained unhit bin and a proven-unreachable one look identical in the
denominator -- which is the whole reason step 4 was rescoped to require this
document at all. `scripts/cov_proof_audit.sh` now enforces it mechanically.

---

## The citation roster

Every RTL citation this file makes, with a fragment of the line it points at.
`scripts/cite_audit.sh` (battery gate `uvm_cites`) follows each one and fails if
the anchor is no longer within a few lines of where the citation says it is.

The anchor is the point. A citation that has drifted still *reads* correct, and
twelve of these had drifted by up to 145 lines while every claim they supported
was still true. The claims were fine; the citations were not **checkable**, and
a proof you cannot follow is a proof on trust. A hostile audit whose stated job
was "every proof checked against the RTL it cites" missed all twelve, because it
re-derived each claim by hand instead of following the citation.

A shape of `?` is a hard failure, so `--regen` cannot quietly launder an
unclassified citation into a pass.

<!-- BEGIN CITATION ROSTER -- generated by scripts/cite_audit.sh --regen -->
```
# path:line                        shape  anchor (must still be within +/-6 lines)
rtl/mem/axi4/axi4_pkg.sv:33        norec       typedef enum logic [1:0] {
rtl/mem/axi_adapter.sv:49          never       assign axlen = word_q ? 8'd0 : 8'(BEATS - 1);
rtl/common/branch_unit.sv:49       norec       assign target_misaligned = taken && (target[1:0] != 2'b00);
rtl/ooo/cluster.sv:246             norec       assign snp_clr[h] = dc_rsv_clear;
rtl/ooo/cluster.sv:248             norec       // Losing a reservation spuriously is legal; keeping one across a trap
rtl/mem/coherence_mgr.sv:144       never       if (req_type[pick] == REQ_PUTM) begin
rtl/mem/coherence_mgr.sv:148       norec       // Snoop everyone except the requester.
rtl/mem/coherence_mgr.sv:161       guard       if (snp_rsp[h] == RSP_TtoB || snp_rsp[h] == RSP_TtoN) dty_d = 1'b1;
rtl/ooo/core.sv:1031               norec       || (mem_ex && mem_mis_ex);
rtl/ooo/core.sv:1033               guard       ? (is_store_ex ? 4'd6 : 4'd4) : 4'd0;
rtl/ooo/core.sv:1151               guard       || mispredict_ex || trig_viol) rq_d = R_QUIESCE;
rtl/ooo/core.sv:1154               hist        || r_is_viol_q)
rtl/ooo/core.sv:143                guard/else  rvfi_rd_addr[i]  = (commit_o[i].rf_we && !((i == 0) && rvfi_exc_emit))
rtl/ooo/core.sv:566                opaque      MEM_W:          mem_mis_ex = (alu_result[1:0] != 2'b00);
tb/uvm/cov/cov_coherence.sv:247    norec       protected function int unsigned req_prestate(snoop_txn t);
tb/uvm/cov/cov_coherence.sv:259    norec       RSP_TtoB, RSP_TtoN, RSP_TtoT: return t.cmp_dirty ? L_M : L_E;
tb/uvm/cov/cov_isa.sv:557          norec       if (a >= 32'h8000_3000) return 1;                     // data
tb/uvm/cov/cov_lrsc.sv:170         norec       protected function int unsigned dist_bucket(longint unsigned d);
rtl/common/csr_regfile.sv:113      opaque      function automatic word_t warl_mstatus(word_t v);
rtl/mem/dcache.sv:18               norec       // Permission traffic only; fills and writebacks ride the line port to
rtl/mem/dcache.sv:202              norec       assign wintent = we || is_lr;
rtl/mem/lrsc_unit.sv:42            norec       // An SC in the backoff phase fails: the retry loop must re-execute it
rtl/mem/lrsc_unit.sv:43            norec       assign sc_success[h] = sc_valid[h] && rsv_valid[h]
rtl/mem/lrsc_unit.sv:52            guard       cnt_d[h] = '0;
tb/uvm/mem/mem_driver.sv:13        norec       protected int unsigned w_stall_pct = 25;
tb/uvm/mem/mem_monitor.sv:72       norec       t.t_req = cycle_now();
rtl/mem/mem_pkg.sv:19              norec       localparam int unsigned BEATS_PER_LINE = LINE_BYTES / 4;
rtl/mem/mesi_ctrl.sv:50            guard       EV_SNOOP_GETM: begin a.snp_resp=1; a.snp_rsp=RSP_NtoN; a.rsv_clear=1; 
rtl/mem/mesi_ctrl.sv:68            never       EV_STORE: begin a.hit=1'b1; ns=LINE_M; end
rtl/mem/mesi_ctrl.sv:70            guard       EV_SNOOP_GETS: begin a.snp_resp=1; a.snp_rsp=RSP_TtoB; ns=LINE_S; end
rtl/mem/mesi_ctrl.sv:80            never       EV_EVICT: begin a.req_valid=1; a.req=REQ_PUTM; a.wb=1; nt=TR_MI_A; end
rtl/mem/mesi_ctrl.sv:89            never       default: xv = 1'b1;    // LINE_O is unreachable: S6-1 rules MESI
rtl/ooo/rob.sv:129                 guard       if (slot_ok && (ce.is_csr || ce.is_mret || ce.is_fence || ce.is_fence_
rtl/common/rv32i_pkg.sv:166        norec       typedef enum logic [11:0] {
tb/uvm/top/tb_top.sv:70           norec       cluster u_dut (
```
<!-- END CITATION ROSTER -->
