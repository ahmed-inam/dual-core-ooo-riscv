// Unit gate for the return address stack.
`timescale 1ns/1ps
module tb_ras;
  import rv32i_pkg::*;

  logic clk, rst_n;
  logic push, pop, restore;
  word_t push_addr, top;
  logic top_valid;
  ras_ptr_t restore_tos, tos_o;
  ras_ovf_t restore_ovf, ovf_o;

  ras u_ras (
    .clk, .rst_n, .push, .push_addr, .pop,
    .restore, .restore_tos, .restore_ovf,
    .top, .top_valid, .tos_o, .ovf_o
  );

  initial clk = 0; always #5 clk = ~clk;
  int errors = 0;

  task automatic chk(input string n, input word_t got, input word_t exp);
    if (got !== exp) begin
      $display("  FAIL %-38s got 0x%08h exp 0x%08h", n, got, exp); errors++;
    end else $display("  ok   %-38s 0x%08h", n, got);
  endtask
  task automatic chkb(input string n, input logic got, input logic exp);
    if (got !== exp) begin
      $display("  FAIL %-38s got %b exp %b", n, got, exp); errors++;
    end else $display("  ok   %-38s %b", n, got);
  endtask

  task automatic do_push(input word_t a);
    push=1; push_addr=a; pop=0; @(posedge clk); #1; push=0; push_addr='0;
  endtask
  task automatic do_pop();
    pop=1; push=0; @(posedge clk); #1; pop=0;
  endtask
  task automatic do_swap(input word_t a);   // coroutine: pop and push together
    pop=1; push=1; push_addr=a; @(posedge clk); #1; pop=0; push=0; push_addr='0;
  endtask
  task automatic do_restore(input ras_ptr_t t, input ras_ovf_t o);
    restore=1; restore_tos=t; restore_ovf=o; @(posedge clk); #1; restore=0;
  endtask
  task automatic idle(); @(posedge clk); #1; endtask

  ras_ptr_t saved_tos; ras_ovf_t saved_ovf;

  initial begin
    push=0; pop=0; restore=0; push_addr='0; restore_tos='0; restore_ovf='0;
    rst_n=0; @(posedge clk); @(posedge clk); #1;

    $display("=== 1. reset: empty, no prediction ===");
    chkb("top_valid after reset", top_valid, 1'b0);
    chk ("tos after reset", {28'd0, tos_o}, 32'd0);

    rst_n=1; #1;

    $display("=== 2. nesting: LIFO order ===");
    do_push(32'h1000);          // main -> foo
    chkb("top_valid after 1 push", top_valid, 1'b1);
    chk ("top = first ret addr", top, 32'h1000);
    do_push(32'h2000);          // foo -> bar
    chk ("top = newest (LIFO)", top, 32'h2000);
    do_push(32'h3000);
    chk ("top = 0x3000", top, 32'h3000);
    do_pop();
    chk ("pop returns to 0x2000", top, 32'h2000);
    do_pop();
    chk ("pop returns to 0x1000", top, 32'h1000);
    do_pop();
    chkb("empty again", top_valid, 1'b0);

    $display("=== 3. fill exactly 8 ===");
    for (int i=1; i<=8; i++) do_push(32'h100 * i);
    chk ("top after 8 pushes", top, 32'h800);
    chk ("tos = 8 (full, distinct from empty)", {28'd0, tos_o}, 32'd8);
    chk ("no overflow yet", {26'd0, ovf_o}, 32'd0);
    chkb("still valid when full", top_valid, 1'b1);

    $display("=== 4. OVERFLOW: array must NOT be corrupted ===");
    do_push(32'hAAA1); do_push(32'hAAA2); do_push(32'hAAA3);
    chk ("ovf counted 3", {26'd0, ovf_o}, 32'd3);
    chk ("tos unmoved by overflow", {28'd0, tos_o}, 32'd8);
    chk ("top still frame 8 (not corrupted)", top, 32'h800);

    $display("=== 5. off-book pops: predict top, drain counter ===");
    chkb("prediction offered while off-book", top_valid, 1'b1);
    do_pop(); chk("ovf 3->2", {26'd0, ovf_o}, 32'd2);
    do_pop(); chk("ovf 2->1", {26'd0, ovf_o}, 32'd1);
    chk ("pointer never moved while off-book", {28'd0, tos_o}, 32'd8);
    do_pop(); chk("ovf 1->0 (back in range)", {26'd0, ovf_o}, 32'd0);

    $display("=== 6. THE POINT: the 8 real frames survived intact ===");
    do_pop(); chk("frame 8", top, 32'h700);
    do_pop(); chk("frame 7", top, 32'h600);
    do_pop(); chk("frame 6", top, 32'h500);
    do_pop(); chk("frame 5", top, 32'h400);
    do_pop(); chk("frame 4", top, 32'h300);
    do_pop(); chk("frame 3", top, 32'h200);
    do_pop(); chk("frame 2 (outermost survived)", top, 32'h100);
    do_pop(); chkb("empty after draining all 8", top_valid, 1'b0);

    $display("=== 7. recursion: overflow predicts the SAME address correctly ===");
    do_push(32'h5000);                       // main -> fact
    for (int i=0; i<20; i++) do_push(32'h6004);  // 20 recursive calls, same site
    chk ("recursion overflowed", {26'd0, ovf_o}, 32'd13);  // 21 pushes, 8 stored
    for (int i=0; i<20; i++) begin
      if (top !== 32'h6004) begin
        $display("  FAIL recursion unwind %0d predicted 0x%08h exp 0x6004", i, top);
        errors++;
      end
      do_pop();
    end
    $display("  ok   all 20 recursive returns predicted 0x6004");
    chk ("outermost return is main's addr", top, 32'h5000);
    do_pop();

    $display("=== 8. underflow: clamp, do not wrap ===");
    chkb("empty before underflow", top_valid, 1'b0);
    do_pop(); do_pop();                       // pops on an empty stack
    chk ("tos clamped at 0 (not wrapped to 7)", {28'd0, tos_o}, 32'd0);
    chkb("still reports no prediction", top_valid, 1'b0);
    do_push(32'h7000);
    chk ("usable after underflow", top, 32'h7000);
    do_pop();

    $display("=== 9. wrong-path push, then snapshot restore ===");
    do_push(32'h1111); do_push(32'h2222);
    saved_tos = tos_o; saved_ovf = ovf_o;     // F captures this per prediction
    do_push(32'hBAD0);                        // speculative push, wrong path
    chk ("wrong-path push moved top", top, 32'hBAD0);
    do_restore(saved_tos, saved_ovf);         // E says: mispredict
    chk ("restored top", top, 32'h2222);
    chk ("restored tos", {28'd0, tos_o}, {28'd0, saved_tos});
    do_pop(); chk("next pop correct after repair", top, 32'h1111);
    do_pop();

    $display("=== 10. wrong-path POP, then restore ===");
    do_push(32'h3333); do_push(32'h4444);
    saved_tos = tos_o; saved_ovf = ovf_o;
    do_pop();                                 // speculative pop, wrong path
    chk ("wrong-path pop moved top", top, 32'h3333);
    do_restore(saved_tos, saved_ovf);
    chk ("restored after bogus pop", top, 32'h4444);
    do_pop(); do_pop();

    $display("=== 11. overflow counter restored with the pointer ===");
    for (int i=1; i<=8; i++) do_push(32'h900 + i);
    do_push(32'hC001); do_push(32'hC002);     // ovf = 2
    saved_tos = tos_o; saved_ovf = ovf_o;
    do_push(32'hC003); do_push(32'hC004);     // wrong path: ovf climbs to 4
    chk ("ovf grew on wrong path", {26'd0, ovf_o}, 32'd4);
    do_restore(saved_tos, saved_ovf);
    chk ("ovf restored to 2", {26'd0, ovf_o}, 32'd2);
    do_pop(); do_pop();
    chk ("ovf drained", {26'd0, ovf_o}, 32'd0);
    do_pop(); chk("real frame intact after ovf recovery", top, 32'h907);

    $display("=== 12. coroutine swap: simultaneous push+pop ===");
    while (top_valid) do_pop();
    do_push(32'hE000); do_push(32'hE001);
    do_swap(32'hF000);                        // jalr x1,0(x5): pop then push
    chk ("swap replaced top", top, 32'hF000);
    do_pop();
    chk ("depth unchanged by swap", top, 32'hE000);

    $display("=== 13. restore at EXACTLY full (the reconstruct hole) ===");
    while (top_valid) do_pop();
    ovf_drain: begin end
    for (int i=1; i<=8; i++) do_push(32'hD00 + i);   // exactly full, ovf = 0
    chk ("full: tos = 8", {28'd0, tos_o}, 32'd8);
    chk ("no overflow", {26'd0, ovf_o}, 32'd0);
    saved_tos = tos_o; saved_ovf = ovf_o;
    do_pop(); do_pop();                              // wrong-path pops
    do_restore(saved_tos, saved_ovf);
    chkb("still valid after restore-at-full", top_valid, 1'b1);
    chk ("tos restored to 8, not mistaken for empty", {28'd0, tos_o}, 32'd8);
    chk ("top entry intact", top, 32'hD08);
    do_pop(); chk("frame 7 intact", top, 32'hD07);

    if (errors==0) $display("RAS PASS: all return-stack checks");
    else           $display("RAS FAIL: %0d error(s)", errors);
    $finish;
  end
endmodule
