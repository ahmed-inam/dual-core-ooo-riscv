// RVFI trace tap on the out-of-order core, perfect memory.
`timescale 1ns/1ps
module tb_rvfi_ooo;
  import rv32i_pkg::*;
  logic clk, rst_n;
  word_t imem_addr, dmem_addr, dmem_wdata, dmem_rdata;
  logic [3:0][31:0] imem_line;
  logic dmem_we; logic [3:0] dmem_wstrb;

  core_wrap #(.RESET_PC_P(32'h8000_0000)) u_core (
               .clk,.rst_n,.imem_addr,.imem_line,
               .dmem_addr,.dmem_we,.dmem_wstrb,.dmem_wdata,.dmem_rdata,
               .irq_timer(1'b0),.irq_soft(1'b0),.irq_ext(1'b0));

  word_t mem [0:65535];   // 256KB unified; [17:2] aliases the 0x8000_0000 region
  for (genvar wi = 0; wi < 4; wi++)
    assign imem_line[wi] = mem[{imem_addr[17:4], 2'(wi)}];
  assign dmem_rdata = mem[dmem_addr[17:2]];
  always_ff @(posedge clk) if (dmem_we) begin
    if (dmem_wstrb[0]) mem[dmem_addr[17:2]][7:0]  <=dmem_wdata[7:0];
    if (dmem_wstrb[1]) mem[dmem_addr[17:2]][15:8] <=dmem_wdata[15:8];
    if (dmem_wstrb[2]) mem[dmem_addr[17:2]][23:16]<=dmem_wdata[23:16];
    if (dmem_wstrb[3]) mem[dmem_addr[17:2]][31:24]<=dmem_wdata[31:24];
  end

  longint unsigned fault_order;
  logic fault_armed;

  always_ff @(posedge clk) begin
    for (int i = 0; i < $size(u_core.u_core.rvfi_valid); i++)
      if (u_core.u_core.rvfi_valid[i]) begin
        automatic logic [31:0] wd = u_core.u_core.rvfi_rd_wdata[i];
        if (fault_armed && u_core.u_core.rvfi_order[i] == fault_order)
          wd = wd ^ 32'h0000_0001;
        $display("V %0d %h %h %0d %h",
                 u_core.u_core.rvfi_order[i], u_core.u_core.rvfi_pc_rdata[i],
                 u_core.u_core.rvfi_insn[i],  u_core.u_core.rvfi_rd_addr[i], wd);
      end
  end
  always_ff @(posedge clk)
    for (int i = 0; i < $size(u_core.u_core.rvfi_valid); i++)
      if (u_core.u_core.rvfi_trap[i])
        $display("X trap pc=%h", u_core.u_core.rvfi_pc_rdata[i]);

  logic rvfi_x_trace;
  initial rvfi_x_trace = $test$plusargs("RVFI_X");
  always_ff @(posedge clk)
    if (rvfi_x_trace)
      for (int i = 0; i < $size(u_core.u_core.rvfi_valid); i++)
        if (u_core.u_core.rvfi_valid[i])
          $display("R pc=%h npc=%h rs1[%0d]=%h rs2[%0d]=%h intr=%0d mode=%0d ixl=%0d halt=%0d",
                   u_core.u_core.rvfi_pc_rdata[i],  u_core.u_core.rvfi_pc_wdata[i],
                   u_core.u_core.rvfi_rs1_addr[i],  u_core.u_core.rvfi_rs1_rdata[i],
                   u_core.u_core.rvfi_rs2_addr[i],  u_core.u_core.rvfi_rs2_rdata[i],
                   u_core.u_core.rvfi_intr[i],      u_core.u_core.rvfi_mode[i],
                   u_core.u_core.rvfi_ixl[i],       u_core.u_core.rvfi_halt[i]);

  always_ff @(posedge clk)
    if (rvfi_x_trace)
      for (int i = 0; i < $size(u_core.u_core.rvfi_valid); i++)
        if (u_core.u_core.rvfi_valid[i]
            && (|u_core.u_core.rvfi_mem_rmask[i] || |u_core.u_core.rvfi_mem_wmask[i]))
          $display("M pc=%h addr=%h rmask=%b rdata=%h wmask=%b wdata=%h",
                   u_core.u_core.rvfi_pc_rdata[i],  u_core.u_core.rvfi_mem_addr[i],
                   u_core.u_core.rvfi_mem_rmask[i], u_core.u_core.rvfi_mem_rdata[i],
                   u_core.u_core.rvfi_mem_wmask[i], u_core.u_core.rvfi_mem_wdata[i]);

  word_t tohost_addr;
  initial clk=0; always #5 clk=~clk;

  initial begin
    string hexfile; longint unsigned fo;
    if (!$value$plusargs("HEX=%s", hexfile))    hexfile = "asm/ctest_rvfi.hex";
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) tohost_addr = 32'h8000_1000;
    fault_armed = $value$plusargs("FAULT=%d", fo);
    fault_order = fo;
    for (int i = 0; i < 65536; i++) mem[i] = '0;
    $readmemh(hexfile, mem);
    rst_n = 0; #12 rst_n = 1;
    #200_000_000 $display("RVFI TIMEOUT"); $finish;
  end

  always @(posedge clk) begin
    if (rst_n && dmem_we && dmem_addr == tohost_addr && dmem_wdata != 0) begin
      if (dmem_wdata == 32'd1) $display("RVFI DONE PASS");
      else $display("RVFI DONE FAIL: testnum %0d", dmem_wdata >> 1);
      $finish;
    end
  end
endmodule
