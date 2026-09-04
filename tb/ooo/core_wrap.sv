// The plain-memory shell for the OoO `core`.
`timescale 1ns/1ps
module core_wrap
  import rv32i_pkg::*;
#(
  parameter word_t RESET_PC_P = RESET_PC,
  parameter bit USE_HISTORY = 1'b1,
  parameter bit OVF_COUNT   = 1'b1
) (
  input  logic  clk,
  input  logic  rst_n,
  output word_t imem_addr,
  input  logic [3:0][31:0] imem_line,   // 4-word line of imem_addr
  output word_t dmem_addr,
  output logic  dmem_we,
  output logic [3:0] dmem_wstrb,
  output word_t dmem_wdata,
  input  word_t dmem_rdata,
  input  logic  irq_timer,
  input  logic  irq_soft,
  input  logic  irq_ext
);
  logic  ireq, ignt, irvalid;
  word_t iaddr, irdata;
  logic  dreq, dgnt, dwe, drvalid;
  logic [3:0] dwstrb;
  word_t daddr, dwdata, drdata;

  core #(.RESET_PC_P(RESET_PC_P), .USE_HISTORY(USE_HISTORY),
         .OVF_COUNT(OVF_COUNT)) u_core (
    .hart_id_i(32'd0),   // single-hart harness: mhartid = 0
    .snoop_valid_i(1'b0), .snoop_addr_i('0),
    .lrsc_lr_valid_o(), .lrsc_sc_valid_o(), .lrsc_addr_o(),
    .lrsc_acc_valid_o(), .lrsc_sc_success_i(1'b0),
    .clk, .rst_n,
    .ireq, .ignt, .iaddr, .irvalid, .irdata,
    .irdata_line, .iwmask,
    .dreq, .dgnt, .daddr, .dwe, .dwstrb, .dwdata, .drvalid, .drdata,
    .ev_ic_miss(1'b0), .ev_dc_miss(1'b0), .ev_dc_wb(1'b0),
    .ic_flush(), .dc_flush(), .dc_flush_done(1'b1),
    .irq_timer, .irq_soft, .irq_ext,
    .rvfi_valid(), .rvfi_order(), .rvfi_insn(), .rvfi_trap(),
    .rvfi_pc_rdata(), .rvfi_rd_addr(), .rvfi_rd_wdata(),
    .rvfi_halt(), .rvfi_intr(), .rvfi_mode(), .rvfi_ixl(),
    .rvfi_rs1_addr(), .rvfi_rs2_addr(), .rvfi_rs1_rdata(), .rvfi_rs2_rdata(),
    .rvfi_pc_wdata(),
    .rvfi_mem_addr(), .rvfi_mem_rmask(), .rvfi_mem_wmask(),
    .rvfi_mem_rdata(), .rvfi_mem_wdata(),
    .trap_taken()
  );

  logic  ivld_q;
  word_t iaddr_q;
  assign ignt = ireq;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ivld_q  <= 1'b0;
      iaddr_q <= '0;
    end else begin
      ivld_q <= ireq && ignt;
      if (ireq && ignt) iaddr_q <= iaddr;
    end
  end
  assign imem_addr = iaddr_q;
  assign irvalid   = ivld_q;
  assign irdata      = imem_line[iaddr_q[3:2]];
  logic [3:0][31:0] irdata_line;
  logic [3:0]       iwmask;
  assign irdata_line = imem_line;
  logic [3:0] iwmask_w;
  always_comb
    for (int i = 0; i < 4; i++) iwmask_w[i] = (2'(i) >= iaddr_q[3:2]);
  assign iwmask = iwmask_w;

  logic  dvld_q, dwe_q;
  word_t daddr_q, dwdata_q;
  logic [3:0] dwstrb_q;
  assign dgnt = dreq;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dvld_q <= 1'b0; dwe_q <= 1'b0; daddr_q <= '0;
      dwdata_q <= '0; dwstrb_q <= '0;
    end else begin
      dvld_q <= dreq && dgnt;
      if (dreq && dgnt) begin
        daddr_q  <= daddr;
        dwe_q    <= dwe;
        dwdata_q <= dwdata;
        dwstrb_q <= dwstrb;
      end
    end
  end
  assign dmem_addr  = daddr_q;
  assign dmem_we    = dvld_q && dwe_q;
  assign dmem_wstrb = dwstrb_q;
  assign dmem_wdata = dwdata_q;
  assign drdata     = dmem_rdata;
  assign drvalid    = dvld_q;
endmodule
