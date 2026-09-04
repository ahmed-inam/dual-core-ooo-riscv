// Unit gate for LR/SC instruction decode.
module tb_decode_lrsc
  import rv32i_pkg::*;
();
  word_t  instr;
  ctrl_t  ctrl;
  int     errors = 0, checked = 0;

  decoder dut (.instr(instr), .ctrl(ctrl));

  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  function automatic word_t amo(input logic [4:0] funct5, input logic aq,
                                input logic rl, input logic [4:0] rs2,
                                input logic [4:0] rs1, input logic [2:0] funct3,
                                input logic [4:0] rd);
    return {funct5, aq, rl, rs2, rs1, funct3, rd, 7'h2F};
  endfunction

  initial begin
    $display("=== tb_decode_lrsc ===");

    instr = amo(5'h02, 1'b0, 1'b0, 5'd0, 5'd10, 3'b010, 5'd5); #1;
    ck("LR.W: is_lr set",            ctrl.is_lr  === 1'b1);
    ck("LR.W: is_sc clear",          ctrl.is_sc  === 1'b0);
    ck("LR.W: it IS a load",         ctrl.mem_re === 1'b1);
    ck("LR.W: not a store",          ctrl.mem_we === 1'b0);
    ck("LR.W: word sized",           ctrl.mem_size === MEM_W);
    ck("LR.W: writes rd",            ctrl.rf_we  === 1'b1);
    ck("LR.W: uses rs1 (address)",   ctrl.uses_rs1 === 1'b1);
    ck("LR.W: does NOT use rs2",     ctrl.uses_rs2 === 1'b0);
    ck("LR.W: not illegal",          ctrl.illegal === 1'b0);
    ck("LR.W: immediate is NONE (address = rs1 + 0)", ctrl.imm_type === IMM_NONE);
    instr = amo(5'h02, 1'b0, 1'b0, 5'd3, 5'd10, 3'b010, 5'd5);
    #1;
    ck("LR.W with rs2 != x0 is ILLEGAL", ctrl.illegal === 1'b1 && ctrl.is_lr === 1'b0);

    instr = amo(5'h03, 1'b0, 1'b0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("SC.W: is_sc set",            ctrl.is_sc  === 1'b1);
    ck("SC.W: is_lr clear",          ctrl.is_lr  === 1'b0);
    ck("SC.W: it IS a store",        ctrl.mem_we === 1'b1);
    ck("SC.W: not a load",           ctrl.mem_re === 1'b0);
    ck("SC.W: uses rs2 (store data)", ctrl.uses_rs2 === 1'b1);
    ck("SC.W: WRITES rd (0=success, 1=failure)", ctrl.rf_we === 1'b1);
    ck("SC.W: not illegal",          ctrl.illegal === 1'b0);
    ck("SC.W: immediate is NONE",    ctrl.imm_type === IMM_NONE);

    instr = amo(5'h02, 1'b1, 1'b1, 5'd0, 5'd10, 3'b010, 5'd5); #1;
    ck("LR.W.aq.rl still decodes as LR", ctrl.is_lr === 1'b1 && ctrl.illegal === 1'b0);
    instr = amo(5'h03, 1'b1, 1'b0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("SC.W.aq still decodes as SC",    ctrl.is_sc === 1'b1 && ctrl.illegal === 1'b0);

    instr = amo(5'h00, 0,0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("amoadd.w  still ILLEGAL", ctrl.illegal === 1'b1 && !ctrl.is_lr && !ctrl.is_sc);
    instr = amo(5'h01, 0,0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("amoswap.w still ILLEGAL", ctrl.illegal === 1'b1);
    instr = amo(5'h04, 0,0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("amoxor.w  still ILLEGAL", ctrl.illegal === 1'b1);
    instr = amo(5'h08, 0,0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("amoor.w   still ILLEGAL", ctrl.illegal === 1'b1);
    instr = amo(5'h0C, 0,0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("amoand.w  still ILLEGAL", ctrl.illegal === 1'b1);
    instr = amo(5'h1C, 0,0, 5'd7, 5'd11, 3'b010, 5'd6); #1;
    ck("amomaxu.w still ILLEGAL", ctrl.illegal === 1'b1);

    instr = amo(5'h02, 0,0, 5'd0, 5'd10, 3'b011, 5'd5); #1;
    ck("LR.D ILLEGAL on RV32", ctrl.illegal === 1'b1 && ctrl.is_lr === 1'b0);
    instr = amo(5'h03, 0,0, 5'd7, 5'd11, 3'b011, 5'd6); #1;
    ck("SC.D ILLEGAL on RV32", ctrl.illegal === 1'b1 && ctrl.is_sc === 1'b0);
    instr = amo(5'h02, 0,0, 5'd0, 5'd10, 3'b000, 5'd5); #1;
    ck("LR with funct3=000 ILLEGAL", ctrl.illegal === 1'b1);

    instr = {12'd8, 5'd10, 3'b010, 5'd5, 7'h03}; #1;      // lw x5, 8(x10)
    ck("plain LW unaffected: load, not LR",
       ctrl.mem_re === 1'b1 && ctrl.is_lr === 1'b0 && ctrl.imm_type === IMM_I);
    instr = {7'd0, 5'd7, 5'd11, 3'b010, 5'd0, 7'h23}; #1;  // sw x7, 0(x11)
    ck("plain SW unaffected: store, not SC, no rd write",
       ctrl.mem_we === 1'b1 && ctrl.is_sc === 1'b0 && ctrl.rf_we === 1'b0);

    $display("=== tb_decode_lrsc: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_DECODE_LRSC PASS");
    else             $display("TB_DECODE_LRSC BROKEN");
    $finish;
  end
endmodule
