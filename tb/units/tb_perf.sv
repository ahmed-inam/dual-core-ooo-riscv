// Unit gate for perf_counters, driven directly with no core attached.
`timescale 1ns/1ps
module tb_perf;
  import rv32i_pkg::*;

  logic clk, rst_n;
  logic instr_retired, branch_resolved, branch_mispred, stall_cycle, flush_cycle;
  logic [11:0] raddr, commit_addr;
  word_t rdata, commit_operand;
  logic  addr_hit, commit_we;
  csr_op_e commit_op;

  perf_counters u_pc (
    .clk, .rst_n,
    .instr_retired, .branch_resolved, .branch_mispred, .stall_cycle, .flush_cycle,
    .raddr, .rdata, .addr_hit,
    .commit_we, .commit_addr, .commit_op, .commit_operand
  );

  initial clk = 0; always #5 clk = ~clk;
  int errors = 0;

  task automatic chk(input string name, input word_t got, input word_t exp);
    if (got !== exp) begin
      $display("  FAIL %-34s got 0x%08h exp 0x%08h", name, got, exp);
      errors++;
    end else $display("  ok   %-34s 0x%08h", name, got);
  endtask

  task automatic rd(input logic [11:0] a, output word_t v);
    raddr = a; #1; v = rdata;
  endtask

  task automatic tick(input logic ret, input logic bres, input logic bmis,
                      input logic stl, input logic flsh);
    instr_retired=ret; branch_resolved=bres; branch_mispred=bmis;
    stall_cycle=stl;  flush_cycle=flsh;
    @(posedge clk); #1;
    instr_retired=0; branch_resolved=0; branch_mispred=0;
    stall_cycle=0;   flush_cycle=0;
  endtask

  task automatic wr(input logic [11:0] a, input word_t v);
    commit_we=1; commit_addr=a; commit_op=CSR_OP_RW; commit_operand=v;
    @(posedge clk); #1;
    commit_we=0; commit_addr='0; commit_op=CSR_OP_NONE; commit_operand='0;
  endtask

  task automatic wset(input logic [11:0] a, input word_t v);
    commit_we=1; commit_addr=a; commit_op=CSR_OP_RS; commit_operand=v;
    @(posedge clk); #1;
    commit_we=0; commit_addr='0; commit_op=CSR_OP_NONE; commit_operand='0;
  endtask

  word_t v, v2;
  initial begin
    instr_retired=0; branch_resolved=0; branch_mispred=0;
    stall_cycle=0; flush_cycle=0; commit_we=0; commit_addr='0; commit_op=CSR_OP_NONE; commit_operand='0;
    raddr='0;
    rst_n=0; @(posedge clk); @(posedge clk); #1;

    $display("=== 1. reset clears every counter ===");
    rd(CSR_MCYCLE,   v); chk("mcycle after reset",   v, 32'd0);
    rd(CSR_MINSTRET, v); chk("minstret after reset", v, 32'd0);
    rd(CSR_MHPM4,    v); chk("mhpm4 after reset",    v, 32'd0);

    rst_n=1; #1;

    $display("=== 2. mcycle free-runs, minstret does not ===");
    repeat (10) tick(0,0,0,0,0);
    rd(CSR_MCYCLE,   v); chk("mcycle after 10 cycles",  v, 32'd10);
    rd(CSR_MINSTRET, v); chk("minstret with no retires", v, 32'd0);

    $display("=== 3. each strobe counts its own counter ===");
    repeat (4) tick(1,0,0,0,0);          // 4 retires
    repeat (7) tick(0,1,0,0,0);          // 7 branches
    repeat (3) tick(0,1,1,0,0);          // 3 branches, all mispredicted
    repeat (5) tick(0,0,0,1,0);          // 5 stall cycles
    repeat (2) tick(0,0,0,0,1);          // 2 flush cycles
    rd(CSR_MINSTRET, v); chk("minstret = 4",            v, 32'd4);
    rd(CSR_MHPM3,    v); chk("branches resolved = 10",  v, 32'd10);
    rd(CSR_MHPM4,    v); chk("mispredicts = 3",         v, 32'd3);
    rd(CSR_MHPM5,    v); chk("stall cycles = 5",        v, 32'd5);
    rd(CSR_MHPM6,    v); chk("flush cycles = 2",        v, 32'd2);

    $display("=== 4. 64-bit carry (what instret_overflow probes) ===");
    wr(CSR_MINSTRET, 32'hFFFF_FFFF);
    rd(CSR_MINSTRET,  v); chk("minstret seeded lo",     v, 32'hFFFF_FFFF);
    rd(CSR_MINSTRETH, v); chk("minstreth still 0",      v, 32'd0);
    tick(1,0,0,0,0);                      // one retire -> must carry
    rd(CSR_MINSTRET,  v); chk("lo wrapped to 0",        v, 32'd0);
    rd(CSR_MINSTRETH, v); chk("hi carried to 1",        v, 32'd1);

    $display("=== 5. half-writes are atomic (other half must not move) ===");
    wr(CSR_MCYCLE, 32'hFFFF_FFFF);
    rd(CSR_MCYCLEH, v); chk("mcycleh before coincident write", v, 32'd0);
    wr(CSR_MCYCLE, 32'h0000_0055);        // write coincides with would-be carry
    rd(CSR_MCYCLE,  v); chk("mcycle lo takes written value",   v, 32'h55);
    rd(CSR_MCYCLEH, v); chk("mcycleh NOT bumped by carry",     v, 32'd0);
    rd(CSR_MCYCLE, v);
    wr(CSR_MCYCLEH, 32'h0000_00AA);
    rd(CSR_MCYCLEH, v2); chk("mcycleh takes written value",    v2, 32'hAA);
    rd(CSR_MCYCLE,  v2); chk("mcycle lo held across hi write", v2, v);

    $display("=== 6. addr_hit decode ===");
    raddr = CSR_MCYCLE;    #1; chk("hit on mcycle",    {31'd0, addr_hit}, 32'd1);
    raddr = CSR_MHPM6H;    #1; chk("hit on mhpm6h",    {31'd0, addr_hit}, 32'd1);
    raddr = CSR_MINSTRETH; #1; chk("hit on minstreth", {31'd0, addr_hit}, 32'd1);
    raddr = CSR_MSCRATCH;  #1; chk("no hit on mscratch",{31'd0, addr_hit}, 32'd0);
    raddr = 12'hBFF;       #1; chk("no hit on 0xBFF",  {31'd0, addr_hit}, 32'd0);
    raddr = CSR_MCYCLE;    #1;

    $display("=== 7. csrrs read-modify-write on a counter half ===");
    wr(CSR_MHPM4, 32'h0000_00F0);
    wset(CSR_MHPM4, 32'h0000_000F);
    rd(CSR_MHPM4, v); chk("csrrs OR'd bits into mhpm4", v, 32'h0000_00FF);

    $display("=== 8. counters are independent ===");
    rd(CSR_MHPM3, v);
    repeat (3) tick(0,0,0,0,1);           // flushes only
    rd(CSR_MHPM3, v2); chk("mhpm3 unchanged by flushes", v2, v);

    if (errors == 0) $display("PERF PASS: all perf_counters checks");
    else             $display("PERF FAIL: %0d error(s)", errors);
    $finish;
  end
endmodule
