// Synthesizable top: the cluster, the CLINT, and a block-RAM memory. No RVFI,
// no simulation memory, no elaboration-time latency knobs.
module fpga_top
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;
  import platform_cfg_pkg::*;
#(
  parameter word_t       RESET_PC_P = 32'h8000_0000,
  parameter int unsigned MEM_WORDS  = 65536,
  parameter              INIT_HEX   = "",
  parameter int unsigned RTC_DIV    = 100           // clocks per mtime tick
) (
  input  logic clk,
  input  logic rst_n,
  output logic heartbeat,                           // toggles on every retirement
  output logic [NUM_HARTS-1:0] mtip_o,
  output logic [NUM_HARTS-1:0] msip_o
);

  axi4_if #(.ID_W(axi4_pkg::M_ID_W)) s0_if (.aclk(clk), .arst_n(rst_n));
  axi4_if #(.ID_W(axi4_pkg::M_ID_W)) s1_if (.aclk(clk), .arst_n(rst_n));

  logic [NUM_HARTS-1:0][COMMIT_W-1:0] rvfi_valid;

  cluster #(.RESET_PC_P(RESET_PC_P)) u_cluster (
    .clk, .rst_n,
    .s0_if(s0_if.mst), .s1_if(s1_if.mst),
    .msip_i(msip_o),
    .mtip_i(mtip_o),
    .rvfi_valid(rvfi_valid),
    .rvfi_order(), .rvfi_insn(), .rvfi_pc_rdata(),
    .rvfi_halt(), .rvfi_intr(), .rvfi_mode(), .rvfi_ixl(),
    .rvfi_rs1_addr(), .rvfi_rs2_addr(), .rvfi_rs1_rdata(), .rvfi_rs2_rdata(),
    .rvfi_pc_wdata(),
    .rvfi_mem_addr(), .rvfi_mem_rmask(), .rvfi_mem_wmask(),
    .rvfi_mem_rdata(), .rvfi_mem_wdata(),
    .rvfi_rd_wdata(), .rvfi_rd_addr(), .rvfi_trap(),
    .dreq_o(), .dwe_o(), .daddr_o(), .dwdata_o(),
    .ev_starve_i()
  );

  logic  cl_req, cl_gnt, cl_we, cl_rvalid;
  word_t cl_addr, cl_wdata, cl_rdata;
  logic [3:0] cl_wstrb;

  axi4_word_slv u_s0 (
    .clk, .rst_n, .sif(s0_if.slv),
    .req(cl_req), .gnt(cl_gnt), .addr(cl_addr), .we(cl_we),
    .wstrb(cl_wstrb), .wdata(cl_wdata), .rvalid(cl_rvalid), .rdata(cl_rdata)
  );

  localparam int unsigned RTC_W = $clog2(RTC_DIV + 1);
  localparam logic [RTC_W-1:0] RTC_LAST = RTC_W'(RTC_DIV - 1);
  logic [RTC_W-1:0] rtc_cnt_q;
  logic rtc_tick;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                      rtc_cnt_q <= '0;
    else if (rtc_cnt_q == RTC_LAST)  rtc_cnt_q <= '0;
    else                             rtc_cnt_q <= rtc_cnt_q + 1'b1;
  end
  assign rtc_tick = (rtc_cnt_q == RTC_LAST);

  clint u_clint (
    .clk, .rst_n,
    .req(cl_req), .gnt(cl_gnt), .addr(cl_addr), .we(cl_we),
    .wstrb(cl_wstrb), .wdata(cl_wdata),
    .rvalid(cl_rvalid), .rdata(cl_rdata),
    .rtc_tick,
    .msip_o, .mtip_o
  );

  axi_req_t  mem_req_raw, mem_req;
  axi_resp_t mem_resp;

  axi4_coreaxi_slv u_s1 (
    .clk, .rst_n, .sif(s1_if.slv),
    .mem_req(mem_req_raw), .mem_resp(mem_resp)
  );

  always_comb begin
    mem_req         = mem_req_raw;
    mem_req.ar.addr = {4'h0, mem_req_raw.ar.addr[27:0]};
    mem_req.aw.addr = {4'h0, mem_req_raw.aw.addr[27:0]};
  end

  axi4_bram_slv #(.WORDS(MEM_WORDS), .INIT_HEX(INIT_HEX)) u_mem (
    .clk, .rst_n, .axi_req(mem_req), .axi_resp(mem_resp)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)              heartbeat <= 1'b0;
    else if (|rvfi_valid)    heartbeat <= ~heartbeat;
  end

endmodule
