#!/usr/bin/env bash
set -uo pipefail

VERILATOR=${VERILATOR:-/opt/verilator-5.050/bin/verilator}
UVM_SRC=${UVM_HOME:-/opt/uvm}/src
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=${GATE_WORK:-/opt/gates/work}
JOBS=${JOBS:-$(nproc)}
mkdir -p "$WORK"

BUILD_ONLY=0; RUN_A=1; RUN_B=1
for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=1 ;;
    --gate-a)     RUN_B=0 ;;
    --gate-b)     RUN_A=0 ;;
  esac
done

echo "=============================================================="
echo " verilator : $("$VERILATOR" --version 2>&1)"
echo " uvm src   : $UVM_SRC"
echo " jobs      : $JOBS"
echo "=============================================================="

gate_a() {
  echo
  echo "### GATE A -- UVM smoke test ###"
  cd "$WORK"
  echo "compiling uvm_pkg (~1,991 generated C++ files; one-time, then incremental)..."
  local t0 t1
  t0=$(date +%s)
  "$VERILATOR" --binary --timing -Wno-fatal -Wno-WIDTH -Wno-CASTCONST \
      --build-jobs "$JOBS" --vpi \
      -I"$UVM_SRC" "$UVM_SRC/uvm_pkg.sv" \
      "$UVM_SRC/dpi/uvm_dpi.cc" -CFLAGS "-I$UVM_SRC/dpi -DVERILATOR" \
      "$HERE/gate_a_uvm_smoke.sv" \
      --top-module uvm_smoke -Mdir "$WORK/obj_uvm" -o uvm_smoke \
      > "$WORK/gate_a_build.log" 2>&1
  local brc=$?
  t1=$(date +%s)
  echo "build exit=$brc in $((t1-t0))s"

  if [[ $brc -ne 0 ]]; then
    echo "GATE A: BUILD FAILED"
    grep -E "%Error" "$WORK/gate_a_build.log" | head -20
    return 1
  fi

  if [[ $BUILD_ONLY -eq 1 ]]; then
    echo "GATE A: built (not run -- --build-only)"
    return 0
  fi

  echo "--- running ---"
  timeout 120 "$WORK/obj_uvm/uvm_smoke" > "$WORK/gate_a_run.log" 2>&1
  local rrc=$?
  cat "$WORK/gate_a_run.log"

  if [[ $rrc -eq 124 ]]; then
    echo "GATE A: FAIL -- timed out (objection never dropped / phasing hang)"
    return 1
  fi
  if grep -q "UVM is alive on Verilator" "$WORK/gate_a_run.log" \
     && grep -q "GATE_A_RESULT: PASS"     "$WORK/gate_a_run.log"; then
    echo "GATE A: PASS"
    return 0
  fi
  echo "GATE A: FAIL"
  return 1
}

declare -a FEATURES=(
  "_scaffold_control"
  "bare_covergroup"
  "value_bins"
  "array_bins"
  "illegal_bins"
  "ignore_bins"
  "at_least"
  "wildcard_bins"
  "transition_bins"
  "cross"
  "cross_binsof"
  "coverpoint_iff"
  "sample_method"
  "get_coverage"
)

emit_probe() {
  local feat=$1 f="$WORK/probe_$1.sv"
  cat > "$f" << 'HDR'
module probe;
  typedef enum logic [2:0] {INV, SH, EX, MOD, TRANS} state_e;
  state_e st; logic [3:0] ev; logic [1:0] hart; bit clk = 0;
HDR
  case "$feat" in
    _scaffold_control) : ;;   # no covergroup at all -- the control
    bare_covergroup) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk); cp : coverpoint st; endgroup
EOF
;;
    value_bins) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint st { bins i = {INV}; bins s = {SH}; bins e = {EX}; bins m = {MOD}; }
  endgroup
EOF
;;
    array_bins) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint ev { bins b[] = {[0:7]}; }
  endgroup
EOF
;;
    illegal_bins) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint st { bins ok = {INV, SH, EX, MOD}; illegal_bins bad = {TRANS}; }
  endgroup
EOF
;;
    ignore_bins) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint ev { bins used = {[0:7]}; ignore_bins unused = {[8:15]}; }
  endgroup
EOF
;;
    at_least) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint hart { bins h[] = {[0:1]}; option.at_least = 5; }
  endgroup
EOF
;;
    wildcard_bins) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint ev { wildcard bins even = {4'b???0}; wildcard bins odd = {4'b???1}; }
  endgroup
EOF
;;
    transition_bins) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint st { bins i2s = (INV => SH); bins s2m = (SH => MOD); }
  endgroup
EOF
;;
    cross) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp_s : coverpoint st { bins i = {INV}; bins s = {SH}; }
    cp_e : coverpoint ev { bins lo = {[0:3]}; bins hi = {[4:7]}; }
    x : cross cp_s, cp_e;
  endgroup
EOF
;;
    cross_binsof) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp_s : coverpoint st { bins i = {INV}; bins s = {SH}; }
    cp_e : coverpoint ev { bins lo = {[0:3]}; bins hi = {[4:7]}; }
    x : cross cp_s, cp_e { ignore_bins n = binsof(cp_s.i) && binsof(cp_e.hi); }
  endgroup
EOF
;;
    coverpoint_iff) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint st iff (hart == 0) { bins i = {INV}; bins s = {SH}; }
  endgroup
EOF
;;
    sample_method) cat >> "$f" << 'EOF'
  covergroup cg;
    cp : coverpoint st { bins i = {INV}; bins s = {SH}; }
  endgroup
EOF
;;
    get_coverage) cat >> "$f" << 'EOF'
  covergroup cg @(posedge clk);
    cp : coverpoint st { bins i = {INV}; bins s = {SH}; }
  endgroup
EOF
;;
  esac

  if [[ "$feat" != "_scaffold_control" ]]; then
    cat >> "$f" << 'FTR'
  cg cg_i = new();
FTR
  fi
  if [[ "$feat" == "sample_method" ]]; then
    cat >> "$f" << 'EOF'
  initial begin
    st = INV; ev = 0; hart = 0;
    repeat (8) begin st = state_e'((st+1) % 4); cg_i.sample(); end
    $display("PROBE_OK"); $finish;
  end
endmodule
EOF
  elif [[ "$feat" == "get_coverage" ]]; then
    cat >> "$f" << 'EOF'
  initial begin
    st = INV; ev = 0; hart = 0;
    repeat (8) begin #5 clk = 1; #5 clk = 0; st = state_e'((st+1) % 4); end
    $display("PROBE_OK cov=%0.2f inst=%0.2f", cg_i.get_coverage(), cg_i.get_inst_coverage());
    $finish;
  end
endmodule
EOF
  else
    cat >> "$f" << 'EOF'
  initial begin
    st = INV; ev = 0; hart = 0;
    repeat (8) begin #5 clk = 1; #5 clk = 0; st = state_e'((st+1) % 4); ev = ev + 1; hart = hart + 1; end
    $display("PROBE_OK"); $finish;
  end
endmodule
EOF
  fi
}

gate_b() {
  echo
  echo "### GATE B -- covergroup feature probe ###"
  echo "one feature per compile, so an unsupported construct cannot mask the rest"
  echo
  printf "%-20s %-12s %s\n" "FEATURE" "VERDICT" "NOTE"
  printf "%-20s %-12s %s\n" "-------" "-------" "----"
  local supported=() missing=()

  for feat in "${FEATURES[@]}"; do
    emit_probe "$feat"
    cd "$WORK"
    "$VERILATOR" --binary --timing --coverage-user -Wno-fatal -Wno-WIDTH \
        --build-jobs "$JOBS" "$WORK/probe_$feat.sv" --top-module probe \
        -Mdir "$WORK/obj_$feat" -o "probe_$feat" \
        > "$WORK/probe_$feat.log" 2>&1
    local rc=$? note="" verdict=""
    if [[ $rc -ne 0 ]]; then
      note=$(grep -m1 -oE "Unsupported: [^:]*" "$WORK/probe_$feat.log" | head -1)
      [[ -z "$note" ]] && note=$(grep -m1 "%Error" "$WORK/probe_$feat.log" | cut -c1-60)
      verdict="NO"
      missing+=("$feat")
    else
      timeout 60 "$WORK/obj_$feat/probe_$feat" > "$WORK/probe_${feat}_run.log" 2>&1
      if grep -q "PROBE_OK" "$WORK/probe_${feat}_run.log"; then
        verdict="YES"
        note=$(grep -m1 "PROBE_OK" "$WORK/probe_${feat}_run.log" | sed 's/PROBE_OK//' | xargs)
        supported+=("$feat")
      else
        verdict="COMPILE-ONLY"
        note="elaborates but did not run"
        missing+=("$feat")
      fi
    fi
    printf "%-20s %-12s %s\n" "$feat" "$verdict" "$note"

    if [[ "$feat" == "_scaffold_control" && "$verdict" != "YES" ]]; then
      echo
      echo "!! SCAFFOLD CONTROL FAILED -- the probe harness itself is broken."
      echo "!! Every row below would be meaningless. Fix run_gates.sh, not the DUT."
      sed -n '1,40p' "$WORK/probe__scaffold_control.log"
      return 1
    fi
  done

  echo
  echo "supported: ${supported[*]:-none}"
  echo "missing  : ${missing[*]:-none}"
  echo

  if printf '%s\n' "${missing[@]}" | grep -qx "illegal_bins"; then
    echo "!! illegal_bins UNSUPPORTED -- cov_coherence.sv cannot encode the eight"
    echo "!! unreachable C1 cells as illegal_bins. Fall back to an explicit SVA"
    echo "!! assertion per cell, or an ignore_bins + a separate always-block check."
    echo "!! This is a DESIGN INPUT for cov_coherence.sv, not a blocker."
  else
    echo "illegal_bins supported -- the natural C1 encoding is available."
  fi
  if printf '%s\n' "${missing[@]}" | grep -qx "cross"; then
    echo "!! cross UNSUPPORTED -- the both-hart cross and snoop x line-state cross"
    echo "!! must be hand-rolled as a concatenated coverpoint."
  fi
  GC=$(grep -m1 "PROBE_OK" "$WORK/probe_get_coverage_run.log" 2>/dev/null || true)
  if [[ -n "$GC" ]]; then
    ctype=$(sed -E 's/.*cov=([0-9.]+).*/\1/' <<< "$GC")
    cinst=$(sed -E 's/.*inst=([0-9.]+).*/\1/' <<< "$GC")
    echo "coverage API cross-check: get_coverage()=$ctype  get_inst_coverage()=$cinst"
    if [[ "$ctype" != "$cinst" ]]; then
      echo "!! TYPE AND INSTANCE COVERAGE DISAGREE."
      echo "!! Use get_inst_coverage() in cov_*.sv. get_coverage() is unreliable here."
      echo "!! Assert on this disagreement in the coverage files so that the day it"
      echo "!! is fixed upstream, you are told rather than silently keeping a"
      echo "!! workaround that has become wrong."
    else
      echo "   they agree -- get_coverage() may have been fixed; re-check cov_*.sv."
    fi
  fi

  if printf '%s\n' "${missing[@]}" | grep -qx "transition_bins"; then
    echo
    echo "transition_bins failed. If the log says 'Internal Error ... ENUMITEMREF',"
    echo "this is a Verilator CRASH on enum item references, not a missing feature."
    echo "Integer literals work:  bins i2s = (3'd0 => 3'd1);   NOT  (INV => SH)"
    echo "Use localparams for readability and leave a comment, or nobody will"
    echo "believe the literals are deliberate."
  fi

  return 0
}

RC=0
[[ $RUN_A -eq 1 ]] && { gate_a || RC=1; }
[[ $RUN_B -eq 1 && $BUILD_ONLY -eq 0 ]] && { gate_b || RC=1; }

echo
echo "=============================================================="
echo " gate logs: $WORK"
echo "=============================================================="
exit $RC
