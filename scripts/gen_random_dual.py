#!/usr/bin/env python3
# Random self-checking dual-hart program generator.
#
# Two harts share NLINES cache lines with interleaved word ownership: hart h
# owns the words whose index is congruent to h mod 2, so every line is falsely
# shared all the time. Each hart's own words are written with random sizes and
# values and read back against the value the generator tracked, so no reference
# simulator is needed. Peer words are checked for what the memory model does
# promise: a monotone word written by its owner with increasing values must
# never appear to go backwards, and two same-address loads in program order
# (the older delayed by a divide so the younger runs first) must not observe
# the older value ahead of the younger. Two LR/SC counters are incremented by
# both harts and checked for their exact total. Fences, fence.i, divides and an
# optional timer interrupt storm are mixed in. Any check failing returns
# (hart+1) through crt0's OR and records the failing op index in a private word.
import argparse, random, sys

NLINES = 2          # falsely shared data lines
LINE_W = 16         # words per line
CTR_OFF = NLINES * 64          # the LR/SC counter line follows the data lines
PRIV_OFF = CTR_OFF + 64        # one private line per hart after that

def s32(v):
    v &= 0xffffffff
    return v - (1 << 32) if v & 0x80000000 else v

class Gen:
    def __init__(self, seed, nops, irq, reps):
        self.r = random.Random(seed)
        self.nops = nops
        self.irq = irq
        self.reps = reps
        self.out = []
        self.lbl = 0

    def e(self, s):
        self.out.append(s)

    def label(self):
        self.lbl += 1
        return "L%d" % self.lbl

    def delay(self, n):
        l = self.label()
        self.e("  li   t6, %d" % n)
        self.e("%s:" % l)
        self.e("  addi t6, t6, -1")
        self.e("  bnez t6, %s" % l)

    def hart(self, h):
        r = self.r
        peer = 1 - h
        own_words = [(ln, w) for ln in range(NLINES) for w in range(LINE_W) if w % 2 == h]
        mono = {(0, h), (1, h)}                 # this hart's monotone words
        peer_mono = [(0, peer), (1, peer)]
        plain = [x for x in own_words if x not in mono]
        exp = {x: 0 for x in own_words}          # tracked word values
        mono_val = {m: 0 for m in mono}
        incs = [0, 0]                            # this hart's LR/SC increments per counter
        e = self.e
        e("hart%d:" % h)
        e("  li   s2, 0")                        # last seen peer monotone 0
        e("  li   s3, 0")                        # last seen peer monotone 1
        e("  li   s11, 1")                       # divisor for the slow address copy
        e("  li   s5, 0")
        e("  li   s6, 0")
        if self.irq:
            e("  la   t0, handler")
            e("  csrw mtvec, t0")
            e("  csrw mscratch, zero")
            e("  li   s8, 0x02004000")
            e("  addi s8, s8, %d" % (8 * h))
            e("  li   s9, 0x0200BFF8")
            e("  li   t0, -1")
            e("  sw   t0, 4(s8)")
            e("  lw   t0, 0(s9)")
            e("  addi t0, t0, 12")
            e("  sw   t0, 0(s8)")
            e("  sw   zero, 4(s8)")
            e("  li   t0, 0x80")
            e("  csrs mie, t0")
            e("  csrsi mstatus, 8")
        e("  li   a2, %d" % self.reps)
        e("rep%d:" % h)
        for (ln, w) in plain:                    # every repetition starts from a known state
            e("  sw   zero, %d(s0)" % (ln * 64 + w * 4))
        for idx in range(self.nops):
            op = r.choices(["st", "ld", "mono", "peer", "corr", "lrsc", "fence", "arith", "delay"],
                           weights=[30, 20, 8, 18, 6, 6, 3, 4, 5])[0]
            e("  li   a1, %d" % idx)
            if op == "st":
                ln, w = r.choice(plain)
                off = ln * 64 + w * 4
                size = r.choice(["sb", "sh", "sw"])
                if size == "sb":
                    bo = r.randrange(4); val = r.randrange(256)
                    cur = exp[(ln, w)]
                    cur = (cur & ~(0xff << (8 * bo))) | (val << (8 * bo))
                    exp[(ln, w)] = cur & 0xffffffff
                    e("  li   t0, %d" % val)
                    e("  sb   t0, %d(s0)" % (off + bo))
                elif size == "sh":
                    bo = r.choice([0, 2]); val = r.randrange(65536)
                    cur = exp[(ln, w)]
                    cur = (cur & ~(0xffff << (8 * bo))) | (val << (8 * bo))
                    exp[(ln, w)] = cur & 0xffffffff
                    e("  li   t0, %d" % val)
                    e("  sh   t0, %d(s0)" % (off + bo))
                else:
                    val = r.getrandbits(32)
                    exp[(ln, w)] = val
                    e("  li   t0, %d" % s32(val))
                    e("  sw   t0, %d(s0)" % off)
            elif op == "ld":
                ln, w = r.choice(plain)
                off = ln * 64 + w * 4
                cur = exp[(ln, w)]
                size = r.choice(["lb", "lbu", "lh", "lhu", "lw"])
                if size in ("lb", "lbu"):
                    bo = r.randrange(4); b = (cur >> (8 * bo)) & 0xff
                    want = (b - 256 if (size == "lb" and b & 0x80) else b)
                    e("  %s  t0, %d(s0)" % (size, off + bo))
                elif size in ("lh", "lhu"):
                    bo = r.choice([0, 2]); hw = (cur >> (8 * bo)) & 0xffff
                    want = (hw - 65536 if (size == "lh" and hw & 0x8000) else hw)
                    e("  %s  t0, %d(s0)" % (size, off + bo))
                else:
                    want = s32(cur)
                    e("  lw   t0, %d(s0)" % off)
                e("  li   t1, %d" % want)
                e("  bne  t0, t1, fail")
            elif op == "mono":
                m = r.choice(sorted(mono))
                mono_val[m] += 1
                reg = "s5" if m[0] == 0 else "s6"
                e("  addi %s, %s, 1" % (reg, reg))
                e("  sw   %s, %d(s0)" % (reg, m[0] * 64 + m[1] * 4))
            elif op == "peer":
                k = r.randrange(2)
                m = peer_mono[k]
                last = "s2" if k == 0 else "s3"
                e("  lw   t0, %d(s0)" % (m[0] * 64 + m[1] * 4))
                e("  bltu t0, %s, fail" % last)
                e("  mv   %s, t0" % last)
            elif op == "corr":
                k = r.randrange(2)
                m = peer_mono[k]
                last = "s2" if k == 0 else "s3"
                off = m[0] * 64 + m[1] * 4
                e("  divu t3, s0, s11")           # t3 = s0, late
                e("  lw   t4, %d(t3)" % off)      # older load, address late
                e("  lw   t5, %d(s0)" % off)      # younger load, runs first
                e("  bgtu t4, t5, fail")          # older may not see a newer value
                e("  bltu t4, %s, fail" % last)
                e("  mv   %s, t5" % last)
            elif op == "lrsc":
                c = r.randrange(2)
                incs[c] += 1
                l = self.label()
                e("%s:" % l)
                e("  lr.w t0, (%s)" % ("s7" if c == 0 else "s10"))
                e("  addi t0, t0, 1")
                e("  sc.w t1, t0, (%s)" % ("s7" if c == 0 else "s10"))
                e("  bnez t1, %s" % l)
            elif op == "fence":
                e("  fence.i" if r.random() < 0.3 else "  fence rw, rw")
            elif op == "arith":
                a = r.getrandbits(32); b = r.randrange(1, 1 << 16)
                kind = r.choice(["mul", "divu", "remu", "mulhu"])
                if kind == "mul":   want = (a * b) & 0xffffffff
                elif kind == "divu": want = a // b
                elif kind == "remu": want = a % b
                else:                want = (a * b) >> 32
                e("  li   t0, %d" % s32(a))
                e("  li   t1, %d" % b)
                e("  %s t2, t0, t1" % kind)
                e("  li   t1, %d" % s32(want))
                e("  bne  t2, t1, fail")
            else:
                self.delay(r.randrange(1, 12))
        e("  addi a2, a2, -1")
        e("  bnez a2, rep%d" % h)
        # final state of every own word
        e("  li   a1, %d" % self.nops)
        for (ln, w) in own_words:
            want = mono_val[(ln, w)] * self.reps if (ln, w) in mono else exp[(ln, w)]
            e("  lw   t0, %d(s0)" % (ln * 64 + w * 4))
            e("  li   t1, %d" % s32(want))
            e("  bne  t0, t1, fail")
        if self.irq:
            e("  csrci mstatus, 8")
            e("  csrr t0, mscratch")
            e("  beqz t0, fail2")
        return incs

    def program(self):
        e = self.e
        e("// generated by scripts/gen_random_dual.py; do not edit")
        e("  .section .text")
        e("  .globl main")
        e("main:")
        e("  la   s0, shared")
        e("  mv   s4, a0")
        e("  slli t0, a0, 6")
        e("  addi t0, t0, %d" % PRIV_OFF)
        e("  add  s1, s0, t0")
        e("  addi s7, s0, %d" % CTR_OFF)
        e("  addi s10, s0, %d" % (CTR_OFF + 4))
        e("  bnez a0, hart1")
        i0 = self.hart(0)
        e("  j    finish")
        i1 = self.hart(1)
        e("finish:")
        tot0 = (i0[0] + i1[0]) * self.reps; tot1 = (i0[1] + i1[1]) * self.reps
        # each hart waits, bounded, for both counters to reach their totals
        e("  li   t3, %d" % tot0)
        e("  li   t4, %d" % tot1)
        e("  li   t5, 20000")
        e("W1:")
        e("  lw   t0, 0(s7)")
        e("  lw   t1, 0(s10)")
        e("  bne  t0, t3, W2")
        e("  beq  t1, t4, done")
        e("W2:")
        e("  addi t5, t5, -1")
        e("  bnez t5, W1")
        e("  li   a0, 8")
        e("  ret")
        e("done:")
        e("  li   a0, 0")
        e("  ret")
        e("fail:")
        e("  sw   a1, 0(s1)")
        e("  addi a0, s4, 1")
        e("  ret")
        e("fail2:")
        e("  li   a0, 16")
        e("  ret")
        if self.irq:
            e("  .align 4")
            e("handler:")
            e("  addi sp, sp, -16")
            e("  sw   t0, 0(sp)")
            e("  sw   t1, 4(sp)")
            e("  csrr t0, mscratch")
            e("  addi t0, t0, 1")
            e("  csrw mscratch, t0")
            e("  lw   t1, 8(s1)")                 # a private word, touched under interrupt
            e("  addi t1, t1, 1")
            e("  sw   t1, 8(s1)")
            e("  lw   t1, 0(s9)")
            e("  addi t1, t1, 10")
            e("  sw   t1, 0(s8)")
            e("  lw   t1, 4(sp)")
            e("  lw   t0, 0(sp)")
            e("  addi sp, sp, 16")
            e("  mret")
        e("  .section .data")
        e("  .align 6")
        e("  .globl shared")
        e("shared: .fill %d, 1, 0" % (PRIV_OFF + 128))
        return "\n".join(self.out) + "\n"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--nops", type=int, default=400)
    ap.add_argument("--irq", action="store_true")
    ap.add_argument("--reps", type=int, default=8)
    ap.add_argument("-o", required=True)
    a = ap.parse_args()
    open(a.o, "w").write(Gen(a.seed, a.nops, a.irq, a.reps).program())

if __name__ == "__main__":
    main()
