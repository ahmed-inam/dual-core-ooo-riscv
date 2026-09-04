#!/usr/bin/env python3
# [S5-H] IPC measurement parser for tb_rvfi_ooo (perfect-memory). Parses the
# RVFI 'V ' trace lines (field[4]=rd, field[5]=hex value) for the benchmark's
# csrr readout registers, and the temp ISSUTIL counter (cyc2/cyc1/cyc0) if present.
# Register maps differ per benchmark -- see maps{} below. Usage: build
# obj_rvfi_ooo/tb_rvfi_ooo, then: python3 scripts/measure_ipc.py [bench ...]
import subprocess, re, sys
BIN="./obj_rvfi_ooo/tb_rvfi_ooo"
# per-benchmark csrr readout register maps (rd number -> meaning)
maps={
 'bench_ilp':    dict(cyc=20,ins=21,br=22,mis=23,stall=24,flush=25),
 'bench_branchy':dict(cyc=20,ins=21,br=22,mis=23,stall=24,flush=25),
 'bench_dep':    dict(cyc=20,ins=21,br=22,mis=23,stall=24,flush=25),
 # bench_chase uses a DIFFERENT map (x18=mcycle,x19=minstret) and reads mhpm7-10;
 # it also runs unbounded in the flat tb (params from mem) -- prefer bench_dep.
 'bench_chase':  dict(cyc=18,ins=19,br=26,mis=27,stall=24,flush=25),
}
lbl={'bench_ilp':'ILP-bound','bench_branchy':'branch-bound','bench_dep':'dependency-bound','bench_chase':'dependency-bound'}
def measure(hexf, m, timeout=15):
    subprocess.run(f"timeout {timeout} {BIN} +HEX=asm/{hexf}.hex > /tmp/_m.log 2>&1", shell=True)
    v={}; cyc2=None
    for l in open('/tmp/_m.log'):
        if l.startswith('V '):
            q=l.split()
            if len(q)>=6:
                try: v[int(q[4])]=int(q[5],16)
                except: pass
        elif 'ISSUTIL' in l:
            mm=re.search(r'cyc2=(\d+)',l); cyc2=int(mm.group(1)) if mm else None
    return v,cyc2
def main():
    benches=sys.argv[1:] or ['bench_ilp','bench_branchy','bench_dep']
    for b in benches:
        m=maps.get(b, maps['bench_ilp']); v,cyc2=measure(b,m)
        cyc=v.get(m['cyc']); ins=v.get(m['ins'])
        if not cyc: print(f"{b:14s} PARSE/RUN FAIL regs={sorted(v)[:8]}"); continue
        dual=f"{cyc2/cyc*100:.0f}%" if cyc2 else "0%(WIDTH=1 or no counter)"
        print(f"{b:14s} [{lbl.get(b,'?'):16s}] IPC={ins/cyc:.3f}  cyc={cyc:5d} ins={ins:5d} "
              f"mis={v.get(m['mis'])} stall={v.get(m['stall'])} dual={dual}")
if __name__=='__main__': main()
