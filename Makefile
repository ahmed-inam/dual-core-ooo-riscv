# A front door, not a build system: the harnesses in scripts/ are the authority
# and each is independently runnable. `make` alone lists the targets.

SHELL   := /bin/bash
SPIKE   ?= /opt/spike/bin/spike
GATES   ?= 92
BUILD   := build

export SPIKE

.PHONY: help
help:
	@echo "RV32IM dual-core OoO CPU --- targets"
	@echo
	@echo "  make verify         sim + coverage + audit + regression, cold  (~70 min)"
	@echo "  make sim            build obj_uvm/sim_uvm only"
	@echo "  make check          audit + regression -- assumes a swept tree"
	@echo "  make audit          9 file-level audits, no build          (seconds)"
	@echo "  make regression     full battery, $(GATES) gates           (~15 min warm)"
	@echo "  make dual           the four dual-core programs"
	@echo "  make stress         LR/SC + coherence stress across four memory latencies"
	@echo "  make litmus         litmus suite vs the herd memory model"
	@echo "  make rvfi           single-core RVFI-vs-Spike through the real memory system"
	@echo "  make rvfi-dual      per-hart RVFI-vs-Spike on the dual-core cluster"
	@echo "  make xbar           AXI4 crossbar suite"
	@echo "  make mesi-xcells    MESI cross-cell sweep"
	@echo "  make bench          the parallel benchmark, serial vs 2-way"
	@echo
	@echo "  make coverage       functional + line coverage sweep, 30 programs (~12 min)"
	@echo "  make mutations      the step-7 mutation campaign        (FAST=1 for one)"
	@echo "  make random         constrained-random seeds vs Spike   (N=8 to change)"
	@echo
	@echo "  make clean          remove obj_*, logs and generated programs"
	@echo
	@echo "  SPIKE=$(SPIKE)"
	@echo "  New here? README.md -- it covers the container and the layout."

.PHONY: sim
sim:
	@scripts/run_uvm.sh cpu_smoke_test

.PHONY: verify
verify: sim coverage check

.PHONY: check
check: audit regression

.PHONY: audit
audit:
	@scripts/audit_all.sh

.PHONY: regression
regression:
	@EXPECT_GATES=$(GATES) scripts/run_regression.sh

.PHONY: coverage
coverage:
	@scripts/cov_sweep.sh

MUT ?=
.PHONY: mutations
mutations:
	@scripts/run_mutations.sh $(MUT)

N ?= 8
.PHONY: random
random:
	@scripts/run_random.sh $(N)

.PHONY: dual
dual:
	@for p in mh share contend litmus_lrsc; do \
	  printf "%-12s " $$p; \
	  ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/$$p.hex +TOHOST=80001000 \
	    +DELAY=10 +BEAT_DELAY=1 2>&1 \
	    | grep -E "DUAL (DONE|TIMEOUT)|LITMUS obs|SWMR-VIOL" | tr '\n' ' '; \
	  echo; \
	done

.PHONY: stress
stress:
	@for d in "0 0" "10 1" "20 3" "40 7"; do set -- $$d; \
	  printf "DELAY=%-2s/%-1s " $$1 $$2; \
	  ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/stress.hex +TOHOST=80001000 \
	    +DELAY=$$1 +BEAT_DELAY=$$2 2>&1 \
	    | grep -E "STRESS counter=|SWMR-VIOL|DUAL TIMEOUT" | tr '\n' ' '; \
	  echo; \
	done

.PHONY: litmus
litmus:
	@scripts/run_litmus.sh mp sb lb mpf s lrsc

.PHONY: rvfi
rvfi:
	@RVFI_ISA=rv32ima_zicsr scripts/run_rvfi_sys_ooo.sh \
	    asm/lrsc_arch.hex asm/lrsc_arch.elf 10 1

.PHONY: rvfi-dual
rvfi-dual:
	@scripts/run_rvfi_dual.sh

.PHONY: xbar
xbar:
	@scripts/run_xbar.sh

.PHONY: mesi-xcells
mesi-xcells:
	@scripts/run_mesi_xcells.sh

.PHONY: bench
bench:
	@for v in ser par; do printf "%-4s " $$v; \
	  ./obj_tb_dual_ooo/tb_dual_ooo +HEX=asm/bench_par_$$v.hex +TOHOST=80001000 \
	    +DELAY=10 +BEAT_DELAY=1 2>&1 | grep -oE "DUAL cycles=[0-9]+"; \
	done
	@echo "full sweep and analysis: docs/results.md"

.PHONY: clean
clean:
	@rm -rf obj_* $(BUILD)
	@rm -f *.log coverage.dat
	@# run_regression.sh copies asm/*.hex to the root; remove only those copies.
	@for h in *.hex; do [ -e "asm/$$h" ] && rm -f "$$h"; done 2>/dev/null; true
	@# The rm above is root-relative and misses these; the battery writes both.
	@# asm/*.hex and asm/*.elf are SOURCE here, so they are never touched.
	@rm -rf asm/rand asm/obj_*
	@rm -f asm/*.log asm/*.bin
	@echo "cleaned build artifacts"
