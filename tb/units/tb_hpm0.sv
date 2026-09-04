// The four unimplemented HPM counters must read constant zero.
`timescale 1ns/1ps
module tb_hpm0;
  import rv32i_pkg::*;
  logic clk, rst_n;
  logic instr_retired, branch_resolved, branch_mispred, stall_cycle, flush_cycle;
  logic [11:0] raddr, commit_addr; word_t rdata, commit_operand;
  logic addr_hit, commit_we; csr_op_e commit_op;
  perf_counters #(.HPM_ENABLE(1'b0)) u_pc (
    .clk,.rst_n,.instr_retired,.branch_resolved,.branch_mispred,.stall_cycle,
    .flush_cycle,.raddr,.rdata,.addr_hit,.commit_we,.commit_addr,.commit_op,.commit_operand);
  initial clk=0; always #5 clk=~clk;
  int errors=0;
  initial begin
    instr_retired=0;branch_resolved=0;branch_mispred=0;stall_cycle=0;flush_cycle=0;
    commit_we=0;commit_addr='0;commit_op=CSR_OP_NONE;commit_operand='0;raddr='0;
    rst_n=0; @(posedge clk); rst_n=1; #1;
    repeat (20) begin
      instr_retired=1;branch_resolved=1;branch_mispred=1;stall_cycle=1;flush_cycle=1;
      @(posedge clk); #1;
    end
    instr_retired=0;branch_resolved=0;branch_mispred=0;stall_cycle=0;flush_cycle=0;
    raddr=CSR_MINSTRET; #1;
    if (rdata!=32'd20) begin $display("FAIL minstret=%0d exp 20",rdata); errors++; end
    else $display("  ok   minstret still counts (architectural): %0d", rdata);
    raddr=CSR_MCYCLE; #1;
    if (rdata==0) begin $display("FAIL mcycle stopped"); errors++; end
    else $display("  ok   mcycle still counts: %0d", rdata);
    foreach_check: begin
      logic [11:0] a [4] = '{CSR_MHPM3,CSR_MHPM4,CSR_MHPM5,CSR_MHPM6};
      for (int i=0;i<4;i++) begin
        raddr=a[i]; #1;
        if (rdata!=0) begin $display("FAIL hpm%0d=%0d exp 0",i+3,rdata); errors++; end
        else $display("  ok   mhpm%0d reads 0 (compiled out)", i+3);
      end
    end
    commit_we=1; commit_addr=CSR_MHPM4; commit_op=CSR_OP_RW; commit_operand=32'hDEAD;
    @(posedge clk); #1; commit_we=0;
    raddr=CSR_MHPM4; #1;
    if (rdata!=0) begin $display("FAIL write resurrected hpm4=%h",rdata); errors++; end
    else $display("  ok   write to disabled counter ignored");
    if (errors==0) $display("HPM0 PASS: instrumentation compiled out, architectural counters intact");
    else $display("HPM0 FAIL: %0d", errors);
    $finish;
  end
endmodule
