// Gate for the ordering point.
module tb_coherence_mgr
  import rv32i_pkg::*;      // word_t
  import mem_pkg::*;
  import coherence_pkg::*;
  import platform_cfg_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic     [NUM_HARTS-1:0] req_valid;
  word_t                    req_addr [NUM_HARTS];
  coh_req_e                 req_type [NUM_HARTS];
  logic     [NUM_HARTS-1:0] req_gnt;
  logic     [NUM_HARTS-1:0] req_atomic;
  logic     [NUM_HARTS-1:0] snp_valid;
  word_t                    snp_addr;
  coh_snoop_e               snp_type;
  logic     [NUM_HARTS-1:0] snp_ack;
  coh_rsp_e                 snp_rsp  [NUM_HARTS];
  logic     [NUM_HARTS-1:0] cmp_valid;
  logic                     cmp_shared, cmp_dirty;
  logic  [NUM_HARTS-1:0]    prot_valid;
  word_t                    prot_addr [NUM_HARTS];
  logic                     prot_deferred, ord_violation;

  int errors = 0, checked = 0;
  logic saw_cmp;

  coherence_mgr dut (
    .clk, .rst_n, .req_valid, .req_addr, .req_type, .req_gnt,
    .req_atomic,
    .snp_valid, .snp_addr, .snp_type, .snp_ack, .snp_rsp,
    .req_installed('1),   // TB has no fill stage: install is instant
    .cmp_valid, .cmp_shared, .cmp_dirty,
    .prot_valid, .prot_addr, .prot_deferred, .ord_violation
  );

  coh_rsp_e mock_rsp [NUM_HARTS];      // what each mock will answer
  logic [NUM_HARTS-1:0] served;        // a snoop is held until acked: answer it once

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin served <= '0; snp_ack <= '0; end
    else begin
      for (int h = 0; h < NUM_HARTS; h++) begin
        snp_ack[h] <= 1'b0;
        if (!snp_valid[h]) served[h] <= 1'b0;
        else if (!served[h]) begin
          served[h]  <= 1'b1;
          snp_ack[h] <= 1'b1;
          snp_rsp[h] <= mock_rsp[h];
        end
      end
    end
  end

  logic [NUM_HARTS-1:0] owns;
  word_t                owns_line [NUM_HARTS];
  always_ff @(posedge clk) if (rst_n) begin
    for (int h = 0; h < NUM_HARTS; h++) begin
      if (req_gnt[h]) begin owns[h] <= 1'b1; owns_line[h] <= req_addr[h]; end
      if (cmp_valid[h]) owns[h] <= 1'b0;
      if (snp_valid[h] && owns[h] && (snp_addr == owns_line[h])) begin
        errors++;
        $display("  [FAIL] hart %0d snooped for the line it owns -- x-cell reachable", h);
      end
    end
  end

  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [FAIL] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  task automatic clear_reqs();
    for (int h = 0; h < NUM_HARTS; h++) begin
      req_valid[h] = 1'b0; req_addr[h] = '0; req_type[h] = REQ_GETS;
      req_atomic[h] = 1'b0;
    end
  endtask

  task automatic wait_cmp(input int h, input int limit, output int took);
    took = 0;
    saw_cmp = 1'b0;
    while (!cmp_valid[h] && took < limit) begin @(posedge clk); took++; end
    saw_cmp = cmp_valid[h];     // cmp_valid is a PULSE -- capture, do not re-sample
    @(posedge clk);
  endtask

  int t;
  int gnt0, gnt1;

  initial begin
    clear_reqs();
    prot_valid = '0;
    for (int h = 0; h < NUM_HARTS; h++) prot_addr[h] = '0;
    for (int h = 0; h < NUM_HARTS; h++) mock_rsp[h] = RSP_NtoN;
    owns = '0;
    repeat (3) @(negedge clk); rst_n = 1'b1; repeat (2) @(negedge clk);

    $display("=== tb_coherence_mgr ===");

    mock_rsp[1] = RSP_NtoN;                       // hart1 does not have it
    @(negedge clk); req_valid[0] = 1'b1; req_addr[0] = 32'h8000_1000; req_type[0] = REQ_GETS;
    #1; ck("GetS is ordered (granted)", req_gnt[0] === 1'b1);
    @(posedge clk); #1; clear_reqs();
    wait_cmp(0, 50, t);
    ck("GetS completes", saw_cmp === 1'b1);
    ck("nobody kept a copy -> shared LOW -> requester installs E", cmp_shared === 1'b0);
    ck("no dirty data reported", cmp_dirty === 1'b0);
    @(negedge clk);

    mock_rsp[1] = RSP_BtoB;                       // hart1 stays S
    @(negedge clk); req_valid[0] = 1'b1; req_addr[0] = 32'h8000_2000; req_type[0] = REQ_GETS;
    @(posedge clk); #1; clear_reqs();
    wait_cmp(0, 50, t);
    ck("responder kept a copy -> shared HIGH -> install S", cmp_shared === 1'b1);
    @(negedge clk);

    mock_rsp[1] = RSP_TtoB;                       // was M, now S, data attached
    @(negedge clk); req_valid[0] = 1'b1; req_addr[0] = 32'h8000_3000; req_type[0] = REQ_GETS;
    @(posedge clk); #1; clear_reqs();
    wait_cmp(0, 50, t);
    ck("dirty responder -> cmp_dirty set (writeback required)", cmp_dirty === 1'b1);
    ck("dirty responder kept a copy (TtoB) -> shared HIGH", cmp_shared === 1'b1);
    @(negedge clk);

    mock_rsp[1] = RSP_BtoN;
    @(negedge clk); req_valid[0] = 1'b1; req_addr[0] = 32'h8000_4000; req_type[0] = REQ_GETM;
    @(posedge clk); #1; clear_reqs();
    wait_cmp(0, 50, t);
    ck("responder went S->I (BtoN) -> shared LOW", cmp_shared === 1'b0);
    @(negedge clk);

    mock_rsp[0] = RSP_NtoN; mock_rsp[1] = RSP_NtoN;
    @(negedge clk);
    req_valid[0] = 1'b1; req_addr[0] = 32'h8000_5000; req_type[0] = REQ_GETM;
    req_valid[1] = 1'b1; req_addr[1] = 32'h8000_5000; req_type[1] = REQ_GETM;
    #1; gnt0 = req_gnt[0]; gnt1 = req_gnt[1];
    @(posedge clk); #1;
    ck("same-line race: EXACTLY ONE ordered", (gnt0 + gnt1) == 1);
    begin
      automatic int spins = 0;
      automatic int extra = 0;
      while (spins < 40 && !(cmp_valid[0] || cmp_valid[1])) begin
        @(posedge clk); #1;
        if (req_gnt[0] || req_gnt[1]) extra++;
        spins++;
      end
      ck("same-line loser NOT ordered while the winner is in flight", extra == 0);
    end
    clear_reqs(); @(negedge clk); @(negedge clk);

    @(negedge clk);
    req_valid[0] = 1'b1; req_addr[0] = 32'h8000_6000; req_type[0] = REQ_GETS;
    req_valid[1] = 1'b1; req_addr[1] = 32'h8000_7000; req_type[1] = REQ_GETS;
    begin
      automatic logic done0 = 1'b0, done1 = 1'b0;
      automatic int spins = 0;
      while (spins < 200 && !(done0 && done1)) begin
        @(posedge clk); #1;
        if (cmp_valid[0]) begin done0 = 1'b1; req_valid[0] = 1'b0; end
        if (cmp_valid[1]) begin done1 = 1'b1; req_valid[1] = 1'b0; end
        spins++;
      end
      ck("different-line requests BOTH complete (no starvation)", done0 && done1);
    end
    clear_reqs(); @(negedge clk);

    @(negedge clk); req_valid[0] = 1'b1; req_addr[0] = 32'h8000_8000; req_type[0] = REQ_PUTM;
    @(posedge clk); #1; clear_reqs();
    begin
      automatic int snoops = 0;
      automatic int spins  = 0;
      while (spins < 40 && !cmp_valid[0]) begin
        @(posedge clk); #1;
        if (snp_valid != '0) snoops++;
        spins++;
      end
      ck("PutM completes", saw_cmp === 1'b1);
      ck("PutM broadcast ZERO snoops", snoops == 0);
    end
    @(negedge clk);

    prot_valid[0] = 1'b1; prot_addr[0] = 32'h8000_9000;   // hart0 holds the window
    @(negedge clk);
    req_valid[1] = 1'b1; req_addr[1] = 32'h8000_9000; req_type[1] = REQ_GETM;
    repeat (6) begin @(posedge clk); #1; end
    ck("competing GetM inside the window is NOT ordered", req_gnt[1] === 1'b0);
    ck("prot_deferred reports the hold-off", prot_deferred === 1'b1);
    clear_reqs(); @(negedge clk);
    req_valid[1] = 1'b1; req_addr[1] = 32'h8000_9000; req_type[1] = REQ_GETS;
    #1; ck("a GetS to the protected line IS still ordered (D2: readers proceed)",
       req_gnt[1] === 1'b1);
    @(posedge clk); #1;
    clear_reqs(); wait_cmp(1, 50, t); @(negedge clk);
    req_valid[0] = 1'b1; req_addr[0] = 32'h8000_9000; req_type[0] = REQ_UPGRADE;
    #1; ck("the window HOLDER may still order its own Upgrade", req_gnt[0] === 1'b1);
    @(posedge clk); #1;
    clear_reqs(); wait_cmp(0, 50, t);
    prot_valid = '0; @(negedge clk);

    clear_reqs(); prot_valid = '0; @(negedge clk);
    req_valid[0] = 1'b1; req_addr[0] = 32'h8000_A000; req_type[0] = REQ_GETM;
    req_atomic[0] = 1'b1;
    #1; ck("atomic GetM is ordered", req_gnt[0] === 1'b1);
    @(posedge clk); #1; clear_reqs(); wait_cmp(0, 50, t); @(negedge clk);
    req_valid[1] = 1'b1; req_addr[1] = 32'h8000_A000; req_type[1] = REQ_GETM;
    repeat (4) begin @(posedge clk); #1; end
    ck("post-grant window defers the peer after an ATOMIC grant",
       req_gnt[1] === 1'b0);
    clear_reqs(); @(negedge clk);
    req_valid[0] = 1'b1; req_addr[0] = 32'h8000_B000; req_type[0] = REQ_GETM;
    req_atomic[0] = 1'b0;
    #1; ck("ordinary GetM is ordered", req_gnt[0] === 1'b1);
    @(posedge clk); #1; clear_reqs(); wait_cmp(0, 50, t); @(negedge clk);
    req_valid[1] = 1'b1; req_addr[1] = 32'h8000_B000; req_type[1] = REQ_GETM;
    #1; ck("no post-grant deferral after an ORDINARY grant (peer not starved)",
       req_gnt[1] === 1'b1);
    @(posedge clk); #1; clear_reqs(); wait_cmp(1, 50, t);
    prot_valid = '0; @(negedge clk);

    ck("no ordering violation at any point", ord_violation === 1'b0);

    $display("=== tb_coherence_mgr: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_COHERENCE_MGR PASS");
    else             $display("TB_COHERENCE_MGR FAIL");
    $finish;
  end

  initial begin
    #200000; $display("TB_COHERENCE_MGR FAIL (timeout)"); $finish;
  end

endmodule
