// V-line trace printer, OoO side.
`timescale 1ns/1ps
module tb_trace_o;
  import rv32i_pkg::*;
  logic clk, rst_n;
  word_t imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0][31:0] imem_line;
  logic dmem_we; logic [3:0] dmem_wstrb;
  core_wrap u_core (.clk,.rst_n,.imem_addr,.imem_line,
    .dmem_addr,.dmem_we,.dmem_wstrb,.dmem_wdata,.dmem_rdata,
    .irq_timer(1'b0),.irq_soft(1'b0),.irq_ext(1'b0));
  word_t mem [0:65535];
  for (genvar wi = 0; wi < 4; wi++)
    assign imem_line[wi] = mem[{imem_addr[17:4], 2'(wi)}];
  assign dmem_rdata = mem[dmem_addr[17:2]];
  always_ff @(posedge clk) if (dmem_we) begin
    if (dmem_wstrb[0]) mem[dmem_addr[17:2]][7:0]  <=dmem_wdata[7:0];
    if (dmem_wstrb[1]) mem[dmem_addr[17:2]][15:8] <=dmem_wdata[15:8];
    if (dmem_wstrb[2]) mem[dmem_addr[17:2]][23:16]<=dmem_wdata[23:16];
    if (dmem_wstrb[3]) mem[dmem_addr[17:2]][31:24]<=dmem_wdata[31:24];
  end
  always_ff @(posedge clk) if (u_core.u_core.rvfi_valid)
    $display("V %0d %h %h %0d %h",
      u_core.u_core.rvfi_order, u_core.u_core.rvfi_pc_rdata,
      u_core.u_core.rvfi_insn, u_core.u_core.rvfi_rd_addr,
      u_core.u_core.rvfi_rd_wdata);
  word_t tohost_addr;
  initial clk=0; always #5 clk=~clk;
  always @(posedge clk)
    if (rst_n && dmem_we && dmem_addr == tohost_addr && dmem_wdata != 0) begin
      $display("TRACE DONE tohost=%0d", dmem_wdata);
      $finish;
    end
  string hexfile;
  initial begin
    if (!$value$plusargs("HEX=%s", hexfile)) hexfile = "asm/mext_smoke.hex";
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) tohost_addr = 32'h1000;
    for (int i = 0; i < 65536; i++) mem[i] = '0;
    $readmemh(hexfile, mem);
    rst_n = 0; #12 rst_n = 1;
    #60_000_000 $display("TRACE TIMEOUT"); $finish;
  end
endmodule
