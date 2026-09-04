// Unit proof of the reorder buffer.
`timescale 1ns/1ps
module tb_rob;
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic allocatable;
  logic [RENAME_W-1:0] alloc_valid;
  uop_t [RENAME_W-1:0] alloc_uop;
  logic [RENAME_W-1:0] alloc_ferr = '0;
  rob_ptr_t [RENAME_W-1:0] alloc_id;
  logic [WAKEUP_W-1:0] comp_valid;
  rob_ptr_t [WAKEUP_W-1:0] comp_id;
  logic [WAKEUP_W-1:0][31:0] comp_wdata;
  logic [WAKEUP_W-1:0] comp_exc;
  logic [WAKEUP_W-1:0][3:0] comp_cause;
  logic [WAKEUP_W-1:0][31:0] comp_tval;
  logic commit_ready;
  logic commit_single;
  commit_t [COMMIT_W-1:0] commit_o;
  logic [COMMIT_W-1:0] free_valid, store_release;
  preg_t [COMMIT_W-1:0] free_preg;
  logic exc_at_head;
  logic viol_set; rob_ptr_t viol_set_id;
  logic head_viol; word_t head_pc; logic [3:0] exc_cause; word_t exc_tval, exc_pc;
  logic walk_pop, walk_valid; rob_entry_t walk_entry;
  logic flush_all;
  logic head_valid, head_done, head_is_mem, head_is_csr, head_is_fence;
  rob_ptr_t walk_id;
  bp_snapshot_t head_bsnap;
  logic [ROB_W:0] tail_o;
  logic restore_valid; logic [ROB_W:0] restore_tail;
  logic head_is_fence_i, head_is_mret;
  rob_ptr_t head_id;
  logic [ROB_W:0] count;

  rob dut (.*);

  int errors = 0;
  task chk(string s, logic c); if (!c) begin $display("FAIL %s", s); errors++; end endtask

  function automatic uop_t mk(int n, logic writes, logic store, logic illegal);
    uop_t u = '0;
    u.valid = 1;
    u.pc    = 32'h1000 + 32'(n) * 4;
    u.instr = 32'h0000_0013;
    u.lrd   = writes ? 5'((n % 30) + 1) : 5'd0;
    u.ctrl  = CTRL_NOP;
    u.ctrl.rf_we  = writes;
    u.ctrl.mem_we = store;
    u.ctrl.illegal = illegal;
    if (illegal) u.ctrl = CTRL_ILLEGAL;
    u.pdst       = preg_t'(32 + (n % 32));
    u.stale_pdst = preg_t'(n % 32);
    return u;
  endfunction

  task automatic idle();
    alloc_valid = '0; comp_valid = '0; comp_exc = '0;
    comp_cause = '0; comp_tval = '0; comp_wdata = '0; comp_id = '0;
    walk_pop = 0; viol_set = 0; viol_set_id = '0; flush_all = 0; commit_ready = 1; commit_single = 0;
    for (int i = 0; i < RENAME_W; i++) alloc_uop[i] = '0;
  endtask

  task automatic alloc1(input uop_t u, output rob_ptr_t id);
    @(negedge clk);
    alloc_uop[0] = u; alloc_valid[0] = 1;
    #1 id = alloc_id[0];
    @(negedge clk);
    alloc_valid[0] = 0;
  endtask

  task automatic comp1(input rob_ptr_t id, input logic [31:0] w);
    @(negedge clk);
    comp_id[0] = id; comp_wdata[0] = w; comp_valid[0] = 1;
    @(negedge clk);
    comp_valid[0] = 0;
  endtask

  rob_ptr_t ids [64];
  int retired_n;
  word_t last_pc;
  uop_t u;

  always @(posedge clk) if (rst_n) begin
    for (int i = 0; i < COMMIT_W; i++)
      if (commit_o[i].valid) begin
        if (retired_n > 0 && commit_o[i].pc <= last_pc) begin
          $display("FAIL retirement order: pc %h after %h", commit_o[i].pc, last_pc);
          errors++;
        end
        last_pc   = commit_o[i].pc;
        retired_n = retired_n + 1;
      end
  end

  initial begin
    idle(); retired_n = 0; last_pc = '0;
    #12 rst_n = 1;
    @(negedge clk);

    for (int n = 0; n < 6; n++) alloc1(mk(n, 1, 0, 0), ids[n]);
    chk("count 6", count == (ROB_W+1)'(6));
    comp1(ids[5], 32'd105);
    comp1(ids[2], 32'd102);
    @(negedge clk);
    chk("nothing retired before head done", retired_n == 0);
    comp1(ids[0], 32'd100);
    comp1(ids[4], 32'd104);
    comp1(ids[1], 32'd101);
    comp1(ids[3], 32'd103);
    repeat (8) @(negedge clk);
    chk("all 6 retired", retired_n == 6);
    chk("count 0 after retire", count == '0);

    u = mk(10, 1, 0, 0); u.stale_pdst = preg_t'(21);
    alloc1(u, ids[10]);
    u = mk(11, 0, 1, 0);
    alloc1(u, ids[11]);
    u = mk(12, 0, 0, 0);
    alloc1(u, ids[12]);
    comp1(ids[10], 32'hAAA0);
    fork
      begin : watch
        logic seen_free = 0, seen_rel = 0, bad_free = 0;
        repeat (12) begin
          @(posedge clk);
          if (free_valid[0]) begin
            seen_free = 1;
            if (free_preg[0] != preg_t'(21)) bad_free = 1;
          end
          if (store_release[0]) seen_rel = 1;
        end
        chk("free strobe fired for the writer", seen_free);
        chk("free strobe carries the STALE name", !bad_free);
        chk("store_release fired for the store", seen_rel);
      end
      begin
        comp1(ids[11], 32'hBBB0);
        comp1(ids[12], 32'hCCC0);
      end
    join
    repeat (4) @(negedge clk);
    chk("trio retired", retired_n == 9);

    alloc1(mk(20, 1, 0, 0), ids[20]);
    @(negedge clk); commit_ready = 0;
    comp1(ids[20], 32'd7);
    repeat (4) @(negedge clk);
    chk("gated: nothing retires with ready low", retired_n == 9);
    @(negedge clk); commit_ready = 1;
    repeat (3) @(negedge clk);
    chk("retires when ready returns", retired_n == 10);

    u = mk(30, 1, 0, 1);       // illegal at decode -> exc in entry
    alloc1(u, ids[30]);
    repeat (3) @(negedge clk);
    chk("exc_at_head raised", exc_at_head == 1'b1);
    chk("exc cause = 2", exc_cause == 4'd2);
    chk("exc pc", exc_pc == u.pc);
    chk("excepting op does NOT retire", retired_n == 10);
    @(negedge clk); flush_all = 1;
    @(negedge clk); flush_all = 0;
    @(negedge clk);
    chk("flush empties", count == '0 && !exc_at_head);

    for (int n = 40; n < 44; n++) alloc1(mk(n, 1, 0, 0), ids[n]);
    @(negedge clk);
    for (int n = 43; n >= 41; n--) begin
      chk($sformatf("walk sees pc of %0d", n),
          walk_valid && walk_entry.pc == 32'h1000 + 32'(n)*4);
      walk_pop = 1;
      @(negedge clk);
      walk_pop = 0; viol_set = 0; viol_set_id = '0;
      @(negedge clk);
    end
    chk("one entry left after 3 pops", count == (ROB_W+1)'(1));
    comp1(ids[40], 32'd1);
    repeat (3) @(negedge clk);
    chk("survivor retires", retired_n == 11);

    for (int n = 0; n < 2 * ROB_N + ROB_N/2; n++) begin
      alloc1(mk(100 + n, 1, 0, 0), ids[0]);
      comp1(ids[0], 32'(n));
      repeat (2) @(negedge clk);
    end
    repeat (4) @(negedge clk);
    chk("wrap: all retired", retired_n == 11 + 2*ROB_N + ROB_N/2);
    chk("wrap: empty", count == '0);

    idle();
    for (int n = 0; n < ROB_N - RENAME_W; n++) alloc1(mk(n, 0, 0, 0), ids[0]);
    @(negedge clk);
    chk("allocatable at N-RENAME_W", allocatable == 1'b1);
    alloc1(mk(63, 0, 0, 0), ids[0]);
    @(negedge clk);
    chk("not allocatable past the reserve", allocatable == 1'b0);

    begin
      automatic logic [ROB_W:0] saved_tail;
      automatic rob_ptr_t first_id;
      while (walk_valid) begin
        @(negedge clk); walk_pop = 1;
        @(negedge clk); walk_pop = 0; viol_set = 0; viol_set_id = '0;
      end
      @(negedge clk);
      commit_ready = 0;
      saved_tail = tail_o;                            // pre-branch tail
      alloc1(mk(900, 1'b0, 1'b0, 1'b0), first_id);    // the "branch"
      saved_tail = saved_tail + (ROB_W+1)'(1);        // post-branch bundle
      comp1(first_id, 32'h0);
      begin
        automatic rob_ptr_t d;
        alloc1(mk(901, 1'b0, 1'b0, 1'b0), d);
        alloc1(mk(902, 1'b0, 1'b0, 1'b0), d);
        alloc1(mk(903, 1'b0, 1'b0, 1'b0), d);
      end
      @(negedge clk);
      restore_valid = 1; restore_tail = saved_tail;
      @(negedge clk); restore_valid = 0;
      @(negedge clk);
      chk("restore: the branch alone survives (commit window shows it done)",
          head_valid && head_done);
      commit_ready = 1;
      begin
        automatic rob_ptr_t nid;
        alloc1(mk(904, 1'b0, 1'b0, 1'b0), nid);
        chk("restore: allocation resumes at the rolled-back id",
            nid == rob_ptr_t'(ROB_W'(saved_tail)));
      end
    end

    if (errors == 0) $display("ROB PASS");
    else $display("ROB FAIL: %0d", errors);
    $finish;
  end
endmodule
