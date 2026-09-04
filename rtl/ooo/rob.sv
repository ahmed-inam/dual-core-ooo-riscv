// 32-entry reorder buffer; retires up to two per cycle, in order.
module rob
  import rv32i_pkg::*;      // word_t, FU_BRANCH (uop ctrl fields)
  import core_cfg_pkg::*;
  import ooo_pkg::*;
(
  input  logic  clk,
  input  logic  rst_n,

  output logic                     allocatable,   // room for a FULL group
  input  logic [RENAME_W-1:0]      alloc_valid,
  input  uop_t [RENAME_W-1:0]      alloc_uop,
  input  logic [RENAME_W-1:0]      alloc_ferr = '0,   // instruction access fault
  output rob_ptr_t [RENAME_W-1:0]  alloc_id,      // slot i's assigned rob_id

  input  logic  [WAKEUP_W-1:0]     comp_valid,
  input  rob_ptr_t [WAKEUP_W-1:0]  comp_id,
  input  logic  [WAKEUP_W-1:0][31:0] comp_wdata,
  input  logic  [WAKEUP_W-1:0]     comp_exc,
  input  logic  [WAKEUP_W-1:0][3:0]  comp_cause,
  input  logic  [WAKEUP_W-1:0][31:0] comp_tval,

  input  logic                     commit_ready,  // consumer accepts this cycle
  input  logic                     commit_single,
  output commit_t [COMMIT_W-1:0]   commit_o,
  output logic [COMMIT_W-1:0]      free_valid,
  output preg_t [COMMIT_W-1:0]     free_preg,
  output logic [COMMIT_W-1:0]      store_release,
  input  logic                     viol_set,
  input  rob_ptr_t                 viol_set_id,
  output logic                     head_viol,
  output word_t                    head_pc,
  output logic                     exc_at_head,
  output logic [3:0]               exc_cause,
  output word_t                    exc_tval,
  output word_t                    exc_pc,

  input  logic                     walk_pop,
  output logic                     walk_valid,    // an entry exists to pop
  output rob_entry_t               walk_entry,
  output bp_snapshot_t             head_bsnap,    // the head's fetch-
  output logic [ROB_W:0]           tail_o,        // full tail pointer,
  input  logic                     restore_valid, // snapshot recovery:
  input  logic [ROB_W:0]           restore_tail,  //   tail rollback + bulk
  output rob_ptr_t                 walk_id,       // id of that entry --

  input  logic                     flush_all,

  output logic                     head_valid,
  output logic                     head_done,
  output logic                     head_is_mem,
  output logic                     head_is_csr,
  output logic                     head_is_fence,
  output logic                     head_is_fence_i,
  output logic                     head_is_mret,
  output rob_ptr_t                 head_id,

  output logic [ROB_W:0]           count
);

  typedef logic [ROB_W:0] rptr_t;                 // wrap bit above the index
  rptr_t head_q, tail_q;
  rob_entry_t e [ROB_N];

  assign count       = tail_q - head_q;
  assign head_id     = ROB_W'(head_q);
  assign head_valid  = (count != '0) && e[ROB_W'(head_q)].valid;
  assign head_done   = e[ROB_W'(head_q)].done;
  assign head_is_mem     = e[ROB_W'(head_q)].is_mem;
  assign head_is_csr     = e[ROB_W'(head_q)].is_csr;
  assign head_is_fence   = e[ROB_W'(head_q)].is_fence;
  assign head_is_fence_i = e[ROB_W'(head_q)].is_fence_i;
  assign head_is_mret    = e[ROB_W'(head_q)].is_mret;
  assign allocatable = (count <= (ROB_W+1)'(ROB_N - RENAME_W));

  always_comb begin
    automatic rptr_t t = tail_q;
    for (int i = 0; i < RENAME_W; i++) begin
      alloc_id[i] = ROB_W'(t);
      t = t + rptr_t'(alloc_valid[i]);
    end
  end

  always_comb begin
    automatic rob_entry_t he = e[ROB_W'(head_q)];
    exc_at_head = (count != '0) && he.valid && he.done && he.exc_valid;
    exc_cause   = he.exc_cause;
    exc_tval    = he.exc_tval;
    exc_pc      = he.pc;
  end

  logic [COMMIT_W-1:0] can_commit;
  always_comb begin
    automatic rptr_t h = head_q;
    automatic logic  go = commit_ready;
    automatic logic  mem_used = 1'b0;   // one memory release per cycle
    for (int i = 0; i < COMMIT_W; i++) begin
      automatic rob_entry_t ce = e[ROB_W'(h)];
      automatic logic slot_ok = go && ((tail_q - h) != '0) && ce.valid && ce.done;
      if (ce.exc_valid) slot_ok = 1'b0;           // never retire an excepting op
      if (viol_q[ROB_W'(h)]) slot_ok = 1'b0;
      if (commit_single && (i != 0)) slot_ok = 1'b0;  // cap at 1 in R_ACT
      if (ce.is_mem && mem_used) slot_ok = 1'b0;
      if ((ce.is_csr || ce.is_mret || ce.is_fence || ce.is_fence_i)
          && (i != 0))
        slot_ok = 1'b0;
      can_commit[i] = slot_ok;

      commit_o[i].valid      = slot_ok;
      commit_o[i].pc         = ce.pc;
      commit_o[i].instr      = ce.instr;
      commit_o[i].lrd        = ce.lrd;
      commit_o[i].lrs1       = ce.lrs1;
      commit_o[i].lrs2       = ce.lrs2;
      commit_o[i].rf_we      = ce.rf_we;
      commit_o[i].pdst       = ce.pdst;
      commit_o[i].stale_pdst = ce.stale_pdst;
      commit_o[i].is_store   = ce.is_store;
      commit_o[i].is_branch  = ce.is_branch;
      commit_o[i].is_mret    = ce.is_mret;
      commit_o[i].is_mem     = ce.is_mem;
      commit_o[i].wdata      = ce.wdata;

      free_valid[i]    = slot_ok && ce.rf_we;     // free the STALE name
      free_preg[i]     = ce.stale_pdst;
      store_release[i] = slot_ok && ce.is_store;

      if (slot_ok && ce.is_mem) mem_used = 1'b1;
      if (slot_ok && (ce.is_csr || ce.is_mret || ce.is_fence || ce.is_fence_i))
        go = 1'b0;
      else
        go = slot_ok;                             // in-order: stop at a gap
      h  = h + rptr_t'(slot_ok);
    end
  end

  logic [$clog2(COMMIT_W+1)-1:0] n_commit;
  always_comb begin
    n_commit = '0;
    for (int i = 0; i < COMMIT_W; i++)
      n_commit = n_commit + ($bits(n_commit))'(can_commit[i]);
  end

  assign walk_valid = (count != '0);
  assign walk_entry = e[ROB_W'(tail_q - rptr_t'(1))];
  assign walk_id    = ROB_W'(tail_q - rptr_t'(1));
  assign head_bsnap = e[ROB_W'(head_q)].bsnap;

  logic viol_q [ROB_N];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < ROB_N; i++) viol_q[i] <= 1'b0;
    end else begin
      for (int i = 0; i < RENAME_W; i++)
        if (alloc_valid[i]) viol_q[ROB_W'(tail_q + rptr_t'(i))] <= 1'b0;
      if (viol_set) viol_q[ROB_W'(viol_set_id)] <= 1'b1;
    end
  end
  assign head_viol = viol_q[ROB_W'(head_q)];
  assign head_pc   = e[ROB_W'(head_q)].pc;
  assign tail_o     = tail_q;

  logic [$clog2(RENAME_W+1)-1:0] n_alloc;
  always_comb begin
    n_alloc = '0;
    for (int i = 0; i < RENAME_W; i++)
      n_alloc = n_alloc + ($bits(n_alloc))'(alloc_valid[i]);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_q <= '0;
      tail_q <= '0;
      for (int i = 0; i < ROB_N; i++) e[i] <= '0;
    end else if (flush_all) begin
      head_q <= '0;
      tail_q <= '0;
      for (int i = 0; i < ROB_N; i++) e[i].valid <= 1'b0;
    end else begin
      for (int i = 0; i < RENAME_W; i++) begin
        if (alloc_valid[i]) begin
          e[alloc_id[i]] <= '{
            valid:      1'b1,
            done:       alloc_ferr[i]
                     || alloc_uop[i].ctrl.illegal
                     || alloc_uop[i].ctrl.is_ecall
                     || alloc_uop[i].ctrl.is_ebreak
                     || alloc_uop[i].ctrl.is_fence
                     || alloc_uop[i].ctrl.is_fence_i
                     || alloc_uop[i].ctrl.is_mret,
            pc:         alloc_uop[i].pc,
            instr:      alloc_uop[i].instr,
            lrd:        alloc_uop[i].lrd,
            lrs1:       alloc_uop[i].lrs1,
            lrs2:       alloc_uop[i].lrs2,
            rf_we:      alloc_uop[i].ctrl.rf_we && (alloc_uop[i].lrd != 5'd0),
            pdst:       alloc_uop[i].pdst,
            stale_pdst: alloc_uop[i].stale_pdst,
            is_store:   alloc_uop[i].ctrl.mem_we,
            is_mem:     alloc_uop[i].ctrl.mem_re || alloc_uop[i].ctrl.mem_we,
            is_branch:  (alloc_uop[i].ctrl.cf_type != CF_NONE),
            is_csr:     (alloc_uop[i].ctrl.csr_op != CSR_OP_NONE),
            is_fence:   alloc_uop[i].ctrl.is_fence,
            is_fence_i: alloc_uop[i].ctrl.is_fence_i,
            bsnap:      alloc_uop[i].pred.snapshot,
            is_mret:    alloc_uop[i].ctrl.is_mret,
            wdata:      '0,
            exc_valid:  alloc_ferr[i]
                     || alloc_uop[i].ctrl.illegal || alloc_uop[i].ctrl.is_ecall
                     || alloc_uop[i].ctrl.is_ebreak,
            exc_cause:  alloc_ferr[i]               ? 4'd1  :
                        alloc_uop[i].ctrl.illegal   ? 4'd2  :
                        alloc_uop[i].ctrl.is_ebreak ? 4'd3  :
                        alloc_uop[i].ctrl.is_ecall  ? 4'd11 : 4'd0,
            exc_tval:   alloc_ferr[i] ? alloc_uop[i].pc : 32'd0
          };
        end
      end
      for (int w = 0; w < WAKEUP_W; w++) begin
        if (comp_valid[w]) begin
          e[comp_id[w]].done  <= 1'b1;
          e[comp_id[w]].wdata <= comp_wdata[w];
          if (comp_exc[w]) begin
            e[comp_id[w]].exc_valid <= 1'b1;
            e[comp_id[w]].exc_cause <= comp_cause[w];
            e[comp_id[w]].exc_tval  <= comp_tval[w];
          end
        end
      end
      for (int i = 0; i < COMMIT_W; i++)
        if (can_commit[i])
          e[ROB_W'(head_q + rptr_t'(i))].valid <= 1'b0;
      head_q <= head_q + rptr_t'(n_commit);
      if (restore_valid) begin
        tail_q <= restore_tail;
        for (int i = 0; i < ROB_N; i++) begin
          automatic logic [ROB_W-1:0] age_i =
              ROB_W'(i) - ROB_W'(head_q);
          if (32'(age_i) >= 32'((ROB_W+1)'(restore_tail - head_q)))
            e[i].valid <= 1'b0;
        end
      end else if (walk_pop) begin
        e[ROB_W'(tail_q - rptr_t'(1))].valid <= 1'b0;
        tail_q <= tail_q - rptr_t'(1);
      end else begin
        tail_q <= tail_q + rptr_t'(n_alloc);
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && !flush_all) begin
      for (int i = 0; i < RENAME_W; i++)
        if (alloc_valid[i] && e[alloc_id[i]].valid)
          $fatal(1, "rob: alloc overwrites valid entry %0d", alloc_id[i]);
      for (int w = 0; w < WAKEUP_W; w++)
        if (comp_valid[w] && !e[comp_id[w]].valid)
          $fatal(1, "rob: completion for invalid entry %0d", comp_id[w]);
      for (int i = 0; i < COMMIT_W; i++)
        if (can_commit[i] && !e[ROB_W'(head_q + rptr_t'(i))].done)
          $fatal(1, "rob: committing entry %0d before done", i);
      if (walk_pop && !walk_valid)
        $fatal(1, "rob: walk_pop on empty");
      if (restore_valid && (walk_pop || (|alloc_valid)))
        $fatal(1, "rob: restore colliding with walk/alloc");
      if (walk_pop && (|alloc_valid))
        $fatal(1, "rob: walk and alloc in one cycle (sequencer bug)");
    end
  end
`endif

endmodule
