// Unit gate for the gshare direction predictor.
`timescale 1ns/1ps
module tb_gshare;
  import rv32i_pkg::*;

  logic clk, rst_n;
  word_t fetch_pc;
  localparam int unsigned WPL = 4;
  logic fetch_valid, fetch_is_branch;
  logic [WPL-1:0] spec_shift;
  always_comb begin
    spec_shift = '0;
    spec_shift[fetch_pc[3:2]] = fetch_is_branch;   // offered word is the branch
  end
  logic [WPL-1:0]       dir_taken_v;
  logic [WPL-1:0][1:0]  pht_ctr_v;
  logic dir_taken;
  assign dir_taken = dir_taken_v[fetch_pc[3:2]];
  logic fetch_pc_en;
  logic [1:0] pht_ctr_o;
  assign pht_ctr_o = pht_ctr_v[fetch_pc[3:2]];
  ghr_t ghr_o;
  bp_update_t update;

  gshare #(.WORDS_PER_LINE(WPL)) u_gs (.clk, .rst_n, .fetch_pc_en, .fetch_pc, .fetch_valid, .spec_shift,
               .dir_taken(dir_taken_v), .pht_ctr_o(pht_ctr_v), .ghr_o, .update, .trap_restore(1'b0), .trap_ghr(10'd0));

  initial clk = 0; always #5 clk = ~clk;
  int errors = 0;

  task automatic chk(input string n, input logic [31:0] got, input logic [31:0] exp);
    if (got !== exp) begin
      $display("  FAIL %-42s got %0d exp %0d", n, got, exp); errors++;
    end else $display("  ok   %-42s %0d", n, got);
  endtask
  task automatic chkb(input string n, input logic got, input logic exp);
    if (got !== exp) begin
      $display("  FAIL %-42s got %b exp %b", n, got, exp); errors++;
    end else $display("  ok   %-42s %b", n, got);
  endtask

  task automatic look(input word_t pc);
    @(negedge clk); fetch_pc = pc; fetch_pc_en = 1'b1;
                    fetch_valid = 1'b0; fetch_is_branch = 1'b0;
    @(negedge clk); fetch_pc_en = 1'b0; #1;
  endtask

  task automatic train(input word_t pc, input logic taken, input ghr_t snap_ghr,
                       input logic [1:0] carried_ctr);
    bp_pred_t p;
    p = BP_PRED_NONE;
    p.snapshot.ghr = snap_ghr;
    p.snapshot.pht_ctr = carried_ctr;
    update = '{ valid: 1'b1, pc: pc, cf_type: CF_BRANCH, call: 1'b0, ret: 1'b0,
                taken: taken, target: '0, mispredict: 1'b0, pred: p };
    @(posedge clk); #1;
    update = BP_UPDATE_NONE;
  endtask

  task automatic predict_then_train(input word_t pc, input logic taken,
                                    input ghr_t snap_ghr);
    look(pc);                      // pht_ctr_o now = this entry's counter
    train(pc, taken, snap_ghr, pht_ctr_o);
  endtask

  task automatic fetch_branch(input word_t pc);
    fetch_pc = pc; fetch_valid = 1'b1; fetch_is_branch = 1'b1;
    @(posedge clk); #1;
    fetch_valid = 1'b0; fetch_is_branch = 1'b0;
  endtask

  task automatic fetch_other(input word_t pc);
    fetch_pc = pc; fetch_valid = 1'b1; fetch_is_branch = 1'b0;
    @(posedge clk); #1;
    fetch_valid = 1'b0;
  endtask

  task automatic mispredict(input word_t pc, input logic taken, input ghr_t snap_ghr);
    bp_pred_t p;
    p = BP_PRED_NONE;
    p.snapshot.ghr = snap_ghr;
    update = '{ valid: 1'b1, pc: pc, cf_type: CF_BRANCH, call: 1'b0, ret: 1'b0,
                taken: taken, target: '0, mispredict: 1'b1, pred: p };
    @(posedge clk); #1;
    update = BP_UPDATE_NONE;
  endtask

  task automatic set_ghr(input ghr_t snap_ghr, input logic bit_in);
    bp_pred_t p;
    p = BP_PRED_NONE;
    p.snapshot.ghr = snap_ghr;
    update = '{ valid: 1'b1, pc: 32'h0000_0FF0, cf_type: CF_JAL, call: 1'b0,
                ret: 1'b0, taken: bit_in, target: '0, mispredict: 1'b1, pred: p };
    @(posedge clk); #1;
    update = BP_UPDATE_NONE;
  endtask

  initial begin
    update = BP_UPDATE_NONE; fetch_pc = '0; fetch_valid = 0; fetch_is_branch = 0; fetch_pc_en = 0;
    rst_n = 0; @(posedge clk); @(posedge clk); #1;

    $display("=== 1. reset: counters start weakly TAKEN ===");
    look(32'h0000_0100); chkb("unseen branch predicts taken", dir_taken, 1'b1);
    look(32'h0000_0244); chkb("another unseen pc predicts taken", dir_taken, 1'b1);
    chk ("ghr starts at 0", {22'd0, ghr_o}, 32'd0);

    rst_n = 1; #1;

    $display("=== 2. two not-takens are needed to flip a taken prediction ===");
    predict_then_train(32'h0000_0100, 1'b1, 10'd0);            // 2 -> 3 strong T
    look(32'h0000_0100); chkb("still taken at strong T", dir_taken, 1'b1);
    predict_then_train(32'h0000_0100, 1'b0, 10'd0);            // 3 -> 2 weak T
    look(32'h0000_0100); chkb("one miss: STILL taken (weak)", dir_taken, 1'b1);
    predict_then_train(32'h0000_0100, 1'b0, 10'd0);            // 2 -> 1 weak NT
    look(32'h0000_0100); chkb("two misses: now not-taken", dir_taken, 1'b0);

    $display("=== 3. saturation at both ends ===");
    for (int i = 0; i < 10; i++) predict_then_train(32'h0000_0100, 1'b0, 10'd0);
    look(32'h0000_0100); chkb("saturated not-taken", dir_taken, 1'b0);
    predict_then_train(32'h0000_0100, 1'b1, 10'd0);
    look(32'h0000_0100); chkb("one taken: still NT (saturation held)", dir_taken, 1'b0);
    for (int i = 0; i < 10; i++) predict_then_train(32'h0000_0100, 1'b1, 10'd0);
    look(32'h0000_0100); chkb("saturated taken after many", dir_taken, 1'b1);

    $display("=== 4. the loop case: 1 mispredict on exit, not 2 ===");
    look(32'h0000_0100); chkb("loop steady state: taken", dir_taken, 1'b1);
    predict_then_train(32'h0000_0100, 1'b0, 10'd0);            // the exit
    look(32'h0000_0100); chkb("after exit: still predicts taken", dir_taken, 1'b1);

    $display("=== 5. training uses the SNAPSHOT ghr, not the current one ===");
    predict_then_train(32'h0000_0200, 1'b1, 10'h0AA);
    predict_then_train(32'h0000_0200, 1'b1, 10'h0AA);
    begin
      ghr_t target_ghr; target_ghr = 10'h0AA;
      mispredict(32'h0000_0FFC, 1'b0, 10'h055);   // ghr = {055[8:0],0} = 0x0AA
    end
    chk ("ghr driven to 0x0AA", {22'd0, ghr_o}, 32'h0AA);
    look(32'h0000_0200);
    chkb("trained counter found via same index", dir_taken, 1'b1);

    $display("=== 6. a different history hits a DIFFERENT counter ===");
    predict_then_train(32'h0000_0200, 1'b0, 10'h155);
    predict_then_train(32'h0000_0200, 1'b0, 10'h155);
    predict_then_train(32'h0000_0200, 1'b0, 10'h155);
    look(32'h0000_0200);
    chkb("original index still taken", dir_taken, 1'b1);

    $display("=== 7. GHR shifts only on conditional branches ===");
    set_ghr(10'd0, 1'b0);                         // ghr = 0
    chk ("ghr set to 0", {22'd0, ghr_o}, 32'd0);
    look(32'h0000_0800); chkb("untrained pc predicts taken", dir_taken, 1'b1);
    fetch_other(32'h0000_0300);                   // an add: must not shift
    chk ("non-branch did not shift ghr", {22'd0, ghr_o}, 32'd0);
    fetch_branch(32'h0000_0800);                  // predicts taken -> shift in 1
    chk ("branch shifted in its prediction", {22'd0, ghr_o}, 32'd1);
    fetch_other(32'h0000_0300);
    chk ("still unchanged by non-branch", {22'd0, ghr_o}, 32'd1);

    $display("=== 8. stalled fetch must not shift (fetch_valid low) ===");
    fetch_pc = 32'h0000_0800; fetch_valid = 1'b0; fetch_is_branch = 1'b1;
    @(posedge clk); #1;
    chk ("stalled cycle did not shift", {22'd0, ghr_o}, 32'd1);

    $display("=== 9. mispredict repairs GHR from the snapshot ===");
    fetch_branch(32'h0000_0800);
    fetch_branch(32'h0000_0800);
    fetch_branch(32'h0000_0800);
    chk ("ghr walked forward", {22'd0, ghr_o}, 32'd15);
    mispredict(32'h0000_0800, 1'b1, 10'h100);
    chk ("ghr = {snapshot[8:0], actual}", {22'd0, ghr_o}, 32'h201);

    $display("=== 10. a JAL must not train the PHT ===");
    look(32'h0000_0400); chkb("fresh pc: weakly taken", dir_taken, 1'b1);
    begin
      bp_pred_t p; p = BP_PRED_NONE; p.snapshot.ghr = ghr_o;
      for (int i = 0; i < 5; i++) begin
        update = '{ valid: 1'b1, pc: 32'h0000_0400, cf_type: CF_JAL, call: 1'b1,
                    ret: 1'b0, taken: 1'b0, target: '0, mispredict: 1'b0, pred: p };
        @(posedge clk); #1;
      end
      update = BP_UPDATE_NONE;
    end
    look(32'h0000_0400);
    chkb("jal did not move the counter", dir_taken, 1'b1);

    if (errors == 0) $display("GSHARE PASS: all direction-predictor checks");
    else             $display("GSHARE FAIL: %0d error(s)", errors);
    $finish;
  end
endmodule
