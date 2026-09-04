// Unit proof of the widened fetch_queue.
`timescale 1ns/1ps
module tb_fetch_queue;
  import rv32i_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  localparam int unsigned DEPTH = 8;
  localparam word_t BASE = 32'h8000_0000;

  logic  ireq, ignt, irvalid;
  word_t iaddr, irdata;
  logic [3:0][31:0] irdata_line;
  logic [3:0]       iwmask;
  bp_pred_t bp_pred; logic accept;
  bp_pred_t [3:0] bp_pred_vec; logic [3:0] word_valid;   // per-word
  logic  redirect_resolve_valid; word_t redirect_resolve_target;
  logic  ex_mem_en, redirect_trap_valid; word_t redirect_trap_target;
  logic [1:0]     out_pop_n, out_valid;
  word_t [1:0]    out_pc, out_instr;
  bp_pred_t [1:0] out_bp;
  logic  out_empty;

  fetch_queue #(.DEPTH(DEPTH), .RESET_PC_P(BASE), .FETCH_WIDE(1'b1)) dut (
    .clk, .rst_n,
    .ireq, .ignt, .iaddr, .irvalid, .irdata, .irdata_line, .iwmask,
    .bp_pred, .bp_pred_vec, .word_valid, .accept,
    .redirect_resolve_valid, .redirect_resolve_target, .ex_mem_en,
    .redirect_trap_valid, .redirect_trap_target,
    .out_pop_n, .out_valid, .out_pc, .out_instr, .out_bp, .out_empty
  );

  int errors = 0;
  task chk(string s, logic c); if (!c) begin $display("FAIL %s", s); errors++; end endtask
  task chkh(string s, word_t g, word_t e);
    if (g !== e) begin $display("FAIL %s: got %h exp %h", s, g, e); errors++; end
  endtask

  task automatic idle();
    ignt = 0; irvalid = 0; irdata = '0; irdata_line = '0; iwmask = '0;
    bp_pred = BP_PRED_NONE; out_pop_n = 0;
    for (int i = 0; i < 4; i++) bp_pred_vec[i] = BP_PRED_NONE;
    word_valid = 4'hF;   // all words present unless a test trims them
    redirect_resolve_valid = 0; redirect_resolve_target = '0; ex_mem_en = 0;
    redirect_trap_valid = 0; redirect_trap_target = '0;
  endtask

  task automatic line_resp(input word_t reqaddr,
                           input [1:0] woff,
                           input word_t w0, w1, w2, w3);
    @(negedge clk); ignt = 1;
    @(negedge clk); ignt = 0;
    @(negedge clk);
    irvalid = 1;
    irdata_line[0] = w0; irdata_line[1] = w1;
    irdata_line[2] = w2; irdata_line[3] = w3;
    irdata = (woff==0)?w0:(woff==1)?w1:(woff==2)?w2:w3;
    for (int i = 0; i < 4; i++) iwmask[i] = (2'(i) >= woff);
    @(negedge clk);
    irvalid = 0; iwmask = '0;
  endtask

  initial begin
    idle();
    #12 rst_n = 1;
    @(negedge clk);

    chk("ireq after reset", ireq === 1'b1);
    chkh("iaddr = reset pc", iaddr, BASE);

    line_resp(BASE, 2'd0, 32'hAAAA0000, 32'hAAAA0004, 32'hAAAA0008, 32'hAAAA000C);
    @(negedge clk);
    chk("after line fill: count>=2 (out_valid[1])", out_valid[1] === 1'b1);
    chkh("slot0 pc = BASE",      out_pc[0],    BASE);
    chkh("slot0 instr = w0",     out_instr[0], 32'hAAAA0000);
    chkh("slot1 pc = BASE+4",    out_pc[1],    BASE + 32'd4);
    chkh("slot1 instr = w1",     out_instr[1], 32'hAAAA0004);

    @(negedge clk); out_pop_n = 2'd2;
    @(negedge clk); out_pop_n = 2'd0;
    @(negedge clk);
    chkh("after pop2: slot0 pc = BASE+8",  out_pc[0], BASE + 32'd8);
    chkh("after pop2: slot0 instr = w2",   out_instr[0], 32'hAAAA0008);
    chkh("after pop2: slot1 pc = BASE+12", out_pc[1], BASE + 32'd12);

    @(negedge clk); out_pop_n = 2'd1;
    @(negedge clk); out_pop_n = 2'd0;
    @(negedge clk);
    chkh("after pop1: slot0 pc = BASE+12", out_pc[0], BASE + 32'd12);
    chk ("after draining to 1: out_valid[0]", out_valid[0] === 1'b1);
    chk ("after draining to 1: !out_valid[1]", out_valid[1] === 1'b0);

    @(negedge clk); out_pop_n = 2'd1;
    @(negedge clk); out_pop_n = 2'd0;
    @(negedge clk);
    chk("queue empty", out_empty === 1'b1);

    chkh("next request = next line base", iaddr, BASE + 32'd16);

    bp_pred_vec[2] = BP_PRED_NONE; bp_pred_vec[2].taken = 1'b1;
    bp_pred_vec[2].target = 32'h8000_2000;
    bp_pred_vec[3] = BP_PRED_NONE;   // word 3: not taken
    word_valid = 4'hF;               // both present words bank
    line_resp(BASE + 32'd16, 2'd2, 32'hBBBB0000, 32'hBBBB0004,
              32'hBBBB0008, 32'hBBBB000C);
    for (int i = 0; i < 4; i++) bp_pred_vec[i] = BP_PRED_NONE;
    @(negedge clk);
    chk ("partial fill: count==2 -> out_valid[1]", out_valid[1] === 1'b1);
    chkh("partial slot0 pc = BASE+16+8",  out_pc[0], BASE + 32'd24);
    chkh("partial slot0 instr = w2",      out_instr[0], 32'hBBBB0008);
    chkh("partial slot1 pc = BASE+16+12", out_pc[1], BASE + 32'd28);
    chkh("partial slot1 instr = w3",      out_instr[1], 32'hBBBB000C);
    chk ("partial: word2 carries its own bp (taken)", out_bp[0].taken === 1'b1);
    chk ("partial: word3 carries its own bp (not-taken)", out_bp[1].taken === 1'b0);

    @(negedge clk);
    redirect_trap_valid = 1; redirect_trap_target = 32'h8000_1000;
    @(negedge clk);
    redirect_trap_valid = 0;
    @(negedge clk);
    chk("after flush: empty", out_empty === 1'b1);

    if (errors == 0) $display("FETCH_QUEUE PASS");
    else $display("FETCH_QUEUE FAIL: %0d", errors);
    $finish;
  end

  initial begin #20000; $display("FETCH_QUEUE TIMEOUT"); $finish; end
endmodule
