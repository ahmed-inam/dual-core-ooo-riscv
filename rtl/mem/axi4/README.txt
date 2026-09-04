rtl/ = 15 synthesizable files (the crossbar). Bring these into rtl/mem/ in Phase 1.
tb/  = class-based UVM-style verification env (reference; re-verify in-context later).
Do NOT widen NUM_MASTERS beyond 2 (see axi4_pkg.sv CHK_TWO_MASTERS).
