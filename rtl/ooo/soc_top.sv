// Platform level: one cluster, plus memory and the timer.
module soc_top
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;
  import coherence_pkg::*;
  import platform_cfg_pkg::*;
#(
  parameter word_t RESET_PC_P = 32'h8000_0000,
  parameter int unsigned MEM_WORDS = 65536            // 256 KB, as tb_rvfi_sys_ooo
) (
  input  logic clk,
  input  logic rst_n,

  input  int unsigned cfg_delay,
  input  int unsigned cfg_beat_delay,

  input  logic rtc_tick,

  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_valid,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][63:0] rvfi_order,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_insn,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_pc_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rd_wdata,
  output regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rd_addr,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_trap,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_halt,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_intr,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][1:0]  rvfi_mode,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][1:0]  rvfi_ixl,
  output regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs1_addr,
  output regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs2_addr,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs1_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs2_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_pc_wdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_addr,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][3:0]  rvfi_mem_rmask,
  output logic     [NUM_HARTS-1:0][COMMIT_W-1:0][3:0]  rvfi_mem_wmask,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_rdata,
  output word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_wdata,

  output logic  [NUM_HARTS-1:0] dreq_o,
  output logic  [NUM_HARTS-1:0] dwe_o,
  output word_t [NUM_HARTS-1:0] daddr_o,
  output word_t [NUM_HARTS-1:0] dwdata_o,

  output logic [NUM_HARTS-1:0] msip_o,
  output logic [NUM_HARTS-1:0] mtip_o,

  input  word_t dbg_addr,
  output word_t dbg_data,
  output logic  err_overlap,
  output logic  err_range,
  output logic [NUM_HARTS-1:0] ev_starve_i
);

  axi4_if #(.ID_W(axi4_pkg::M_ID_W)) s0_if (.aclk(clk), .arst_n(rst_n));
  axi4_if #(.ID_W(axi4_pkg::M_ID_W)) s1_if (.aclk(clk), .arst_n(rst_n));

  cluster #(.RESET_PC_P(RESET_PC_P)) u_cluster (
    .clk, .rst_n,
    .s0_if(s0_if.mst), .s1_if(s1_if.mst),
    .msip_i(msip_o),
    .mtip_i(mtip_o),
    .rvfi_valid, .rvfi_order, .rvfi_insn, .rvfi_pc_rdata,
    .rvfi_halt, .rvfi_intr, .rvfi_mode, .rvfi_ixl,
    .rvfi_rs1_addr, .rvfi_rs2_addr, .rvfi_rs1_rdata, .rvfi_rs2_rdata,
    .rvfi_pc_wdata,
    .rvfi_mem_addr, .rvfi_mem_rmask, .rvfi_mem_wmask,
    .rvfi_mem_rdata, .rvfi_mem_wdata,
    .rvfi_rd_wdata, .rvfi_rd_addr, .rvfi_trap,
    .dreq_o, .dwe_o, .daddr_o, .dwdata_o,
    .ev_starve_i
  );

  logic  cl_req, cl_gnt, cl_we, cl_rvalid;
  word_t cl_addr, cl_wdata, cl_rdata;
  logic [3:0] cl_wstrb;

  axi4_word_slv u_s0 (
    .clk, .rst_n, .sif(s0_if.slv),
    .req(cl_req), .gnt(cl_gnt), .addr(cl_addr), .we(cl_we),
    .wstrb(cl_wstrb), .wdata(cl_wdata), .rvalid(cl_rvalid), .rdata(cl_rdata)
  );

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

  sim_mem #(.WORDS(MEM_WORDS)) u_mem (
    .clk, .rst_n, .cfg_delay, .cfg_beat_delay,
    .axi_req(mem_req), .axi_resp(mem_resp), .dbg_addr, .dbg_data,
    .err_overlap, .err_range
  );

endmodule
