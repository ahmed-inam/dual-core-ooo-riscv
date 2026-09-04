// The whole machine: core, both caches, arbiter and AXI adapter.
`timescale 1ns/1ps
module tb_sys_ooo;
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coreaxi_pkg::*;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic  ireq, ignt, irvalid;
  word_t iaddr, irdata;
  logic [3:0][31:0] irdata_line;   // whole-line fill from the icache
  logic [3:0]       iwmask;
  logic  dreq, dgnt, dwe, drvalid;
  logic [3:0] dwstrb;
  word_t daddr, dwdata, drdata;
  logic  ic_flush, dc_flush, dc_flush_done;
  logic  ic_ev_access, ic_ev_miss, dc_ev_access, dc_ev_miss, dc_ev_wb;

  logic        rvfi_valid;
  logic [63:0] rvfi_order;
  word_t       rvfi_insn, rvfi_pc_rdata, rvfi_rd_wdata;
  logic        rvfi_trap;
  regaddr_t    rvfi_rd_addr;
  word_t hartid_arg;
  initial begin
    if (!$value$plusargs("HARTID=%d", hartid_arg)) hartid_arg = 32'd0;
  end

  core u_core (
    .hart_id_i(hartid_arg),
    .snoop_valid_i(1'b0), .snoop_addr_i('0),
    .lrsc_lr_valid_o(), .lrsc_sc_valid_o(), .lrsc_addr_o(),
    .lrsc_acc_valid_o(), .lrsc_sc_success_i(1'b0),
    .clk, .rst_n,
    .ireq, .ignt, .iaddr, .irvalid, .irdata,
    .irdata_line, .iwmask,
    .dreq, .dgnt, .daddr, .dwe, .dwstrb, .dwdata, .drvalid, .drdata,
    .ev_ic_miss(ic_ev_miss), .ev_dc_miss(dc_ev_miss), .ev_dc_wb(dc_ev_wb),
    .ic_flush, .dc_flush, .dc_flush_done,
    .irq_timer(1'b0), .irq_soft(1'b0), .irq_ext(1'b0),
    .rvfi_valid, .rvfi_order, .rvfi_insn, .rvfi_trap,
    .rvfi_pc_rdata, .rvfi_rd_addr, .rvfi_rd_wdata,
    .rvfi_halt(), .rvfi_intr(), .rvfi_mode(), .rvfi_ixl(),
    .rvfi_rs1_addr(), .rvfi_rs2_addr(), .rvfi_rs1_rdata(), .rvfi_rs2_rdata(),
    .rvfi_pc_wdata(),
    .rvfi_mem_addr(), .rvfi_mem_rmask(), .rvfi_mem_wmask(),
    .rvfi_mem_rdata(), .rvfi_mem_wdata(),
    .trap_taken()   // named-but-empty: this TB has no LR/SC path
  );
  logic done_seen;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) done_seen <= 1'b0;
    else if (rvfi_valid && rvfi_rd_addr == 5'd28 && rvfi_rd_wdata == 32'd1)
      done_seen <= 1'b1;
  end

  logic              il_req, il_gnt, il_rvalid;
  word_t             il_addr;
  logic [LINE_W-1:0] il_rdata;

  icache u_ic (
    .clk, .rst_n,
    .req(ireq), .gnt(ignt), .addr(iaddr), .rvalid(irvalid), .rdata(irdata),
    .rdata_line(irdata_line), .rdata_woff(), .rdata_wmask(iwmask),
    .flush(ic_flush),
    .line_req(il_req), .line_gnt(il_gnt), .line_addr(il_addr),
    .line_rvalid(il_rvalid), .line_rdata(il_rdata),
    .ev_access(ic_ev_access), .ev_miss(ic_ev_miss)
  );

  logic              dl_req, dl_gnt, dl_we, dl_rvalid;
  word_t             dl_addr;
  logic [LINE_W-1:0] dl_wdata, dl_rdata;
  logic       dm_req, dm_gnt, dm_we, dm_rvalid;
  logic [3:0] dm_wstrb;
  word_t      dm_addr, dm_wdata, dm_rdata;

  dcache u_dc (
    .clk, .rst_n,
    .snp_valid(1'b0), .snp_addr('0), .snp_type(coherence_pkg::SNP_TO_S),
    .snp_ack(), .snp_rsp(),
    .coh_req_valid(), .coh_req_type(), .coh_req_addr(),
    .coh_gnt(1'b1), .coh_done(1'b1), .coh_shared(1'b0),
    .coh_installed(),
    .req(dreq), .gnt(dgnt), .addr(daddr), .we(dwe), .wstrb(dwstrb),
    .wdata(dwdata), .rvalid(drvalid), .rdata(drdata),
    .kill(1'b0), .flush(dc_flush), .flush_done(dc_flush_done),
    .line_req(dl_req), .line_gnt(dl_gnt), .line_addr(dl_addr),
    .line_we(dl_we), .line_wdata(dl_wdata),
    .line_rvalid(dl_rvalid), .line_rdata(dl_rdata),
    .mmio_req(dm_req), .mmio_gnt(dm_gnt), .mmio_addr(dm_addr),
    .mmio_we(dm_we), .mmio_wstrb(dm_wstrb), .mmio_wdata(dm_wdata),
    .mmio_rvalid(dm_rvalid), .mmio_rdata(dm_rdata),
    .ev_access(dc_ev_access), .ev_miss(dc_ev_miss), .ev_wb(dc_ev_wb)
  );

  logic              o_req, o_gnt, o_we, o_word, o_rvalid;
  logic [3:0]        o_wstrb;
  word_t             o_addr;
  logic [LINE_W-1:0] o_wdata, o_rdata;
  logic              ev_starve_i;

  mem_arbiter u_arb (
    .clk, .rst_n,
    .d_req(dl_req), .d_gnt(dl_gnt), .d_addr(dl_addr), .d_we(dl_we),
    .d_wdata(dl_wdata), .d_rvalid(dl_rvalid), .d_rdata(dl_rdata),
    .m_req(dm_req), .m_gnt(dm_gnt), .m_addr(dm_addr), .m_we(dm_we),
    .m_wstrb(dm_wstrb), .m_wdata(dm_wdata),
    .m_rvalid(dm_rvalid), .m_rdata(dm_rdata),
    .i_req(il_req), .i_gnt(il_gnt), .i_addr(il_addr),
    .i_rvalid(il_rvalid), .i_rdata(il_rdata),
    .out_req(o_req), .out_gnt(o_gnt), .out_addr(o_addr), .out_we(o_we),
    .out_word(o_word), .out_wstrb(o_wstrb), .out_wdata(o_wdata),
    .out_rvalid(o_rvalid), .out_rdata(o_rdata),
    .ev_starve_i(ev_starve_i)
  );

  axi_req_t  axi_req;
  axi_resp_t axi_resp;

  axi_adapter u_adp (
    .clk, .rst_n,
    .req(o_req), .gnt(o_gnt), .addr(o_addr), .we(o_we), .word_mode(o_word),
    .wstrb(o_wstrb), .wdata(o_wdata), .rvalid(o_rvalid), .rdata(o_rdata),
    .axi_req, .axi_resp
  );

  word_t dbg_addr, dbg_data;
  logic  err_overlap, err_range;
  int unsigned cfg_delay, cfg_beat_delay;

  sim_mem #(.WORDS(16384)) u_mem (
    .clk, .rst_n, .cfg_delay, .cfg_beat_delay,
    .axi_req, .axi_resp, .dbg_addr, .dbg_data, .err_overlap, .err_range
  );

  int n_starve;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)          n_starve <= 0;
    else if (ev_starve_i) n_starve <= n_starve + 1;
  end

  string hexfile;
  int unsigned dly, bdly, ws_words, ws_passes;
  word_t cyc, ins, br, mis, st, fl, icm, dcm, dwb, mst, sum;

  initial begin
    dbg_addr = '0;
    if (!$value$plusargs("DELAY=%d", dly))       dly  = 10;
    if (!$value$plusargs("BEAT_DELAY=%d", bdly)) bdly = 0;
    if (!$value$plusargs("WS_PASSES=%d", ws_passes)) ws_passes = 1;
    if (!$value$plusargs("HEX=%s", hexfile))     hexfile = "asm/bench_memory.hex";
    cfg_delay      = dly;
    cfg_beat_delay = bdly;
    for (int i = 0; i < 16384; i++) u_mem.mem[i] = 32'h0000_0000;
    for (int i = 1024; i < 16384; i++) u_mem.mem[i] = 32'h9E37_79B9 + 32'(i)*32'd2654435761;
    $readmemh(hexfile, u_mem.mem);
    if ($value$plusargs("WS_WORDS=%d", ws_words)) begin
      u_mem.mem[32'h100 >> 2] = ws_words;
      u_mem.mem[32'h104 >> 2] = (ws_passes == 0) ? 32'd1 : ws_passes;
    end
    rst_n = 0; #12 rst_n = 1;

    fork
      wait (done_seen);
      begin #60_000_000; $display("SYS TIMEOUT"); $finish; end
    join_any
    disable fork;
    #200;

    dbg_addr = 32'h0000_0200; #1; cyc = dbg_data;
    dbg_addr = 32'h0000_0204; #1; ins = dbg_data;
    dbg_addr = 32'h0000_0208; #1; br  = dbg_data;
    dbg_addr = 32'h0000_020C; #1; mis = dbg_data;
    dbg_addr = 32'h0000_0210; #1; st  = dbg_data;
    dbg_addr = 32'h0000_0214; #1; fl  = dbg_data;
    dbg_addr = 32'h0000_0218; #1; icm = dbg_data;
    dbg_addr = 32'h0000_021C; #1; dcm = dbg_data;
    dbg_addr = 32'h0000_0220; #1; dwb = dbg_data;
    dbg_addr = 32'h0000_0224; #1; mst = dbg_data;
    dbg_addr = 32'h0000_0228; #1; sum = dbg_data;

    $display("SYS DELAY=%0d BEAT_DELAY=%0d | cycles=%0d instret=%0d IPC=%0d.%02d",
      dly, bdly, cyc, ins, ins/cyc, ((ins*100)/cyc)%100);
    $display("SYS   branches=%0d mispred=%0d luse_stall=%0d flush=%0d",
      br, mis, st, fl);
    $display("SYS   imiss=%0d dmiss=%0d dwb=%0d memstall=%0d istarve=%0d",
      icm, dcm, dwb, mst, n_starve);
    $display("SYS   checksum=%08h", sum);
    $finish;
  end
endmodule
