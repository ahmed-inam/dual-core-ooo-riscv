// Unit gate for the out-of-order core through plain memory.
`timescale 1ns/1ps
module tb_core_ooo;
  import rv32i_pkg::*;
  logic clk, rst_n;
  word_t imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0][31:0] imem_line;
  logic dmem_we; logic [3:0] dmem_wstrb;

  core_wrap u_core (.clk,.rst_n,.imem_addr,.imem_line,
               .dmem_addr,.dmem_we,.dmem_wstrb,.dmem_wdata,.dmem_rdata,
               .irq_timer(irq_timer_r),.irq_soft(1'b0),.irq_ext(1'b0));
  logic irq_timer_r;
  int   irq_at;
  int   cyc;
  initial if (!$value$plusargs("IRQ_AT=%d", irq_at)) irq_at = -1;
  always_ff @(posedge clk) begin
    if (!rst_n) begin irq_timer_r <= 0; cyc <= 0; end
    else begin
      cyc <= cyc + 1;
      if (irq_at >= 0 && cyc == irq_at) irq_timer_r <= 1'b1;
      if (dmem_we && dmem_addr == tohost_addr - 32'h10) irq_timer_r <= 1'b0;
    end
  end

  word_t mem [0:65535];   // 256KB unified
  for (genvar wi = 0; wi < 4; wi++)
    assign imem_line[wi] = mem[{imem_addr[17:4], 2'(wi)}];
  assign dmem_rdata = mem[dmem_addr[17:2]];
  always_ff @(posedge clk) if (dmem_we) begin
    if (dmem_wstrb[0]) mem[dmem_addr[17:2]][7:0]  <=dmem_wdata[7:0];
    if (dmem_wstrb[1]) mem[dmem_addr[17:2]][15:8] <=dmem_wdata[15:8];
    if (dmem_wstrb[2]) mem[dmem_addr[17:2]][23:16]<=dmem_wdata[23:16];
    if (dmem_wstrb[3]) mem[dmem_addr[17:2]][31:24]<=dmem_wdata[31:24];
  end

  word_t tohost_addr;
  initial clk=0; always #5 clk=~clk;
  always_ff @(posedge clk)
    for (int i = 0; i < $size(u_core.u_core.commit_o); i++)
      if (u_core.u_core.commit_o[i].valid)
        $display("R %h", u_core.u_core.commit_o[i].pc);
  always_ff @(posedge clk) if (u_core.u_core.exc_at_head)
    $display("[T] exc-at-head cause=%h pc=%h (recovery handles or walks it)",
             u_core.u_core.exc_cause, u_core.u_core.exc_pc);

  always @(posedge clk) begin
    if (rst_n && dmem_we && dmem_addr == tohost_addr && dmem_wdata != 0) begin
      if (dmem_wdata == 32'd1) $display("COMPLIANCE PASS");
      else $display("COMPLIANCE FAIL: testnum %0d", dmem_wdata >> 1);
      $finish;
    end
  end

  string hexfile;
  initial begin
    if (!$value$plusargs("HEX=%s", hexfile)) begin $display("no +HEX"); $finish; end
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) begin $display("no +TOHOST"); $finish; end
    for (int i=0;i<65536;i++) mem[i]='0;
    $readmemh(hexfile, mem);
    rst_n=0; #12 rst_n=1;
    #2_000_000;
    $display("COMPLIANCE TIMEOUT");
    $finish;
  end
endmodule
