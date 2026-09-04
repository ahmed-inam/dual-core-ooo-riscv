// Unit gate for the BTB, focused on the allocation policy.
`timescale 1ns/1ps
module tb_btb;
  import rv32i_pkg::*;

  logic clk, rst_n;
  localparam int unsigned WPL = 4;
  word_t fetch_pc;
  logic       [WPL-1:0] hit_v;
  word_t      [WPL-1:0] target_v;
  btb_class_e [WPL-1:0] cf_class_v;
  logic       [WPL-1:0] is_call_v;
  word_t      target;
  logic       hit;
  btb_class_e cf_class;
  assign hit      = hit_v[fetch_pc[3:2]];
  assign target   = target_v[fetch_pc[3:2]];
  assign cf_class = cf_class_v[fetch_pc[3:2]];
  bp_update_t update;

  logic is_call;
  assign is_call = is_call_v[fetch_pc[3:2]];
  logic fetch_pc_en;
  btb #(.WORDS_PER_LINE(WPL)) u_btb (.clk, .rst_n, .fetch_pc_en, .fetch_pc,
    .hit(hit_v), .target(target_v), .cf_class(cf_class_v), .is_call(is_call_v), .update);

  initial clk = 0; always #5 clk = ~clk;
  int errors = 0;

  task automatic chk(input string n, input logic [31:0] got, input logic [31:0] exp);
    if (got !== exp) begin
      $display("  FAIL %-40s got 0x%08h exp 0x%08h", n, got, exp); errors++;
    end else $display("  ok   %-40s 0x%08h", n, got);
  endtask
  task automatic chkb(input string n, input logic got, input logic exp);
    if (got !== exp) begin
      $display("  FAIL %-40s got %b exp %b", n, got, exp); errors++;
    end else $display("  ok   %-40s %b", n, got);
  endtask

  task automatic train(input word_t pc, input cf_type_e cf, input word_t tgt,
                       input logic taken, input logic is_ret, input logic is_call);
    update = '{ valid: 1'b1, pc: pc, cf_type: cf, call: is_call, ret: is_ret,
                taken: taken, target: tgt, mispredict: 1'b0, pred: BP_PRED_NONE };
    @(posedge clk); #1;
    update = BP_UPDATE_NONE;
  endtask

  task automatic look(input word_t pc);
    @(negedge clk); fetch_pc = pc; fetch_pc_en = 1'b1;
    @(negedge clk); fetch_pc_en = 1'b0;   // now hit/target/... are valid
    #1;
  endtask

  initial begin
    update = BP_UPDATE_NONE; fetch_pc = '0; fetch_pc_en = 1'b0;
    rst_n = 0; @(posedge clk); @(posedge clk); #1;

    $display("=== 1. reset: every entry invalid ===");
    look(32'h0000_0100); chkb("miss after reset", hit, 1'b0);
    look(32'h0000_0200); chkb("miss on another pc", hit, 1'b0);

    rst_n = 1; #1;

    $display("=== 2. allocate on a taken branch, then hit ===");
    look(32'h0000_0100); chkb("cold miss before training", hit, 1'b0);
    train(32'h0000_0100, CF_BRANCH, 32'h0000_0080, 1'b1, 1'b0, 1'b0);
    look(32'h0000_0100);
    chkb("hit after training", hit, 1'b1);
    chk ("target learned", target, 32'h0000_0080);
    chk ("class = BRANCH", {30'd0, cf_class}, {30'd0, BTB_BRANCH});

    $display("=== 3. NOT-taken branch must not allocate ===");
    look(32'h0000_0300); chkb("cold", hit, 1'b0);
    train(32'h0000_0300, CF_BRANCH, 32'h0000_0300, 1'b0, 1'b0, 1'b0);
    look(32'h0000_0300);
    chkb("still miss (never-taken wastes no entry)", hit, 1'b0);

    $display("=== 4. taken branch that later falls through KEEPS its entry ===");
    train(32'h0000_0100, CF_BRANCH, 32'h0000_0080, 1'b0, 1'b0, 1'b0);
    look(32'h0000_0100);
    chkb("entry retained after fall-through", hit, 1'b1);
    chk ("target unchanged", target, 32'h0000_0080);

    $display("=== 5. tag mismatch must NOT hit (aliasing) ===");
    look(32'h0000_0500);
    chkb("aliasing pc misses", hit, 1'b0);
    train(32'h0000_0500, CF_JAL, 32'h0000_0900, 1'b1, 1'b0, 1'b1);
    look(32'h0000_0500);
    chkb("aliasing pc hits after its own training", hit, 1'b1);
    chk ("its target", target, 32'h0000_0900);
    look(32'h0000_0100);
    chkb("original pc evicted (direct-mapped)", hit, 1'b0);

    $display("=== 6. class learning: JAL / JALR / RET ===");
    train(32'h0000_0204, CF_JAL,  32'h0000_0700, 1'b1, 1'b0, 1'b1);
    look(32'h0000_0204);
    chk ("jal -> BTB_JAL", {30'd0, cf_class}, {30'd0, BTB_JAL});

    train(32'h0000_0208, CF_JALR, 32'h0000_0AA0, 1'b1, 1'b0, 1'b1);
    look(32'h0000_0208);
    chk ("indirect jalr -> BTB_JALR", {30'd0, cf_class}, {30'd0, BTB_JALR});

    train(32'h0000_020C, CF_JALR, 32'h0000_0BB0, 1'b1, 1'b1, 1'b0);
    look(32'h0000_020C);
    chk ("ret -> BTB_RET (not JALR)", {30'd0, cf_class}, {30'd0, BTB_RET});

    $display("=== 7. a RET's stored target is stale by design ===");
    train(32'h0000_020C, CF_JALR, 32'h0000_0CC0, 1'b1, 1'b1, 1'b0);
    look(32'h0000_020C);
    chk ("class still RET", {30'd0, cf_class}, {30'd0, BTB_RET});
    chk ("target follows the last caller", target, 32'h0000_0CC0);

    $display("=== 8. retarget: an indirect jalr that moved ===");
    train(32'h0000_0208, CF_JALR, 32'h0000_0DD0, 1'b1, 1'b0, 1'b1);
    look(32'h0000_0208);
    chk ("last-seen target wins", target, 32'h0000_0DD0);

    $display("=== 9. an invalid update must not write ===");
    update = '{ valid: 1'b0, pc: 32'h0000_0210, cf_type: CF_JAL, call: 1'b1,
                ret: 1'b0, taken: 1'b1, target: 32'hDEAD_BEEF,
                mispredict: 1'b0, pred: BP_PRED_NONE };
    @(posedge clk); #1; update = BP_UPDATE_NONE;
    look(32'h0000_0210);
    chkb("bubble did not allocate", hit, 1'b0);

    $display("=== 10. entries are independent ===");
    look(32'h0000_0204); chkb("0x204 still valid", hit, 1'b1);
    chk ("0x204 target intact", target, 32'h0000_0700);
    look(32'h0000_020C); chkb("0x20C still valid", hit, 1'b1);

    $display("=== 11. is_call: `j label` must NOT be marked a call ===");
    train(32'h0000_0280, CF_JAL, 32'h0000_0300, 1'b1, 1'b0, 1'b1);   // call=1
    look(32'h0000_0280);
    chk ("real call -> class JAL", {30'd0, cf_class}, {30'd0, BTB_JAL});
    chkb("real call -> is_call set", is_call, 1'b1);

    train(32'h0000_0284, CF_JAL, 32'h0000_0300, 1'b1, 1'b0, 1'b0);   // call=0
    look(32'h0000_0284);
    chk ("plain jump -> class still JAL", {30'd0, cf_class}, {30'd0, BTB_JAL});
    chkb("plain jump -> is_call CLEAR", is_call, 1'b0);

    $display("=== 12. index/tag split: 64 distinct entries coexist ===");
    for (int i = 0; i < 64; i++)
      train(32'h0001_0000 + (i*4), CF_BRANCH, 32'h0002_0000 + (i*4), 1'b1, 1'b0, 1'b0);
    begin
      int misses; misses = 0;
      for (int i = 0; i < 64; i++) begin
        look(32'h0001_0000 + (i*4));
        if (!hit || target !== (32'h0002_0000 + (i*4))) misses++;
      end
      if (misses != 0) begin
        $display("  FAIL %0d of 64 entries wrong", misses); errors++;
      end else $display("  ok   all 64 entries held simultaneously");
    end

    if (errors == 0) $display("BTB PASS: all branch-target-buffer checks");
    else             $display("BTB FAIL: %0d error(s)", errors);
    $finish;
  end
endmodule
