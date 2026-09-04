#!/usr/bin/env bash
# Break the design on purpose and require a checker to go red.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

FILTER="${1:-}"
ORIG=""; TARGET=""
restore() {
  [[ -n "$TARGET" && -n "$ORIG" && -f "$ORIG" ]] && cp "$ORIG" "$TARGET" && rm -f "$ORIG"
  rm -f obj_uvm/sim_uvm
}
trap restore EXIT INT TERM

UNGRADED=""
MUT_ROWS=""
RED_WHY=""
EVIDENCE=""
IDS="m1_lrsc_no_snoop_clear m2_lrsc_arm_always m3_lrsc_sc_always_ok m4_trap_clr_tied m5_lrsc_refresh_no_hit \
m6_mesi_s_no_inv m7_mesi_m_no_wb m8_coh_shared_bit m9_dcache_store_gets \
m10_rob_viol_slot m11_rob_slot1_serialise m12_core_half_align \
m13_csr_mpp_writable m14_axi_axlen_short m15_branch_no_tgt_align \
m17_core_word_align m18_dcache_wb_clean m19_core_rvfi_order m20_coh_snoop_none \
m16_lsq_no_violation \
m21_core_rvfi_trap_novalid m22_coh_install_no_grant \
m23_mesi_s_reports_kept"

mut_file() { case "$1" in
  m1_lrsc_no_snoop_clear|m2_lrsc_arm_always|m3_lrsc_sc_always_ok|m5_lrsc_refresh_no_hit) echo rtl/mem/lrsc_unit.sv ;;
  m4_trap_clr_tied) echo rtl/ooo/cluster.sv ;;
  m6_mesi_s_no_inv|m7_mesi_m_no_wb) echo rtl/mem/mesi_ctrl.sv ;;
  m8_coh_shared_bit) echo rtl/mem/coherence_mgr.sv ;;
  m9_dcache_store_gets) echo rtl/mem/dcache.sv ;;
  m10_rob_viol_slot|m11_rob_slot1_serialise) echo rtl/ooo/rob.sv ;;
  m12_core_half_align) echo rtl/ooo/core.sv ;;
  m13_csr_mpp_writable) echo rtl/common/csr_regfile.sv ;;
  m14_axi_axlen_short) echo rtl/mem/axi_adapter.sv ;;
  m15_branch_no_tgt_align) echo rtl/common/branch_unit.sv ;;
  m16_lsq_no_violation) echo rtl/ooo/lsq.sv ;;
  m17_core_word_align) echo rtl/ooo/core.sv ;;
  m18_dcache_wb_clean) echo rtl/mem/dcache.sv ;;
  m19_core_rvfi_order) echo rtl/ooo/core.sv ;;
  m20_coh_snoop_none)  echo rtl/mem/coherence_mgr.sv ;;
  m21_core_rvfi_trap_novalid) echo rtl/ooo/core.sv ;;
  m22_coh_install_no_grant)   echo rtl/mem/dcache.sv ;;
  m23_mesi_s_reports_kept)    echo rtl/mem/mesi_ctrl.sv ;;
esac; }

mut_what() { case "$1" in
  m1_lrsc_no_snoop_clear) echo "a remote GetM no longer kills the reservation" ;;
  m2_lrsc_arm_always)     echo "drop acc_hit from the arm -- MEASURED to be a no-op" ;;
  m3_lrsc_sc_always_ok)   echo "every SC succeeds regardless of the reservation" ;;
  m4_trap_clr_tied)       echo "a trap no longer clears the reservation (the 2c-A2 defect)" ;;
  m5_lrsc_refresh_no_hit) echo "drop acc_hit from the S6-6.9 same-line REFRESH (line 224)" ;;
  m6_mesi_s_no_inv)       echo "a SHARED line is not invalidated by a remote GetM -- SWMR" ;;
  m7_mesi_m_no_wb)        echo "a MODIFIED line downgrades to S without writing back -- stale data" ;;
  m8_coh_shared_bit)      echo "the shared-bit ignores responders -- the requester installs E while a sharer lives" ;;
  m9_dcache_store_gets)   echo "a STORE miss issues GetS instead of GetM -- the two copies of the C1 request rule DISAGREE" ;;
  m10_rob_viol_slot)      echo "a violation-marked entry may retire (the S5-I.1 defect)" ;;
  m11_rob_slot1_serialise) echo "a CSR/mret/fence may retire in commit slot 1 (rob.sv:226)" ;;
  m12_core_half_align)    echo "halfword misalignment is not detected -- an unaligned lh/sh completes" ;;
  m13_csr_mpp_writable)   echo "mstatus.MPP becomes writable -- the WARL-zero rule broken" ;;
  m14_axi_axlen_short)    echo "AxLEN one beat short -- the burst ends before the line is filled" ;;
  m15_branch_no_tgt_align) echo "a misaligned branch target no longer traps" ;;
  m16_lsq_no_violation)   echo "the store->load violation CAM never fires -- speculative loads keep stale data" ;;
  m17_core_word_align)    echo "WORD misalignment is not detected -- the other half of the case m12 broke" ;;
  m18_dcache_wb_clean)    echo "a CLEAN victim is written back -- dirty data for a line never held in M" ;;
  m19_core_rvfi_order)    echo "rvfi_order stops incrementing -- the retirement-order checker's whole subject" ;;
  m20_coh_snoop_none)     echo "the ordering point snoops NOBODY -- no hart is told to invalidate" ;;
  m21_core_rvfi_trap_novalid) echo "rvfi_trap asserted on slot 0 every cycle, valid or not" ;;
  m22_coh_install_no_grant)   echo "a write-intent fill installs E even when the bus said SHARED" ;;
  m23_mesi_s_reports_kept)    echo "a SHARED line answers GetM with BtoB -- it REPORTS keeping its copy" ;;
esac; }

# EXPECT names the gates that MUST go red. Empty means EXPLORATORY -- no
# prediction, and the result is the finding either way. A mutation where the
# named gates stay green is what step 7 exists to discover.
mut_expect() { case "$1" in
  m1_lrsc_no_snoop_clear) echo "stress_lrsc" ;;
  m2_lrsc_arm_always)     echo "" ;;   # SEMANTIC NO-OP -- see below
  m3_lrsc_sc_always_ok)   echo "stress_lrsc" ;;
  m4_trap_clr_tied)       echo "uvm_lrsc_qtrap" ;;   # [4d] a DISCRIMINATING witness now exists
  m5_lrsc_refresh_no_hit) echo "" ;;   # exploratory: is this use load-bearing?
  m6_mesi_s_no_inv)       echo "swmr_cluster uvm_share" ;;
  # contend gives each hart DISJOINT memory, so it never downgrades a shared
  # line and cannot witness this. Second time a wrong EXPECT read as MISSED,
  # after m9 named uvm_base (fence-separated). NAME THE GATE WHOSE PROGRAM HAS
  # THE SCENARIO, not the one whose name sounds related.
  m7_mesi_m_no_wb)        echo "uvm_share uvm_excl" ;;
  m8_coh_shared_bit)      echo "swmr_cluster uvm_excl" ;;
  # CORRECTED AFTER MEASUREMENT, and the correction is the lesson.
  # This first named uvm_base, and the full battery then reddened ELEVEN gates
  # while uvm_base stayed green: mh.hex is fence-separated by crt0_multihart and
  # barely shares, so it is a WEAK witness for any coherence mutation. The
  # sharing programs are the strong ones. A wrong EXPECT reads as "missed" and
  # would have been written up as a hole in the battery.
  m9_dcache_store_gets)   echo "swmr_cluster uvm_share" ;;
  m10_rob_viol_slot)      echo "uvm_min_sl uvm_satviol" ;;
  m11_rob_slot1_serialise) echo "" ;;  # exploratory: does ANY program retire one in slot 1?
  m12_core_half_align)    echo "uvm_misalign" ;;
  # [REVIEW] m13 WAS THE ONE FIX GRADED BY ARGUMENT RATHER THAN BY THE MUTATION
  # THAT FOUND IT. Its row reads "fixed", not "caught", while m10, m12 and m16
  # were all re-run -- and this file's own rule is that "a fix graded by
  m13_csr_mpp_writable)   echo "uvm_csrprobe uvm_ral" ;;
  m17_core_word_align)    echo "uvm_misalign" ;;
  m18_dcache_wb_clean)    echo "uvm_share uvm_excl" ;;
  m19_core_rvfi_order)    echo "uvm_base" ;;
  m20_coh_snoop_none)     echo "uvm_share uvm_excl" ;;
  m21_core_rvfi_trap_novalid) echo "uvm_base" ;;
  m22_coh_install_no_grant)   echo "uvm_share uvm_excl" ;;
  m23_mesi_s_reports_kept)    echo "uvm_share uvm_excl" ;;
  m14_axi_axlen_short)    echo "uvm_base" ;;
  m15_branch_no_tgt_align) echo "uvm_misalign" ;;
  m16_lsq_no_violation)   echo "uvm_min_sl uvm_satviol" ;;
esac; }

mut_apply() { f=$(mut_file "$1"); case "$1" in
  m1_lrsc_no_snoop_clear)
     sed -i "s#if (snoop_clear\[h\] || trap_clear\[h\])#if (1'b0 \&\& (snoop_clear[h] || trap_clear[h]))#" "$f" ;;
  m2_lrsc_arm_always)
     sed -i "s#if (acc_hit\[h\] \&\& (cnt_q\[h\] == '0))#if ((cnt_q[h] == '0))#" "$f" ;;
  m3_lrsc_sc_always_ok)
     sed -i "s#assign sc_success\[h\] = sc_valid\[h\] \&\& rsv_valid\[h\]#assign sc_success[h] = sc_valid[h] \&\& 1'b1#" "$f" ;;
  m4_trap_clr_tied)
     sed -i "s#assign trp_clr\[h\] = core_trap_taken\[h\];#assign trp_clr[h] = 1'b0;#" "$f" ;;
  m5_lrsc_refresh_no_hit)
     sed -i "s#if (rsv_valid\[h\] \&\& acc_hit\[h\]#if (rsv_valid[h]#" "$f" ;;
  m6_mesi_s_no_inv)
     # TWO-LINE, and it has to be: `a.inv=1; ns=LINE_I; a.rsv_clear=1; end`
     # appears in the S row AND the E row. RSP_BtoN is unique to the S row, so
     # find that line and edit the NEXT one. A pattern that matched both would
     # mutate two rows and the result could not be attributed to either.
     # BOTH the invalidate AND the state change. The first version removed only
     # `a.inv=1;` and left `ns=LINE_I`, so the line was still invalidated and the
     # mutation changed NOTHING observable -- clean and mutated runs were
     # identical to the digit (424 samples, 848 backdoor checks, 417 inferred
     # evictions, same sim time). tb_mesi_ctrl still failed, because it checks
     # the ACTION STRUCT field by field, and that was misread as "the system
     # checkers cannot see a broken invalidation" when nothing was broken.
     # A MUTATION MUST BREAK WHAT ITS NAME CLAIMS, and byte-identical output is
     # the mechanical test that it did not.
     sed -i "/RSP_BtoN/{n; s#a.inv=1; ns=LINE_I; ##}" "$f" ;;
  m7_mesi_m_no_wb)
     sed -i "s#a.wb=1; ns=LINE_S; end#ns=LINE_S; end#" "$f" ;;
  m8_coh_shared_bit)
     sed -i "s#if (rsp_keeps_copy(snp_rsp\[h\])) shr_d = 1'b1;#if (1'b0) shr_d = 1'b1;#" "$f" ;;
  m9_dcache_store_gets)
     sed -i "s#: (mshr_wi_q ? REQ_GETM : REQ_GETS);#: (REQ_GETS);#" "$f" ;;
  m10_rob_viol_slot)
     sed -i "s#if (viol_q\[ROB_W'(h)\]) slot_ok = 1'b0;#if (1'b0) slot_ok = 1'b0;#" "$f" ;;
  m11_rob_slot1_serialise)
     sed -i "s#if (slot_ok \&\& (ce.is_csr || ce.is_mret || ce.is_fence || ce.is_fence_i))#if (1'b0)#" "$f" ;;
  m12_core_half_align)
     sed -i "s#MEM_H, MEM_HU:  mem_mis_ex = alu_result\[0\];#MEM_H, MEM_HU:  mem_mis_ex = 1'b0;#" "$f" ;;
  m13_csr_mpp_writable)
     sed -i "s#m\[MSTATUS_MPIE_BIT\] = v\[MSTATUS_MPIE_BIT\];#m[MSTATUS_MPIE_BIT] = v[MSTATUS_MPIE_BIT]; m[12:11] = v[12:11];#" "$f" ;;
  m14_axi_axlen_short)
     sed -i "s#assign axlen = word_q ? 8'd0 : 8'(BEATS - 1);#assign axlen = word_q ? 8'd0 : 8'(BEATS - 2);#" "$f" ;;
  m15_branch_no_tgt_align)
     sed -i "s#assign target_misaligned = taken \&\& (target\[1:0\] != 2'b00);#assign target_misaligned = 1'b0;#" "$f" ;;
  m16_lsq_no_violation)
     sed -i "s#          viol_valid  = 1'b1;#          viol_valid  = 1'b0;#" "$f" ;;
  m17_core_word_align)
     sed -i "s#MEM_W:          mem_mis_ex = (alu_result\[1:0\] != 2'b00);#MEM_W:          mem_mis_ex = 1'b0;#" "$f" ;;
  m18_dcache_wb_clean)
     sed -i "s#        if (needs_wb(tag_q\[mshr_idx_q\]\[mshr_way_q\].state)) begin#        if (1'b1) begin#" "$f" ;;
  # m19 -- rvfi_order stops advancing. rvfi_monitor::check_order is the checker
  # and it has never been shown able to fail.
  m19_core_rvfi_order)
     sed -i "s#      acc = acc + 64'((i == 0) ? (commit_o\[i\].valid || rvfi_exc_emit)#      acc = acc + 64'((i == 0) ? 1'b0#" "$f" ;;
  m20_coh_snoop_none)
     sed -i "s#          todo_d = '1;#          todo_d = '0;#" "$f" ;;

  m21_core_rvfi_trap_novalid)
     sed -i "s#rvfi_trap\[i\]     = (i == 0) \&\& rvfi_exc_emit;#rvfi_trap[i]     = (i == 0);#" "$f" ;;

  m22_coh_install_no_grant)
     sed -i "s#: mshr_wi_q                   ? (acq_shared_q ? LINE_S : LINE_E)#: mshr_wi_q                   ? LINE_E#" "$f" ;;

  m23_mesi_s_reports_kept)
     sed -i "s#EV_SNOOP_GETM: begin a.snp_resp=1; a.snp_rsp=RSP_BtoN;#EV_SNOOP_GETM: begin a.snp_resp=1; a.snp_rsp=RSP_BtoB;#" "$f" ;;
esac; }

grade_test()  { case "$1" in
  uvm_base) echo cpu_base_test:mh:200 ;;      uvm_share) echo cpu_share_test:share:100 ;;
  uvm_contend) echo cpu_contend_test:contend:20000 ;;
  uvm_stress) echo cpu_stress_test:stress:3000 ;;
  uvm_saturate) echo cpu_saturate_test:saturate:150000 ;;
  uvm_min_sl) echo cpu_base_test:min_sl:4000 ;;
  uvm_satviol) echo cpu_base_test:satviol:120000 ;;
  uvm_misalign) echo cpu_misalign_test:misalign:200 ;;
  uvm_memconv) echo cpu_memconv_test:memconv:150 ;;
  uvm_excl) echo cpu_base_test:excl:15000 ;;
  uvm_lrsc_qtrap) echo cpu_atomic_prog_test:lrsc_qtrap:150 ;;
  uvm_lrsc_conflict) echo cpu_atomic_prog_test:lrsc_conflict:20000 ;;
  uvm_lrsc_diffline) echo cpu_atomic_prog_test:lrsc_diffline:150 ;;
  uvm_csrprobe) echo 'cpu_csrprobe_test:csrprobe:-:86 CSR access\(es\)' ;;
  uvm_ral)      echo 'cpu_ral_test:csrprobe:-:REGISTER MODEL: [0-9]+ reset check' ;;
  *) echo "" ;;
esac; }

run_uvm_gate () {
  local g=$1 spec test prog floor want hex elf tpc cmp mis
  spec=$(grade_test "$g")
  if [[ -z "$spec" ]]; then
    echo "  !! GRADE_TEST HAS NO ENTRY FOR '$g' -- cannot grade this gate." >&2
    echo "     Add it to grade_test(), copying the criterion from" >&2
    echo "     run_regression.sh. Treating this as UNGRADED, not as green." >&2
    UNGRADED="$UNGRADED $g"
    return 1
  fi
  IFS=: read -r test prog floor want <<< "$spec"
  hex="asm/$prog.hex"; elf="asm/$prog.elf"
  local args="+UVM_TESTNAME=$test +HEX=$hex +TOHOST=80001000"
  [[ -f $elf ]] && args="$args +ELF=$elf"
  tpc=$(${NM:-riscv64-unknown-elf-nm} "$elf" 2>/dev/null | grep -w park_forever | awk '{print $1}')
  [[ -n $tpc ]] && args="$args +TRUNC_PC=$tpc"
  rm -f obj_uvm/verdict.txt
  timeout 900 ./obj_uvm/sim_uvm $args > obj_uvm/mut_$g.log 2>&1
  if [[ -n ${MUT_ID:-} ]]; then
    mkdir -p "obj_uvm/evidence/$MUT_ID"
    cp -f "obj_uvm/mut_$g.log" "obj_uvm/evidence/$MUT_ID/$g.log" 2>/dev/null
  fi
  RED_WHY=""; EVIDENCE=""
  scan_checkers "obj_uvm/mut_$g.log"
  if [[ ! -f obj_uvm/verdict.txt ]]; then
    add_why "no verdict (timeout or crash)"
  elif [[ $floor == "-" ]]; then
    grep -qE "$want" obj_uvm/mut_$g.log || add_why "known-count string absent"
  else
    mis=$(grep -oE "^ mismatches +[0-9]+" obj_uvm/verdict.txt | awk '{print $2}')
    cmp=$(grep -oE "^ CHECKED +[0-9]+"    obj_uvm/verdict.txt | awk '{print $2}')
    [[ -n $mis && $mis == 0 ]] || add_why "mismatches=${mis:-?}"
    [[ -n $cmp && $cmp -ge $floor ]] 2>/dev/null || add_why "CHECKED=${cmp:-?} below floor $floor"
  fi
  grep -q "UVM_FATAL :    0" obj_uvm/mut_$g.log || add_why "UVM_FATAL"
  [[ -n $RED_WHY ]] && return 0
  return 1
}

add_why () { RED_WHY="${RED_WHY:+$RED_WHY
}$1"; }
add_evidence () { EVIDENCE="${EVIDENCE:+$EVIDENCE
}$1"; }

scan_checkers () {
  local f=$1
  [[ -f $f ]] || return 0
  red_by "UVM_ERROR.*\[COV_LRSC\].*(ATOMICITY VIOLATION|reservation read VALID)" "$f"
  red_by "UVM_ERROR.*\[COV_COH\].*(ILLEGAL C1 cell|C1 EQUIVALENCE)"              "$f"
  red_by "UVM_ERROR.*\[COV_ISA\].*(COMMIT SLOT 1|OUTSIDE THE LINKED IMAGE)"      "$f"
  red_by "UVM_ERROR.*\[SYS_MON\]"                                                "$f"
  red_by "UVM_ERROR.*\[SB_RETIRE\].*deferrals exceeds the ceiling"               "$f"
  red_by "UVM_ERROR.*\[SB_COH\].*SWMR violated"                       "$f"   # coh: SWMR
  red_by "UVM_ERROR.*\[SB_COH\].*WRITEBACK of line"                   "$f"   # coh: writeback of an unowned line
  red_by "UVM_ERROR.*\[SB_COH\].*(unknown snoop response|unknown request)" "$f"  # coh: response/request encoding
  red_by "UVM_ERROR.*\[SB_COH\].*DISAGREEMENT: ordering point"        "$f"   # coh: ordering-point self-report (the VERDICT half)
  red_by "UVM_ERROR.*\[SNOOP_MON\].*(granted while a transaction|overlapping grants)" "$f"  # snoop: ordering-point atomicity
  red_by "UVM_ERROR.*\[SNOOP_MON\].*no req_installed"                 "$f"   # snoop: install timeout
  red_by "UVM_ERROR.*\[RVFI_MON\].*(order not increasing|order GAP)"  "$f"   # rvfi: retirement order
  red_by "UVM_ERROR.*\[RVFI_MON\].*rvfi_trap asserted"                "$f"   # rvfi: trap without valid
  red_by "UVM_ERROR.*\[MEM_MON\].*(with nothing outstanding|orphan B)" "$f"  # axi: orphan response bookkeeping
  red_by "UVM_ERROR.*\[MEM_MON\].*RLAST after"                        "$f"   # axi: RLAST vs AxLEN
  red_by "UVM_ERROR.*\[COV_ISA\].*byte mask"                          "$f"   # isa: malformed byte mask
  red_by "UVM_ERROR.*\[COV_ISA\].*contradict axi_adapter"             "$f"   # isa: AXI constants vs axi_adapter
  red_by "UVM_ERROR.*\[RAL\].*at reset, model says"                    "$f"   # csr: reset value
  red_by "UVM_ERROR.*\[RAL\].*is declared RO with reset"              "$f"   # csr: read-only field policy
  red_by "UVM_ERROR.*\[SB_CSR\]"                                        "$f"   # csr: predicted value vs hardware
  note_by "UVM_ERROR.*\[SB_COH\].*cache tag_q holds" "$f"                    # coh: silent acquire
  note_by "UVM_ERROR.*\[SB_COH\].*ordering point self-reported" "$f"       # coh: ordering-point self-report (evidence)
  note_by "UVM_ERROR.*\[SNOOP_MON\].*ordering point self-reported" "$f"    # coh: ordering-point self-report (per-run tally)
  note_by "UVM_ERROR.*\[COV_COH\].*implying it held" "$f"                    # coh: state never granted
  note_by "UVM_ERROR.*\[COV_COH\].*ILLEGAL C1 cell" "$f"                     # coh: illegal C1 cell
  note_by "UVM_ERROR.*\[COV_LRSC\].*SC (FAILED|SUCCEEDED)" "$f"              # lrsc: SC legality
  note_by "UVM_ERROR.*no tohost after [0-9]+ cycles" "$f"
}


escalation_why () {
  local gl=$1 g out=""
  for g in $gl; do
    case "$g" in uvm_*) ;; *) continue ;; esac   # cluster/unit gates write no uvm_*.log
    RED_WHY=""; EVIDENCE=""
    scan_checkers "obj_uvm/uvm_$g.log"
    [[ -n $RED_WHY$EVIDENCE ]] && out="$out$(emit_why "$g")"
  done
  [[ -n $out ]] && {
    echo "  why    : (recovered from the battery's per-gate logs)"
    echo "$out" | grep -v '^$'
    WHY_LOG="$WHY_LOG$out"
  }
  return 0
}

# Delete every per-gate battery log before a battery runs. A log left from an
# EARLIER run is indistinguishable from one this run wrote, and the earlier run
# may have been of a different, mutated design.
stale_logs_clear () { rm -f obj_uvm/uvm_uvm_*.log; }

# strip_artefact_gates -- remove gates that read an ARTEFACT rather than the DUT
# from $failed_gates, and REPORT them. ONE DEFINITION, called at every point
# failed_gates is (re)assigned.
#
# It was written inline, once, before the escalation -- and the escalation then
# overwrote failed_gates from the battery output, so the strip did not apply to
# the value the caught/missed decision actually reads. A mutation whose only red
# gate after a battery were uvm_docs would have scored CAUGHT having proven
# nothing: m11's defect, surviving inside m11's fix, one branch over.
#
# THE DEFECT IS "a gate that reads an ARTEFACT is not design evidence". The
# instances are whichever gates happen to fire that day, and the PLACES are
# wherever failed_gates gets a new value. Grep for both:
#   grep -n 'failed_gates=' scripts/run_mutations.sh
strip_artefact_gates () {
  local g
  for g in uvm_cites uvm_checkers uvm_proofs uvm_bins uvm_docs; do
    if echo "$failed_gates" | grep -qw "$g"; then
      DOC_AUDIT_RED="$DOC_AUDIT_RED $g"
      failed_gates=$(echo "$failed_gates" | sed "s/\\b$g\\b//g")
    fi
  done
  [[ -n ${DOC_AUDIT_RED// /} ]] && \
    echo "  note   : artefact gate(s) also red:$DOC_AUDIT_RED (NOT design evidence -- these read files, not the DUT)"
  return 0
}

# emit_why <gate> -- render RED_WHY, one indented line per reason.
emit_why () {
  local g=$1 w
  while IFS= read -r w; do
    [[ -z $w ]] && continue
    printf '\n    %s <- %s' "$g" "$w"
  done <<< "${RED_WHY:-<criterion, no error ID>}"
  while IFS= read -r w; do
    [[ -z $w ]] && continue
    printf '\n    %s .. %s' "$g" "$w"
  done <<< "${EVIDENCE:-}"
}

# red_by <pattern> <file> [evidence] -- APPEND every distinct matching line's ID
note_by () { red_by "${1/UVM_ERROR/UVM_(ERROR|WARNING|FATAL)}" "$2" evidence; }

red_by () {
  local pat=$1 f=$2 tag=${3:-} line
  line=$(grep -aoE "$pat" "$f" 2>/dev/null | head -1)
  [[ -z $line ]] && return 1
  line=$(echo "$line" | sed 's/^UVM_[A-Z]*[^[]*//' | cut -c1-70)
  if [[ -n $tag ]]; then
    line="[$tag] $line"
    grep -qxF -- "$line" <<< "$EVIDENCE" && return 0
    add_evidence "$line"
  else
    grep -qxF -- "$line" <<< "$RED_WHY" && return 0
    add_why "$line"
  fi
  return 0
}

line_verdict () {   # line_verdict <file> <line> -> DEAD | LIVE | UNKNOWN
  local f=$1 l=$2
  awk -v want_f="$f" -v want_l="$l" '
    BEGIN { SOH=sprintf("%c",1); STX=sprintf("%c",2); seen=0; tot=0 }
    /^#/ { next }
    {
      n=split($0,tok," "); cnt=tok[n]+0
      key=$0; sub(/^C '"'"'/,"",key); sub(/'"'"' *[0-9]+ *$/,"",key)
      delete F; m=split(key,parts,SOH)
      for (i=1;i<=m;i++) { if (parts[i]=="") continue
        j=index(parts[i],STX); if (j==0) continue
        F[substr(parts[i],1,j-1)]=substr(parts[i],j+1) }
      if (F["t"]=="covergroup") next
      if (F["f"]!=want_f || F["l"]+0!=want_l+0) next
      k=F["o"]
      # see the note above the function: SUM every record at the line
      seen=1; tot+=cnt
    }
    END { if (!seen) print "UNKNOWN"; else if (tot==0) print "DEAD"; else print "LIVE" }
  ' obj_uvm/cov/merged.dat
}

arm_warning () {   # arm_warning <file> <line>
  local f=$1 l=$2 z
  [[ -f obj_uvm/cov/merged.dat ]] || return 0
  z=$(awk -v want_f="$f" -v want_l="$l" '
    BEGIN { SOH=sprintf("%c",1); STX=sprintf("%c",2); n=0 }
    /^#/ { next }
    {
      k=split($0,tok," "); cnt=tok[k]+0
      key=$0; sub(/^C '"'"'/,"",key); sub(/'"'"' *[0-9]+ *$/,"",key)
      delete F; m=split(key,parts,SOH)
      for (i=1;i<=m;i++) { if (parts[i]=="") continue
        j=index(parts[i],STX); if (j==0) continue
        F[substr(parts[i],1,j-1)]=substr(parts[i],j+1) }
      if (F["t"]=="covergroup") next
      if (F["f"]!=want_f || F["l"]+0!=want_l+0) next
      if (cnt==0) n++
    }
    END { print n+0 }
  ' obj_uvm/cov/merged.dat)
  [[ ${z:-0} -gt 0 ]] && {
    echo "  .. NOTE: $f:$l carries $z record(s) with count 0 -- an ARM of this line"
    echo "     is never taken. If the mutation edits THAT arm the result is INERT,"
    echo "     not MISSED. Running it anyway; a warning here is not a verdict."
  }
  return 0
}

preflight_selftest () {
  local d live tern els bad=0
  [[ -f obj_uvm/cov/merged.dat ]] || {
    echo "  .. no merged.dat: the dead-line pre-flight is INACTIVE this run"
    echo "     (run ./scripts/cov_sweep.sh to arm it). Not a failure, but every"
    echo "     mutation is graded without it."
    return 0; }
  # Four anchors re-derived from the current tree (the old line numbers predated
  # the pre-publication comment strip): one illegal x-cell that stays DEAD, three
  # ordinary lines that any run takes. Update these if the code at them moves.
  d=$(line_verdict    rtl/mem/mesi_ctrl.sv   73)
  live=$(line_verdict rtl/ooo/rob.sv        230)
  tern=$(line_verdict rtl/mem/axi_adapter.sv 72)
  els=$(line_verdict  rtl/mem/lrsc_unit.sv   60)
  echo "  pre-flight self-test: mesi_ctrl.sv:73=$d (want DEAD, an x-cell)  rob.sv:230=$live (want LIVE)"
  echo "                        axi_adapter.sv:72=$tern (want LIVE)  lrsc_unit.sv:60=$els (want LIVE)"
  [[ $d    == DEAD ]] || bad=1
  [[ $live == LIVE ]] || bad=1
  [[ $tern == LIVE ]] || bad=1
  [[ $els  == LIVE ]] || bad=1
  [[ $bad == 0 ]] && return 0
  echo "  !! THE DEAD-LINE PRE-FLIGHT CANNOT DISCRIMINATE. Refusing to use it:"
  echo "     a check that cannot report both answers reports neither. Fix it, or"
  echo "     re-derive the four lines if the design has changed. A LIVE case that"
  echo "     reads DEAD is the dangerous direction -- it discards evidence."
  return 1
}

scan_selftest () {
  local g=obj_uvm/__scan_selftest.log rc=0 n
  mkdir -p obj_uvm
  cat > "$g" <<'LOG'
UVM_ERROR tb/uvm/sys/sys_monitor.sv(203) @ 1: uvm_test_top.env [SYS_MON] program reported 00000003, expected 00000001 (test)
UVM_ERROR tb/uvm/rvfi/rvfi_monitor.sv(160) @ 2: uvm_test_top.env [RVFI_MON] hart 0 order GAP: 91 after 44 -- 46 retirements lost
UVM_ERROR tb/uvm/snoop/snoop_monitor.sv(140) @ 3: uvm_test_top.env [SNOOP_MON] no req_installed within 200 cycles of completion
UVM_ERROR tb/uvm/sb/sb_coherence.sv(360) @ 4: uvm_test_top.env [SB_COH] line 00003100 hart 0: cache tag_q holds LINE_S but the shadow model has LINE_I
UVM_ERROR tb/uvm/sb/sb_coherence.sv(298) @ 5: uvm_test_top.env [SB_COH] SWMR violated on line 00003100 after h0:GetM
UVM_WARNING tb/uvm/sb/sb_coherence.sv(431) @ 6: uvm_test_top.env [SB_COH] ordering point self-reported a violation: h0:GetM
LOG
  RED_WHY=""; EVIDENCE=""; scan_checkers "$g"

  grep -q '\[SYS_MON\]'                 <<< "$RED_WHY" || { echo "  !! scan self-test: a GATE-CRITERION error was not recorded as a reason"; rc=1; }
  grep -q 'order GAP'                   <<< "$RED_WHY" || { echo "  !! scan self-test: rvfi: retirement order is a GATE CRITERION now and was not recorded"; rc=1; }
  grep -q 'no req_installed'            <<< "$RED_WHY" || { echo "  !! scan self-test: snoop: install timeout is a GATE CRITERION now and was not recorded"; rc=1; }
  grep -q 'SWMR violated'               <<< "$RED_WHY" || { echo "  !! scan self-test: coh: SWMR was MASKED -- one pattern per mechanism"; rc=1; }
  n=$(grep -c . <<< "$RED_WHY")
  [[ $n == 4 ]] || { echo "  !! scan self-test: expected exactly 4 gate reasons, got $n"; rc=1; }

  grep -q '\[evidence\].*self-reported' <<< "$EVIDENCE" || { echo "  !! scan self-test: a WARNING-severity checker was not recorded -- 2 DESIGN sites are warnings by design"; rc=1; }

  grep -q 'cache tag_q holds'           <<< "$EVIDENCE" || { echo "  !! scan self-test: coh: silent acquire was not recorded as evidence"; rc=1; }
  grep -q 'cache tag_q holds'           <<< "$RED_WHY"  && { echo "  !! scan self-test: 'cache tag_q holds' LEAKED INTO THE GATE REASONS -- it fires 404x on a CORRECT run and would redden a good battery"; rc=1; }
  grep -q 'self-reported'               <<< "$RED_WHY"  && { echo "  !! scan self-test: the ordering-point EVIDENCE site leaked into the gate reasons"; rc=1; }

  cat > "$g" <<'LOG'
UVM_ERROR tb/uvm/cov/cov_lrsc.sv(707) @ 3: uvm_test_top.env [COV_LRSC] NO LR executed: nothing in this run exercised the atomics path at all
UVM_ERROR tb/uvm/sb/sb_coherence.sv(486) @ 4: uvm_test_top.env [SB_COH] only 9 quiescent samples (< 100). This scoreboard reported 0 violations
LOG
  RED_WHY=""; EVIDENCE=""; scan_checkers "$g"
  [[ -z $RED_WHY$EVIDENCE ]] || { echo "  !! scan self-test: ANTI-VACUOUS errors were recorded as findings:"; echo "$RED_WHY$EVIDENCE" | sed 's/^/     /'; rc=1; }
  RED_WHY=""; EVIDENCE=""; scan_checkers "obj_uvm/__no_such_log.log"
  [[ -z $RED_WHY$EVIDENCE ]] || { echo "  !! scan self-test: scanned something other than the file it was given"; rc=1; }
  rm -f "$g"
  RED_WHY=""; EVIDENCE=""
  [[ $rc == 0 ]] && echo "  scan self-test: 4 criteria recorded, evidence kept out of the reasons, anti-vacuous ignored, reads only the named log"
  return $rc
}

grader_control () {
  local g bad=0
  echo "=============================================================="
  echo "CONTROL -- the grader must read GREEN on the UNMUTATED design"
  ./scripts/gate_criteria_check.sh || {
    echo "  !! the fast grader and the battery do not admit the same errors."
    echo "     Grading a mutation on a criterion the battery does not use, or"
    echo "     missing one it does, is how a fixed defect gets re-reported as a"
    echo "     miss. Refusing to run."
    return 1; }
  preflight_selftest || return 1
  scan_selftest || return 1
  ./scripts/run_uvm.sh cpu_smoke_test > obj_uvm/mut_build.log 2>&1
  [[ -x obj_uvm/sim_uvm ]] || { echo "  !! control build failed"; return 1; }
  for g in uvm_base uvm_share uvm_stress uvm_min_sl uvm_misalign uvm_lrsc_qtrap; do
    RED_WHY=""; EVIDENCE=""
    if run_uvm_gate "$g"; then
      echo "  !! $g reads RED on a correct design"
      echo "$(emit_why "$g")" | grep -v '^$' | sed 's/^/    /'
      bad=1
    else echo "  $g green"; fi
  done
  [[ $bad == 0 ]] || { echo "  !! GRADER IS BROKEN -- refusing to run the campaign"; return 1; }
  echo "  control OK"
  return 0
}

run_cluster_gate () {
  local g=$1 out
  case "$g" in
    stress_lrsc)
      for lat in "0 0" "20 3"; do
        set -- $lat
        out=$(timeout 300 ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/stress.hex \
              +TOHOST=80001000 +DELAY=$1 +BEAT_DELAY=$2 2>&1)
        echo "$out" | grep -q "STRESS counter=128  SC-OK h0=64 h1=64" || return 0
        echo "$out" | grep -q "SC-ON-UNOWNED-LINE h0=0 h1=0"          || return 0
        echo "$out" | grep -q "SWMR-VIOLATIONS cluster-wide: 0"       || return 0
      done ;;
    swmr_cluster)
      for prog in mh share contend litmus_lrsc; do
        timeout 250 ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/$prog.hex \
          +TOHOST=80001000 +DELAY=10 +BEAT_DELAY=1 2>&1 \
          | grep -q "SWMR-VIOLATIONS cluster-wide: 0" || return 0
      done ;;
    *) return 1 ;;
  esac
  return 1
}

if [[ "${SKIP_CONTROL:-0}" != "1" ]]; then
  grader_control || exit 1
else
  echo "=============================================================="
  echo "!! SKIP_CONTROL=1 -- THE GRADER WAS NOT VERIFIED ON A CORRECT DESIGN."
  echo "   Every result below is UNGRADED, not caught and not missed. Debug use"
  echo "   only; never quote a campaign that printed this line."
fi

pass=0; fail=0; ROSTER=""
for id in $IDS; do
  if [[ -n "$FILTER" ]]; then
    keep=0
    for pat in ${FILTER//,/ }; do [[ "$id" == *"$pat"* ]] && keep=1; done
    [[ $keep == 0 ]] && continue
  fi
  file=$(mut_file "$id"); what=$(mut_what "$id"); expect=$(mut_expect "$id")

  echo "=============================================================="
  echo "MUTATION $id"
  echo "  breaks : $what"
  echo "  expect : ${expect:-<none named -- exploratory>}"

  TARGET="$file"; ORIG="${file}.mutorig"
  cp "$file" "$ORIG"
  mut_apply "$id"
  if [[ -f obj_uvm/cov/merged.dat ]]; then
    ln=$(diff "$ORIG" "$file" | sed -n 's/^\([0-9]*\)c.*/\1/p' | head -1)
    if [[ -n "$ln" ]]; then
      case "$(line_verdict "$file" "$ln")" in
        DEAD)
          echo "  !! VACUOUS: $file:$ln is NEVER EXECUTED in the coverage union."
          echo "     A mutation on a dead line cannot be detected by any checker, so"
          echo "     the result would say nothing. Closing it needs STIMULUS, not a checker."
          fail=$((fail+1)); ROSTER="$ROSTER $id:VACUOUS"; restore; TARGET=""; ORIG=""; continue ;;
        UNKNOWN)
          echo "  .. $file:$ln has NO coverage record (a continuous assign, or a file"
          echo "     cov_scope.vlt excludes). The dead-line pre-flight cannot speak."
          ;;
        LIVE)
          arm_warning "$file" "$ln" ;;
      esac
    fi
  fi
  if cmp -s "$file" "$ORIG"; then
    echo "  !! MUTATION DID NOT APPLY -- the pattern no longer matches."
    echo "     A FAILURE OF THIS SCRIPT, not a result: an unapplied mutation"
    echo "     makes every gate look correctly green."
    fail=$((fail+1)); ROSTER="$ROSTER $id:NOTAPPLIED"; restore; TARGET=""; ORIG=""; continue
  fi

  failed_gates=""; WHY_LOG=""; DOC_AUDIT_RED=""
  MUT_ID="$id"        # [REVIEW3] names the per-mutation evidence directory
  if [[ "${FAST:-0}" == "1" ]]; then
    echo "  grading: FAST (named gates + control), escalating to the full battery on a miss"
    ./scripts/run_uvm.sh cpu_smoke_test > obj_uvm/mut_build.log 2>&1
    if [[ ! -x obj_uvm/sim_uvm ]]; then
      echo "  result : DID NOT BUILD"
      fail=$((fail+1)); ROSTER="$ROSTER $id:NOBUILD"; restore; TARGET=""; ORIG=""; continue
    fi
    needs_cluster=0
    for g in $expect; do case "$g" in stress_lrsc|swmr_cluster|litmus|bench_par) needs_cluster=1 ;; esac; done
    if [[ $needs_cluster == 1 ]]; then
      echo "  ...... a CLUSTER gate is named; fast mode cannot grade those, going to the battery"
    else
      for g in $(echo $expect uvm_base | tr ' ' '\n' | awk 'NF && !seen[$0]++'); do
        RED_WHY=""; EVIDENCE=""
        if run_uvm_gate "$g"; then
          failed_gates="$failed_gates $g"
          WHY_LOG="$WHY_LOG$(emit_why "$g")"
        fi
      done
      echo "  red    : ${failed_gates:-<none>}"
      [[ -n $WHY_LOG ]] && { echo "  why    :"; echo "$WHY_LOG" | grep -v '^$'; }
    fi
    strip_artefact_gates
    esc=0
    for g in $expect; do echo "$failed_gates" | grep -qw "$g" || esc=1; done
    [[ -z "$expect" && -z "$failed_gates" ]] && esc=1
    if [[ $esc == 1 ]]; then
      echo "  ...... fast grading did not confirm; ESCALATING to the full battery"
      stale_logs_clear
      out=$(make regression 2>&1 | tail -40)
      echo "  result : $(echo "$out" | grep -oE "REGRESSION: pass=[0-9]+ fail=[0-9]+")"
      failed_gates=$(echo "$out" | sed -n "s/^REGRESSION: pass=[0-9]* fail=[0-9]* //p")
      echo "  red    : ${failed_gates:-<none>}"
      strip_artefact_gates
      escalation_why "$failed_gates"
    fi
  else
    stale_logs_clear
    out=$(make regression 2>&1 | tail -40)
    red=$(echo "$out" | grep -oE "REGRESSION: pass=[0-9]+ fail=[0-9]+" || echo "REGRESSION: ?")
    failed_gates=$(echo "$out" | sed -n "s/^REGRESSION: pass=[0-9]* fail=[0-9]* //p")
    echo "  result : $red"
    echo "  red    : ${failed_gates:-<none>}"
    strip_artefact_gates
    escalation_why "$failed_gates"
  fi

  ok=1
  for g in $expect; do
    echo "$failed_gates" | grep -qw "$g" || { echo "  MISSED : $g stayed GREEN"; ok=0; }
  done
  if [[ -z "$expect" && -z "$failed_gates" ]]; then echo "  MISSED : nothing went red"; ok=0; fi
  if [[ $ok -eq 1 ]]; then pass=$((pass+1)); ROSTER="$ROSTER $id:caught"
  else fail=$((fail+1)); ROSTER="$ROSTER $id:MISSED"; fi

  mev=$(echo "$WHY_LOG" | sed 's/^ *//' | grep -v '^$' | paste -sd'; ' - | cut -c1-160)
  [[ -z $mev ]] && mev="<gates only> ${failed_gates:-none}"
  MUT_ROWS="$MUT_ROWS
$id|$([[ $ok -eq 1 ]] && echo CAUGHT || echo MISSED)|$mev"

  if [[ "${KEEP:-0}" == "1" ]]; then echo "  KEEP=1: left applied"; trap - EXIT; exit 0; fi
  restore; TARGET=""; ORIG=""
done

echo "=============================================================="
echo "MUTATIONS: caught=$pass missed=$fail"
echo "ROSTER:$ROSTER"

MR=docs/mutation_roster.txt
if [[ -n ${MUT_ROWS// /} && -f $MR ]]; then
  tmp=$(mktemp)
  { grep '^#' "$MR"
    { grep -v '^#' "$MR" | grep -v '^$'
      echo "$MUT_ROWS" | grep -v '^$'
    } | awk -F'|' '{rows[$1]=$0} END{for (k in rows) print rows[k]}' | sort
  } > "$tmp"
  n=$(grep -vc '^#' "$tmp")
  if [[ $n -ge $(grep -vc '^#' "$MR") ]]; then
    mv "$tmp" "$MR"; chmod 644 "$MR"
    echo "ROSTER FILE: $MR updated ($n row(s)). Promote any MISSED that is"
    echo "             actually INERT by hand, with the measurement in the row."
  else
    rm -f "$tmp"
    echo "!! refusing to shrink $MR from $(grep -vc '^#' "$MR") to $n rows"
  fi
fi
if [[ -n ${UNGRADED// /} ]]; then
  echo "UNGRADED (grade_test has no entry -- NOT a miss, NO evidence):$UNGRADED"
fi
[[ $fail -eq 0 ]]
