// Gate for lrsc_unit, including THE directed.
module tb_lrsc_unit
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coherence_pkg::*;
  import platform_cfg_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic  [NUM_HARTS-1:0] lr_valid, sc_valid, acc_valid, acc_hit;
  word_t                 acc_addr [NUM_HARTS];
  logic  [NUM_HARTS-1:0] snoop_clear, trap_clear;
  logic  [NUM_HARTS-1:0] sc_success, prot_valid, rsv_valid, backing_off;
  word_t                 prot_addr [NUM_HARTS];

  int errors = 0, checked = 0;

  lrsc_unit dut (
    .clk, .rst_n, .lr_valid, .sc_valid, .acc_valid, .acc_addr, .acc_hit,
    .snoop_clear, .trap_clear, .sc_success, .prot_valid, .prot_addr,
    .rsv_valid, .backing_off
  );

  function automatic logic other_window(input int h);
    other_window = 1'b0;
    for (int o = 0; o < NUM_HARTS; o++)
      if ((o != h) && prot_valid[o]
          && (prot_addr[o][31:OFF_W] == LINE_A[31:OFF_W])) other_window = 1'b1;
  endfunction

  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [FAIL] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  task automatic clean_slate();
    @(negedge clk);
    idle_all(); trap_clear = '1;
    @(posedge clk); @(negedge clk); idle_all();
    repeat (LRSC_BACKOFF + 4) @(posedge clk);
    @(negedge clk);
  endtask

  task automatic idle_all();
    lr_valid='0; sc_valid='0; acc_valid='0; acc_hit='0;
    snoop_clear='0; trap_clear='0;
    for (int h=0; h<NUM_HARTS; h++) acc_addr[h]='0;
  endtask

  task automatic do_lr(input int h, input word_t a);
    @(negedge clk);
    idle_all();
    lr_valid[h]=1'b1; acc_valid[h]=1'b1; acc_hit[h]=1'b1; acc_addr[h]=a;
    @(posedge clk); #1; idle_all();
  endtask

  task automatic do_sc(input int h, input word_t a, output logic ok);
    @(negedge clk);
    idle_all();
    sc_valid[h]=1'b1; acc_valid[h]=1'b1; acc_hit[h]=1'b1; acc_addr[h]=a;
    #1; ok = sc_success[h];
    @(posedge clk); #1; idle_all();
  endtask

  localparam word_t LINE_A = 32'h8000_1000;
  localparam word_t LINE_B = 32'h8000_2000;

  logic ok0, ok1;
  int   nobackoff;
  int   spins;
  int   win0, win1;
  int   lr_turn = 0;

  initial begin
    if (!$value$plusargs("NOBACKOFF=%d", nobackoff)) nobackoff = 0;
    idle_all();
    repeat (3) @(negedge clk); rst_n = 1'b1; @(negedge clk);

    $display("=== tb_lrsc_unit (N=%0d BACKOFF=%0d) ===",
             LRSC_WINDOW_N, LRSC_BACKOFF);

    ck("no reservation out of reset", rsv_valid === '0 && backing_off === '0);
    do_lr(0, LINE_A);
    ck("LR arms hart 0's window", rsv_valid[0] === 1'b1);
    ck("LR does NOT arm hart 1", rsv_valid[1] === 1'b0);
    ck("protection window advertised for hart 0", prot_valid[0] === 1'b1);
    ck("protection address is hart 0's line",
       prot_addr[0][31:OFF_W] === LINE_A[31:OFF_W]);
    do_sc(0, LINE_A, ok0);
    ck("SC to the reserved line SUCCEEDS", ok0 === 1'b1);

    do_lr(0, LINE_A);
    do_sc(0, LINE_B, ok0);
    ck("SC to a different line is rejected", ok0 === 1'b0);

    do_lr(0, LINE_A);
    idle_all(); snoop_clear[0]=1'b1; @(posedge clk); #1; idle_all();
    ck("snooped GetM clears the reservation", rsv_valid[0] === 1'b0);
    ck("snoop clear leaves NO backoff (line is gone)", backing_off[0] === 1'b0);
    do_sc(0, LINE_A, ok0);
    ck("SC after a snoop clear is rejected", ok0 === 1'b0);

    do_lr(0, LINE_A);
    idle_all(); trap_clear[0]=1'b1; @(posedge clk); #1; idle_all();
    ck("a trap clears the reservation", rsv_valid[0] === 1'b0);

    do_lr(0, LINE_A);
    idle_all(); acc_valid[0]=1'b1; acc_hit[0]=1'b1; acc_addr[0]=LINE_B;
    @(posedge clk); #1; idle_all();
    ck("intervening access kills the reservation", rsv_valid[0] === 1'b0);
    ck("...and enters BACKOFF (forbids instant re-arm)", backing_off[0] === 1'b1);
    do_sc(0, LINE_A, ok0);
    ck("SC during BACKOFF is rejected (dead reservation)", ok0 === 1'b0);

    idle_all();
    lr_valid[0]=1'b1; acc_valid[0]=1'b1; acc_hit[0]=1'b1; acc_addr[0]=LINE_A;
    @(posedge clk); #1;
    ck("LR during BACKOFF does not immediately re-arm", rsv_valid[0] === 1'b0);
    idle_all();
    repeat (LRSC_BACKOFF + 4) @(posedge clk);
    clean_slate();
    do_lr(0, LINE_A);
    ck("LR from a fully idle counter arms normally", rsv_valid[0] === 1'b1);

    clean_slate();
    idle_all();
    lr_valid[0]=1'b1; acc_valid[0]=1'b1; acc_hit[0]=1'b0; acc_addr[0]=LINE_A;
    @(posedge clk); #1; idle_all();
    ck("an LR that MISSED arms no window", rsv_valid[0] === 1'b0);

    clean_slate();
    do_lr(0, LINE_A);
    do_lr(1, LINE_B);
    ck("hart 0 window open on line A", rsv_valid[0] === 1'b1);
    ck("hart 1 window open on line B (concurrently)", rsv_valid[1] === 1'b1);
    ck("the two windows advertise DIFFERENT lines",
       prot_addr[0][31:OFF_W] !== prot_addr[1][31:OFF_W]);

    clean_slate();

    win0 = 0; win1 = 0; spins = 0;
    while (spins < 20000 && (win0 == 0 || win1 == 0)) begin
      @(negedge clk);
      idle_all();
      lr_turn = (lr_turn + 1) % NUM_HARTS;
      for (int h = 0; h < NUM_HARTS; h++) begin
        if (rsv_valid[h]) begin
          sc_valid[h]=1'b1; acc_valid[h]=1'b1; acc_hit[h]=1'b1; acc_addr[h]=LINE_A;
        end else if (!backing_off[h] && !other_window(h) && (h == lr_turn)) begin
          lr_valid[h]=1'b1; acc_valid[h]=1'b1; acc_hit[h]=1'b1; acc_addr[h]=LINE_A;
          for (int o = 0; o < NUM_HARTS; o++) if (o != h) snoop_clear[o] = 1'b1;
        end
      end
      #1;
      for (int h = 0; h < NUM_HARTS; h++) begin
        if (sc_success[h]) begin
          if (h == 0) win0++; else win1++;
          for (int o = 0; o < NUM_HARTS; o++)
            if (o != h) snoop_clear[o] = 1'b1;
        end
      end
      @(posedge clk);
      spins++;
    end
    idle_all();

    $display("  livelock test: hart0 wins=%0d hart1 wins=%0d in %0d cycles",
             win0, win1, spins);
    ck("CONFORMANCE: at least one hart's SC succeeded (spec eventuality)",
       (win0 + win1) > 0);
    ck("FAIRNESS (not spec-required): BOTH harts eventually succeeded",
       (win0 > 0) && (win1 > 0));

    if (nobackoff != 0) begin
      $display("  NOBACKOFF control: win0=%0d win1=%0d", win0, win1);
    end

    $display("=== tb_lrsc_unit: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_LRSC_UNIT PASS");
    else             $display("TB_LRSC_UNIT FAIL");
    $finish;
  end

  initial begin
    #4000000; $display("TB_LRSC_UNIT FAIL (timeout)"); $finish;
  end

endmodule
