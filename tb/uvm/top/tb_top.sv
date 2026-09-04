// Static top: clock, reset, interfaces, the cluster, and run_test.
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import rv32i_pkg::*;
  import platform_cfg_pkg::*;   // NUM_HARTS
  import core_cfg_pkg::*;       // COMMIT_W
  import axi4_pkg::*;           // M_ID_W
  import cpu_tb_pkg::*;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  localparam time CLK_PERIOD = 10ns;
  always #(CLK_PERIOD/2) clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (10) @(negedge clk);
    rst_n = 1'b1;
  end

  longint unsigned cycle_count;
  always_ff @(posedge clk) begin
    if (!rst_n) cycle_count <= '0;
    else        cycle_count <= cycle_count + 1;
  end

  logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_valid;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0][63:0] rvfi_order;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_insn;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_pc_rdata;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rd_wdata;
  regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rd_addr;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_trap;

  logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_halt;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_intr;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0][1:0]  rvfi_mode;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0][1:0]  rvfi_ixl;
  regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs1_addr;
  regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs2_addr;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs1_rdata;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rs2_rdata;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_pc_wdata;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_addr;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0][3:0]  rvfi_mem_rmask;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0][3:0]  rvfi_mem_wmask;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_rdata;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_mem_wdata;

  logic  [NUM_HARTS-1:0] dreq_o, dwe_o, ev_starve;
  word_t [NUM_HARTS-1:0] daddr_o, dwdata_o;

  axi4_if #(.ID_W(M_ID_W)) s0_vif (.aclk(clk), .arst_n(rst_n));  // CLINT
  axi4_if #(.ID_W(M_ID_W)) s1_vif (.aclk(clk), .arst_n(rst_n));  // memory

  irq_if u_irq_vif (.clk(clk), .rst_n(rst_n));

  sys_if u_sys_vif (
    .clk(clk), .rst_n(rst_n),
    .dreq(dreq_o), .dwe(dwe_o), .daddr(daddr_o), .dwdata(dwdata_o),
    .ev_starve(ev_starve)
  );

  cluster u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .s0_if         (s0_vif.mst),
    .s1_if         (s1_vif.mst),
    .msip_i        (u_irq_vif.msip),
    .mtip_i        (u_irq_vif.mtip),
    .rvfi_valid    (rvfi_valid),
    .rvfi_order    (rvfi_order),
    .rvfi_insn     (rvfi_insn),
    .rvfi_pc_rdata (rvfi_pc_rdata),
    .rvfi_rd_wdata (rvfi_rd_wdata),
    .rvfi_rd_addr  (rvfi_rd_addr),
    .rvfi_trap     (rvfi_trap),
    .rvfi_halt     (rvfi_halt),
    .rvfi_intr     (rvfi_intr),
    .rvfi_mode     (rvfi_mode),
    .rvfi_ixl      (rvfi_ixl),
    .rvfi_rs1_addr (rvfi_rs1_addr),
    .rvfi_rs2_addr (rvfi_rs2_addr),
    .rvfi_rs1_rdata(rvfi_rs1_rdata),
    .rvfi_rs2_rdata(rvfi_rs2_rdata),
    .rvfi_pc_wdata (rvfi_pc_wdata),
    .rvfi_mem_addr (rvfi_mem_addr),
    .rvfi_mem_rmask(rvfi_mem_rmask),
    .rvfi_mem_wmask(rvfi_mem_wmask),
    .rvfi_mem_rdata(rvfi_mem_rdata),
    .rvfi_mem_wdata(rvfi_mem_wdata),
    .dreq_o        (dreq_o),
    .dwe_o         (dwe_o),
    .daddr_o       (daddr_o),
    .dwdata_o      (dwdata_o),
    .ev_starve_i   (ev_starve)
  );

  int n_rvfi_published = 0;

  generate
    for (genvar h = 0; h < NUM_HARTS; h++) begin : g_rvfi
      rvfi_if u_rvfi_vif (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid    (rvfi_valid[h]),
        .order    (rvfi_order[h]),
        .insn     (rvfi_insn[h]),
        .pc_rdata (rvfi_pc_rdata[h]),
        .rd_wdata (rvfi_rd_wdata[h]),
        .rd_addr  (rvfi_rd_addr[h]),
        .trap     (rvfi_trap[h]),
        .halt     (rvfi_halt[h]),
        .intr     (rvfi_intr[h]),
        .mode     (rvfi_mode[h]),
        .ixl      (rvfi_ixl[h]),
        .rs1_addr (rvfi_rs1_addr[h]),
        .rs2_addr (rvfi_rs2_addr[h]),
        .rs1_rdata(rvfi_rs1_rdata[h]),
        .rs2_rdata(rvfi_rs2_rdata[h]),
        .pc_wdata (rvfi_pc_wdata[h]),
        .mem_addr (rvfi_mem_addr[h]),
        .mem_rmask(rvfi_mem_rmask[h]),
        .mem_wmask(rvfi_mem_wmask[h]),
        .mem_rdata(rvfi_mem_rdata[h]),
        .mem_wdata(rvfi_mem_wdata[h])
      );

      initial begin
        uvm_config_db #(virtual rvfi_if)::set(
          null, "*", $sformatf("rvfi_vif_%0d", h), u_rvfi_vif);
        n_rvfi_published++;
      end
    end
  endgenerate

  bind cluster snoop_if u_snoop_vif (
    .clk           (clk),
    .rst_n         (rst_n),
    .req_valid     (coh_req_valid),
    .req_type      (coh_req_type),
    .req_addr      (coh_req_addr),
    .req_gnt       (coh_req_gnt),
    .req_atomic    (coh_req_atomic),
    .snp_valid     (coh_snp_valid),
    .snp_addr      (coh_snp_addr),
    .snp_type      (coh_snp_type),
    .snp_ack       (coh_snp_ack),
    .snp_rsp       (coh_snp_rsp),
    .cmp_valid     (coh_cmp_valid),
    .cmp_shared    (coh_cmp_shared),
    .cmp_dirty     (coh_cmp_dirty),
    .installed     (coh_installed),
    .prot_deferred (coh_prot_deferred),
    .ord_violation (coh_ord_violation),
    .lr_valid      (lr_v),
    .sc_valid      (sc_v),
    .sc_success    (sc_ok),
    .rsv_valid     (rsv_valid),
    .backing_off   (backing_off),
    .snoop_clear   (snp_clr),
    .trap_clear    (trp_clr),
    .acc_addr      (lrsc_acc_addr),
    .prot_addr     (prot_addr)
  );

  bind dcache cache_probe_if u_cache_probe (
    .clk   (clk),
    .rst_n (rst_n),
    .tag   (tag_q),
    .wi    (mshr_wi_q),
    .we    (mshr_we_q)
  );

  bind core core_probe_if u_core_probe (
    .clk           (clk),
    .rst_n         (rst_n),
    .rob_count     (rob_count),
    .sq_cnt        (u_lsq.sq_cnt),
    .lq_cnt        (u_lsq.lq_cnt),
    .recovery_idle (recovery_idle),
    .mispredict_ex (mispredict_ex),
    .trig_viol     (trig_viol),
    .rq_state      (rq_q),
    .r_is_bpr_q    (r_is_bpr_q),
    .r_is_viol_q   (r_is_viol_q),
    .r_is_irq_q    (r_is_irq_q),
    .r_is_exc_q    (r_is_exc_q),
    .r_is_mret_q   (r_is_mret_q),
    .r_is_fence_q  (r_is_fence_q),
    .r_is_fencei_q (r_is_fencei_q),
    .trap_cause    (r_cause_q),
    .mstatus       (mstatus_o),
    .bp_mispredict (bp_update.mispredict),
    .bp_cf_type    (bp_update.cf_type),
    .bp_call       (bp_update.call),
    .bp_ret        (bp_update.ret),
    .rob_head_id   (rob_head_id),
    .rob_viol      (u_rob.viol_q),
    .snap_cnt      (snap_cnt),
    .trap_taken    (trap_taken)
  );

  bind core csr_probe_if u_csr_probe (
    .clk      (clk),
    .rst_n    (rst_n),
    .mstatus  (u_csr.mstatus_q),
    .mie      (u_csr.mie_q),
    .mtvec    (u_csr.mtvec_q),
    .mscratch (u_csr.mscratch_q),
    .mepc     (u_csr.mepc_q),
    .mcause   (u_csr.mcause_q),
    .mtval    (u_csr.mtval_q),
    .mip      (u_csr.mip_val)
  );

  int n_probe_published = 0;
  generate
    for (genvar h = 0; h < NUM_HARTS; h++) begin : g_probe
      initial begin
        uvm_config_db #(virtual cache_probe_if)::set(
          null, "*", $sformatf("cache_probe_vif_%0d", h),
          u_dut.g_hart[h].u_dc.u_cache_probe);
        uvm_config_db #(virtual core_probe_if)::set(
          null, "*", $sformatf("core_probe_vif_%0d", h),
          u_dut.g_hart[h].u_core.u_core_probe);
        uvm_config_db #(virtual csr_probe_if)::set(
          null, "*", $sformatf("csr_probe_vif_%0d", h),
          u_dut.g_hart[h].u_core.u_csr_probe);
        n_probe_published++;
      end
    end
  endgenerate

  initial begin
    uvm_config_db #(virtual axi4_if #(.ID_W(M_ID_W)))::set(null, "*", "s0_vif", s0_vif);
    uvm_config_db #(virtual axi4_if #(.ID_W(M_ID_W)))::set(null, "*", "s1_vif", s1_vif);
    uvm_config_db #(virtual irq_if)  ::set(null, "*", "irq_vif",   u_irq_vif);
    uvm_config_db #(virtual sys_if)  ::set(null, "*", "sys_vif",   u_sys_vif);
    uvm_config_db #(virtual snoop_if)::set(null, "*", "snoop_vif", u_dut.u_snoop_vif);

    uvm_config_db #(int)::set(null, "*", "clk_period_ns", int'(CLK_PERIOD/1ns));

    wait (n_rvfi_published  == NUM_HARTS);
    wait (n_probe_published == NUM_HARTS);

    run_test();
  end

  longint unsigned timeout_cycles;
  initial begin
    if (!$value$plusargs("TIMEOUT=%d", timeout_cycles)) timeout_cycles = 2_000_000;
    wait (rst_n === 1'b1);
    while (cycle_count < timeout_cycles) @(posedge clk);
    $fatal(1, "tb_top: TIMEOUT after %0d cycles -- no tohost store observed", timeout_cycles);
  end

  initial begin
    if ($test$plusargs("TRACE")) begin
      $dumpfile("tb_top.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule
