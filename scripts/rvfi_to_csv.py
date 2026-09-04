#!/usr/bin/env python3
"""Convert tb_rvfi retirement lines to riscv-dv trace CSV."""
import argparse
import csv
import sys

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
       "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
       "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
       "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]

HEADER = ["pc", "instr", "gpr", "csr", "binary", "mode",
          "instr_str", "operand", "pad"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rvfi_log")
    ap.add_argument("out_csv")
    args = ap.parse_args()

    rows, total = 0, 0
    with open(args.rvfi_log) as f, open(args.out_csv, "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(HEADER)
        for line in f:
            parts = line.split()
            if len(parts) != 6 or parts[0] != "V":
                continue
            total += 1
            _, _order, pc, insn, rd, wdata = parts
            rd = int(rd)
            if rd == 0:
                continue                      # no architectural GPR write
            gpr = "{}:{}".format(ABI[rd], wdata.lower())
            w.writerow([pc.lower(), "", gpr, "", insn.lower(), "3",
                        "", "", ""])
            rows += 1
    print("rvfi_to_csv: {} retirements, {} gpr-writing rows".format(
        total, rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
