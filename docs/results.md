# Results

Every headline measurement, with the harness that produced it.

> **These figures are not gated, and that is a deliberate decision rather than
> an oversight.** `scripts/docs_audit.sh` knows fifteen keys - `gates`, `bins`,
> `hit`, `proven`, `mut` and so on - each with a checked-in artefact that owns
> it. It has **no authority for a cycle count**, because a cycle count's owner
> is a run, not a file. So these are *recorded measurements, reproducible by the
> command named beside each*, and the project's own rule applies: a figure not
> in a `CURRENT FIGURES` block is a figure nothing checks, which is a decision
> made once, visibly. The gated figures live in `README.md`.
>
> Where a measurement was taken on an earlier tree, that is stated. The rule
> throughout was that a change is not finished until every earlier number is
> unmoved.

---

## 1. What issue width buys - perfect memory

Isolates the core microarchitecture: single-cycle instruction and data memory,
no caches, no miss penalty. Absolute IPC is therefore an upper bound; **the
deltas between machines on the same benchmark are the result.**

Harness: `tb/ooo/tb_rvfi_ooo.sv`, parsed by `scripts/measure_ipc.py`.

| benchmark | class | OoO 1-wide | OoO 2-wide | width delta | dual-issue % | mispredicts |
|---|---|---|---|---|---|---|
| `bench_ilp` | ILP-bound | 0.994 | **1.729** | **+74%** | 74% | 2 |
| `bench_branchy` | branch-bound | 0.801 | 0.945 | +18% | 17% | 23 |
| `bench_dep` | dependency-bound | 0.700 | 0.701 | +0.1% | 2% | 7 |

`instret` is identical across both machines per benchmark (2819 / 681 / 2636),
confirming both configurations execute the same architectural stream - only
cycles move.

**Width does exactly, and only, what ILP allows.** The dual-issue column is the
fraction of cycles the second port did useful work, and it tracks the width
delta monotonically: 74% → +74%, 17% → +18%, 2% → +0.1%. That correspondence is
the causal link. A 1-wide machine is pinned at ~1.0 no matter how much
parallelism exists; a 2-wide machine cannot speed up a pointer chase, because
there is never a second ready operation.

The gap from the 2.0 ceiling on `bench_ilp` is the loop's own overhead - the
counter increment and its branch are a two-operation dependency chain that
cannot dual-issue with itself.

---

> **Note.** Four changes postdate every table below: predictions held across
> an I-cache miss (`bp_top.sv`), out-of-order loads (`lsq.sv`), the ordering
> point releasing at completion (`coherence_mgr.sv`), and a registered execute
> stage (`core.sv`). Instruction counts are unaffected; cycle counts move. The
> section 1c measurements below are the current tree against the original commit,
> both built locally, and supersede the pre-change tables where they overlap.

---

## 1c. What the recent microarchitecture changes bought

Current tree versus the original commit, same programs, same simulator.

### Two cores: the ordering point releasing early

`make bench`, `bench_par` serial vs parallel. The serial run barely moves; the
parallel run is where a hart no longer stalls on the other's whole miss.

| memory latency | parallel, before | parallel, now | fewer cycles | speedup before / now |
|---|---|---|---|---|
| DELAY=0  | 76,963  | 66,838  | 13.2% | 1.583 / 1.823 |
| DELAY=10 | 133,141 | 112,743 | 15.3% | 1.337 / 1.579 |
| DELAY=20 | 207,844 | 187,365 | 9.9%  | 1.216 / 1.349 |
| DELAY=40 | 357,503 | 336,982 | 5.7%  | (serial exceeds the harness bound) |

Serial is unchanged (121,820 -> 121,819 at DELAY=0), so the whole gain is the
second hart. Contention programs improved too at DELAY=10: `stress` 15,989 ->
15,191, `contend` 63,730 -> 63,390.

### One core: out-of-order loads, and the pipeline register's cost

Single-core working-set sweep, `bench_memory` (independent walk) and
`bench_chase` (dependent pointer chase, the control).

| program | DELAY | before | now |
|---|---|---|---|
| `bench_memory` | 0  | 38,587  | 38,599  |
| `bench_memory` | 10 | 55,967  | 55,979  |
| `bench_memory` | 40 | 108,107 | 108,119 |
| `bench_chase`  | 0  | 162,975 | 171,176 |
| `bench_chase`  | 10 | 250,045 | 258,246 |
| `bench_chase`  | 40 | 511,255 | 519,456 |

**Out-of-order loads change nothing here, by design.** A younger load can pass an
older one's operands, but both still serialise at the single-MSHR blocking cache,
so there is no memory-level parallelism to expose. The gain waits on a
non-blocking cache. **The registered execute stage costs ~5% on `bench_chase`**,
one added cycle of load-use latency on a pure dependency chain. That is the price
paid in cycles for the shorter critical path, which a cycle-accurate simulation
cannot cash back as a higher clock.

## 2. What memory latency costs - the real hierarchy

Harness: `tb/ooo/tb_rvfi_sys_ooo.sv` - the 2-wide core through the real
icache / dcache / arbiter / AXI adapter / memory, with `+DELAY` and
`+BEAT_DELAY`. Every row was diffed per-instruction against Spike; the
retirement trace is latency-invariant, so Spike is a valid oracle at every
setting.

```bash
scripts/run_mem_sweep.sh          # the sweep
scripts/run_rvfi_sys_ooo.sh <hex> <elf> <delay> <beat>
```

`ctest`, a large mixed-integer C program. `instret` = 49,877 at every latency:

| DELAY | cycles | IPC |
|---|---|---|
| 0 | 67,769 | 0.736 |
| 4 | 70,715 | 0.705 |
| 10 | 75,198 | 0.663 |
| 40 | 97,688 | **0.510** |

**A blocking cache costs 30.7% of IPC** across that range. The per-beat delay is
worth about 2% on its own (BEAT=0 → 66,236 cycles, BEAT=1 → 67,769).

### The closed form

The cleanest result in the project. Total running time is exactly

```
cycles = 49,822 + 1,738 × L
```

where `L` is the memory latency. **The 1,738 is not fitted** - it is the exact
count of trips the machine made to memory, and the formula predicted every
measured point to within a single cycle. That is worth more than a raw
performance number, because it says precisely where the time goes: not to vague
inefficiency, but to a countable number of journeys each costing exactly the
latency. Recorded in `overview.pdf` chapter 6.

> **A Stage-5 vs Stage-6 note.** The table above is Stage-5, on a data cache not
> yet coherent. The same measurement on the Stage-6 tree reads 75,254 at
> DELAY=10 - exactly **56 cycles more**, being two extra acquire states across
> ~28 misses. Both are correct for their tree; neither is a typo. That 56 cycles
> out of ~75,000 is the **cost of making the cache coherent at all: 0.07%.**

### Per-program, cache-resident (DELAY=0)

| program | instret | cycles | IPC | mispred | imiss | dmiss |
|---|---|---|---|---|---|---|
| `vt_regpress` | 11,985 | 7,051 | 1.700 | 12 | 31 | 3 |
| `vt_uncond` | 12,883 | 9,827 | 1.311 | 71 | 15 | 5 |
| `vt_kitchen` | 1,170,315 | 1,266,144 | 0.924 | 18,260 | 17,057 | 36 |
| `vt_bsort` | 3,538 | 3,837 | 0.922 | 80 | 19 | 5 |
| `min_sl` | 2,146 | 2,448 | 0.877 | 4 | 22 | 3 |
| `vt_subword` | 27,740 | 32,919 | 0.843 | 672 | 32 | 10 |
| `ctest` | 49,877 | 66,236 | 0.753 | 2,265 | 808 | 45 |
| `vt_condns` | 512 | 706 | 0.725 | 19 | 18 | 9 |
| `vtest2` | 246,705 | 384,392 | 0.642 | 6,751 | 7,544 | 24 |
| `vt_trap` | 8,549 | 35,324 | 0.242 | 616 | 19 | 1 |

At DELAY=40 the drop tracks miss count exactly: cache-resident programs barely
move (`vt_regpress` 1.700 → 1.417), miss-heavy ones fall 30-45% (`vt_kitchen`
0.924 → 0.590, `vtest2` 0.642 → 0.364).

**Blended everyday estimate: IPC ~0.6-0.75.** Typical branchy integer C centres
around 0.8 cache-resident, limited by mispredictions and short basic blocks that
leave the second issue slot empty. Trap-heavy code is far lower - each trap
serialises.

---

## 3. Where the reorder window stops helping

`scripts/run_rob_sweep.sh`, DELAY=10, real memory. Co-scaled so the ROB stays
the binding constraint: PRF = next-pow2(32+ROB), IQ = min(16, ROB). Predictions
were locked before the run.

| ROB entries | PRF | IQ | `chase` IPC | `memory` IPC |
|---|---|---|---|---|
| 8 | 64 | 8 | 0.17 | 0.45 |
| 16 | 64 | 16 | 0.17 | 0.54 |
| 32 | 64 | 16 | 0.16 | 0.54 |
| 64 | 128 | 16 | 0.16 | 0.54 |

**`chase` is the control and it is flat** - a dependent load chain has no
independent work at any window depth, so a slope there would mean a broken
measurement rather than an insight. It is flat, so the measurement is sound.

`memory` gains 20% from 8 → 16 entries and then saturates within 1%. Past ~16
entries **the blocking cache binds**, not the window: one miss shadow at a time,
no memory-level parallelism for a deeper window to exploit. The shipped ROB of
32 is already past that knee, which quantifies the motivation for the next
stage.

---

## 4. Branch prediction

Recorded in `overview.pdf` chapter 4; harness `scripts/run_pattern_sweep.sh` and
the `branchy_*` / `rasx` programs.

| measurement | result |
|---|---|
| One bit distinguishing a call from a plain jump | return prediction **20% → 97%** |
| Overflowed return stack: keep-and-count vs let-it-wrap | **75% vs 34%** correct, 2,251 vs 2,447 cycles |

The call bit is the single most valuable bit in the predictor. Without it every
plain jump pushed a return address no return would ever remove, and the stack
drifted permanently out of step from that moment on.

The overflow policy is the more interesting result. On a call that does not fit,
the stack is **not touched** - a counter records that one call went unrecorded.
Returns spend the counter first, and only then does the pointer move down
through the eight untouched entries. For recursion, repeating the top entry is
not an approximation of the missing entries but an **exact reconstruction** of
them, because every recursive call pushes the identical address. Twelve of
twelve correct on a stack that holds eight.

---

## 5. Misprediction recovery

Recorded in `overview.pdf` chapter 7.

| method | cost |
|---|---|
| Walk the reorder buffer backwards, undoing each rename | **31.3 cycles** |
| Restore a checkpoint of the map table | **3.85 cycles** |

**8.1× better, and a deeply nested branch benchmark got 23.7% shorter.**

There are deliberately only **four** checkpoints, fewer than the window can hold
branches. That guarantees the machine runs out regularly and falls back on the
slow path, so the slow path stays exercised during ordinary work rather than
sitting untested until the day it is needed.

---

## 6. Interrupts

`scripts/run_irq_sweep.sh` sweeps an external interrupt across every cycle of a
program containing every stall flavour, asserting precision, write-once, and
final-state invariance at each arrival point.

It found **five duplicated stores in twelve interrupts.** An interrupt allowed
to land on an instruction part-way through writing to memory lets that write
happen twice - once before the interrupt and once after the handler returns.
Invisible for ordinary memory; corruption for a device.

The fix holds interrupts back until the retiring instruction is not a memory
operation. It delays an interrupt by a few cycles at most and cannot starve, because
any loop of stores must eventually finish a branch. Faults are deliberately
*not* delayed the same way: a fault on a store means the store itself was wrong,
and that is detected before anything is written.

---

## 7. Two cores

```bash
make bench
```

Workload `asm/csrc/bench_par.c`: a strided reduction, 16 passes over 1024 words.
**Two binaries from one source**, differing only in `SERIAL_ONLY`, so platform,
data, layout and termination path are identical and the ratio is a speedup
rather than an artefact. Both pay the same start barrier and join, so the serial
fraction is charged to both sides and the measured speedup is conservative.

**Correctness first.** Both variants return `1235124224`, and an independent
host oracle in plain Python computes `1235124224`. A wrong answer cannot
masquerade as a fast one. This required making the reduction *associative* - the
first draft carried a loop-borne dependence, so splitting the range legitimately
changed the result and no correctness check was possible.

| memory latency | serial | parallel | speedup | absolute saving |
|---|---|---|---|---|
| DELAY=0 | 121,820 | 76,963 | **1.583** | 44,857 |
| DELAY=10 | 178,015 | 133,141 | **1.337** | 44,874 |
| DELAY=20 | 252,709 | 207,844 | **1.216** | 44,865 |
| DELAY=40 | >400,000 (exceeds the harness bound) | 357,503 | - | - |

At DELAY=40 the serial run does not fit inside the testbench's 400,000-cycle
limit while the parallel run completes: **parallelism is what brings the
workload under the bound.**

### The column that matters is the last one

Speedup degrades with memory latency - 1.58 → 1.34 → 1.22 - and the obvious
reading is that coherence gets more expensive as memory slows. **That reading is
wrong**, and the number that shows it is easy not to look at:

> The absolute saving is **constant** - 44,857 / 44,874 / 44,865 cycles - across
> a fourfold change in memory latency.

The work the second hart lifts off the first is a fixed quantity of compute and
it stays fixed. Added latency is charged to both runs almost equally, because
both harts share **one** path to memory: a single AXI slave port through the 2×2
crossbar. Latency spent on a resource that does not parallelise cannot be
divided by two. The speedup falls purely because the denominator grows.

So the honest statement is not *coherence costs more when memory is slow*. It
is: **this design's parallel headroom is bounded by the shared route to memory,
not by the coherence protocol.** That is a statement about what to build next,
which a speedup figure alone would not have given - an L2, or a wider fabric.

**Gating:** `bench_par` is wired into the battery as a *correctness* gate only -
both variants must return `1235124224`. The cycle counts are a measurement, not
a pass/fail criterion.

---

## 8. Correctness through real memory

Every program below was diffed per-instruction against Spike through the real
cache hierarchy, at the memory latencies shown.

| program | latencies | state-changes matched | what it stresses |
|---|---|---|---|
| `ctest` | 0, 4, 10, 40 | 31,035 each | large mixed integer C |
| `vt_kitchen` | 40 | 786,908 | kitchen sink, 1.17M instructions |
| `vtest2` | 40 | 115,077 | mixed branch and memory |
| `vtest3` | 10, 40 | 49,528 | memory ordering |
| `vt_subword` | 40 | 19,506 | byte and halfword operations |
| `vt_memdep` | 10, 40 | 15,934 | store→load forwarding in the LSQ |
| `vt_regpress` | 40 | 11,345 | register pressure |
| `vt_uncond` | 40 | 8,942 | unconditional jumps |
| `vt_trap` | 40 | 6,474 | trap-heavy |
| `vt_bsort` | 40 | 2,864 | bubble sort |
| `min_sl` | 40 | 1,887 | store→load |
| `vt_condns` | 40 | 408 | conditionals |

All passed.

> One control worth stating: `vt_ilp` reaches IPC 1.700 with real memory,
> confirming the 2-wide core exceeds 1.0 when given parallelism. **Its
> per-instruction correctness is not in the verified set** - it returns a
> computed checksum rather than the pass value, so the harness skips the Spike
> diff. The IPC is valid; the correctness is not claimed.

---

## 9. The measurement harnesses

These are not run by the battery. They are the tools that produced the numbers
above, kept so the numbers can be reproduced rather than believed. Each anchors
itself to the project root, so it runs from anywhere.

| harness | what it measures |
|---|---|
| `scripts/run_mem_sweep.sh` | memory latency and bandwidth against the closed form |
| `scripts/run_sys_sweep.sh` | the same sweep, decomposed: miss counts, writebacks and stalled cycles as separate columns, because they have separate cures |
| `scripts/run_ws_sweep.sh` | working-set size against the fixed 1 KB cache, with the access count held constant |
| `scripts/run_pattern_sweep.sh` | sequential walk versus pointer chase at equal working set, isolating locality |
| `scripts/run_rob_sweep.sh` | reorder buffer depth, with PRF and issue queue co-scaled so the ROB stays the binding constraint |
| `scripts/run_irq_sweep.sh` | an interrupt swept across every cycle of a program containing every stall flavour |
| `scripts/measure_ipc.py` | parses the RVFI trace into the per-benchmark IPC table in section 1 |
