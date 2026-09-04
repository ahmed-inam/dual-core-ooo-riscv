// Dual-core cluster gate: two harts, coherence, and the shared bus.
module tb_dual_ooo
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
  import mem_pkg::*;
  import platform_cfg_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int unsigned cfg_delay, cfg_beat_delay;
  word_t       dbg_addr = '0, dbg_data;
  logic        err_overlap, err_range;

  logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_valid;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0][63:0] rvfi_order;
  word_t    [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_insn, rvfi_pc_rdata, rvfi_rd_wdata;
  regaddr_t [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_rd_addr;
  logic     [NUM_HARTS-1:0][COMMIT_W-1:0]       rvfi_trap;

  logic  [NUM_HARTS-1:0] dreq_o, dwe_o, msip_o, mtip_o, ev_starve_i;

  int n_lr [NUM_HARTS], n_sc [NUM_HARTS], n_scok [NUM_HARTS];
  logic [31:0] f_rsvline, f_accaddr; logic f_rsv, f_seen;
  int n_snpclr [NUM_HARTS], n_both_live;
  int n_sc_nowrite [NUM_HARTS];
  int sc_log_n;
  int n_snwait, n_mainout, n_fill, n_hazard;
  int fill_log_n;
  int scst_n;
  int n_cstore0, n_cstore1, cstore_log_n;
  int n_swmr_viol;   // cluster-level SWMR violations observed
  logic swmr_quiet;
  line_state_t prev_st [2][mem_pkg::SETS][mem_pkg::WAYS];
  int          n_611;
  int          n_611b;
  int life_n; logic life_arm;
  wire [$clog2(mem_pkg::SETS)-1:0] sc_set0 =
       (u_cl.u_cluster.u_lrsc.acc_addr[0] >> mem_pkg::OFF_W);
  wire [$clog2(mem_pkg::SETS)-1:0] sc_set1 =
       (u_cl.u_cluster.u_lrsc.acc_addr[1] >> mem_pkg::OFF_W);
  wire sc_writable0 =
       (u_cl.u_cluster.g_hart[0].u_dc.tag_q[sc_set0][0].state == LINE_E) ||
       (u_cl.u_cluster.g_hart[0].u_dc.tag_q[sc_set0][0].state == LINE_M) ||
       (u_cl.u_cluster.g_hart[0].u_dc.tag_q[sc_set0][1].state == LINE_E) ||
       (u_cl.u_cluster.g_hart[0].u_dc.tag_q[sc_set0][1].state == LINE_M);
  wire sc_writable1 =
       (u_cl.u_cluster.g_hart[1].u_dc.tag_q[sc_set1][0].state == LINE_E) ||
       (u_cl.u_cluster.g_hart[1].u_dc.tag_q[sc_set1][0].state == LINE_M) ||
       (u_cl.u_cluster.g_hart[1].u_dc.tag_q[sc_set1][1].state == LINE_E) ||
       (u_cl.u_cluster.g_hart[1].u_dc.tag_q[sc_set1][1].state == LINE_M);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int k = 0; k < NUM_HARTS; k++) begin
        n_lr[k] <= 0; n_sc[k] <= 0; n_scok[k] <= 0; n_snpclr[k] <= 0;
        n_sc_nowrite[k] <= 0;
      end
      n_both_live <= 0; sc_log_n <= 0; n_snwait <= 0; n_mainout <= 0; n_fill <= 0;
      n_hazard <= 0; fill_log_n <= 0; scst_n <= 0; life_n <= 0; life_arm <= 1'b0;
      n_cstore0 <= 0; n_cstore1 <= 0; cstore_log_n <= 0;
      n_swmr_viol <= 0;
      n_611 <= 0; n_611b <= 0;
    end else for (int k = 0; k < NUM_HARTS; k++) begin
      if (u_cl.u_cluster.u_lrsc.lr_valid[k])   n_lr[k]   <= n_lr[k] + 1;
      if (u_cl.u_cluster.u_lrsc.sc_valid[k])   n_sc[k]   <= n_sc[k] + 1;
      if (u_cl.u_cluster.u_lrsc.sc_success[k]) n_scok[k] <= n_scok[k] + 1;
      if (u_cl.u_cluster.snp_clr[k])           n_snpclr[k] <= n_snpclr[k] + 1;
    end
    if (u_cl.u_cluster.u_lrsc.sc_success[0] && !sc_writable0) n_sc_nowrite[0] <= n_sc_nowrite[0] + 1;
    if (u_cl.u_cluster.u_lrsc.sc_success[1] && !sc_writable1) n_sc_nowrite[1] <= n_sc_nowrite[1] + 1;
    if ((u_cl.u_cluster.u_lrsc.sc_success[0] || u_cl.u_cluster.u_lrsc.sc_success[1]) && (sc_log_n < 0)) begin
      sc_log_n <= sc_log_n + 1;
      $display("SCLOG %0d cyc=%0d hart=%0d mem_counter=%0d rsv0=%b rsv1=%b line0=%h line1=%h",
               sc_log_n, cyc, u_cl.u_cluster.u_lrsc.sc_success[1],
               u_cl.u_mem.mem[16'hC50],
               u_cl.u_cluster.u_lrsc.rsv_valid[0], u_cl.u_cluster.u_lrsc.rsv_valid[1],
               u_cl.u_cluster.u_lrsc.rsv_line_q[0], u_cl.u_cluster.u_lrsc.rsv_line_q[1]);
    end
    if (u_cl.u_cluster.g_hart[1].u_dc.snstate_q == u_cl.u_cluster.g_hart[1].u_dc.SN_WAIT) n_snwait <= n_snwait + 1;
    if ((u_cl.u_cluster.g_hart[1].u_dc.dstate_q == u_cl.u_cluster.g_hart[1].u_dc.D_FILL_WAIT)
     || (u_cl.u_cluster.g_hart[1].u_dc.dstate_q == u_cl.u_cluster.g_hart[1].u_dc.D_WB_WAIT)) n_mainout <= n_mainout + 1;
    if (u_cl.u_cluster.g_hart[1].u_dc.dstate_q == u_cl.u_cluster.g_hart[1].u_dc.D_FILL) n_fill <= n_fill + 1;
    if ((u_cl.u_cluster.g_hart[1].u_dc.snstate_q == u_cl.u_cluster.g_hart[1].u_dc.SN_WAIT)
        && ((u_cl.u_cluster.g_hart[1].u_dc.dstate_q == u_cl.u_cluster.g_hart[1].u_dc.D_FILL_WAIT)
         || (u_cl.u_cluster.g_hart[1].u_dc.dstate_q == u_cl.u_cluster.g_hart[1].u_dc.D_WB_WAIT)))
      n_hazard <= n_hazard + 1;
    if (u_cl.u_cluster.u_lrsc.sc_success[1] && !life_arm && (scst_n >= 3)) life_arm <= 1'b1;
    if (life_arm && (life_n < 30)) begin
    end
    if (u_cl.u_cluster.g_hart[1].u_dc.gnt && u_cl.u_cluster.g_hart[1].u_dc.we
        && (u_cl.u_cluster.g_hart[1].u_dc.addr[17:4] == 14'h0314) && (scst_n < 20))
      $display("SCGNT h1 cyc=%0d h1tag=%s upg=%b snpblk=%b",
               cyc, u_cl.u_cluster.g_hart[1].u_dc.tag_q[20][0].state.name(),
               u_cl.u_cluster.g_hart[1].u_dc.upg_needed, u_cl.u_cluster.g_hart[1].u_dc.snp_block);
    if (u_cl.u_cluster.u_lrsc.sc_success[1] && (scst_n < 20)) begin
      scst_n <= scst_n + 1;
      $display("SCST h1 cyc=%0d h1tag=%s h0tag=%s mem=%0d",
               cyc,
               u_cl.u_cluster.g_hart[1].u_dc.tag_q[20][0].state.name(),
               u_cl.u_cluster.g_hart[0].u_dc.tag_q[20][0].state.name(),
               u_cl.u_mem.mem[16'hC50]);
    end
    if (u_cl.u_cluster.g_hart[0].u_dc.gnt && u_cl.u_cluster.g_hart[0].u_dc.we
        && (u_cl.u_cluster.g_hart[0].u_dc.addr[17:4] == 14'h0314)) n_cstore0 <= n_cstore0 + 1;
    if (u_cl.u_cluster.g_hart[1].u_dc.gnt && u_cl.u_cluster.g_hart[1].u_dc.we
        && (u_cl.u_cluster.g_hart[1].u_dc.addr[17:4] == 14'h0314)) n_cstore1 <= n_cstore1 + 1;
    if (u_cl.u_cluster.g_hart[0].u_dc.gnt && u_cl.u_cluster.g_hart[0].u_dc.we
        && (u_cl.u_cluster.g_hart[0].u_dc.addr[17:4] == 14'h0314) && (cstore_log_n < 40)) begin
      cstore_log_n <= cstore_log_n + 1;
      $display("CSTORE h0 cyc=%0d strb=%b wdata=%0d scok=%b scv=%b held=%b lat=%b tag=%s",
               cyc, u_cl.u_cluster.g_hart[0].u_dc.wstrb, u_cl.u_cluster.g_hart[0].u_dc.wdata,
               u_cl.u_cluster.u_lrsc.sc_success[0],
               u_cl.u_cluster.g_hart[0].u_core.u_lsq.lrsc_sc_valid,
               u_cl.u_cluster.g_hart[0].u_core.u_lsq.sc_held_q,
               u_cl.u_cluster.g_hart[0].u_core.u_lsq.sc_lat_q,
               u_cl.u_cluster.g_hart[0].u_dc.tag_q[20][0].state.name());
    end
    if ((n_611b < 24) && (cyc > 400) && (cyc < 560)) begin
      if (u_cl.u_cluster.g_hart[0].u_dc.snp_valid) begin
        n_611b <= n_611b + 1;
        $display("SNP0 cyc=%0d snpaddr=%h snhit=%b sndirty=%b sn_ns=%s rsp=%s | tag24w0=%s tag24w1=%s snstate=%0d",
          cyc, u_cl.u_cluster.g_hart[0].u_dc.snp_addr,
          u_cl.u_cluster.g_hart[0].u_dc.sn_hit, u_cl.u_cluster.g_hart[0].u_dc.sn_dirty_hit,
          u_cl.u_cluster.g_hart[0].u_dc.sn_ns.name(), u_cl.u_cluster.g_hart[0].u_dc.snp_rsp.name(),
          u_cl.u_cluster.g_hart[0].u_dc.tag_q[24][0].state.name(),
          u_cl.u_cluster.g_hart[0].u_dc.tag_q[24][1].state.name(),
          u_cl.u_cluster.g_hart[0].u_dc.snstate_q);
      end
      if ((u_cl.u_cluster.g_hart[0].u_dc.tag_q[24][0].state != prev_st[0][24][0])
       || (u_cl.u_cluster.g_hart[0].u_dc.tag_q[24][1].state != prev_st[0][24][1])) begin
        n_611b <= n_611b + 1;
        $display("TAG0 cyc=%0d set24 w0 %s->%s  w1 %s->%s | dst0=%0d gnt=%b we=%b s0hit=%b",
          cyc, prev_st[0][24][0].name(), u_cl.u_cluster.g_hart[0].u_dc.tag_q[24][0].state.name(),
          prev_st[0][24][1].name(), u_cl.u_cluster.g_hart[0].u_dc.tag_q[24][1].state.name(),
          u_cl.u_cluster.g_hart[0].u_dc.dstate_q, u_cl.u_cluster.g_hart[0].u_dc.gnt,
          u_cl.u_cluster.g_hart[0].u_dc.we, u_cl.u_cluster.g_hart[0].u_dc.s0_hit);
      end
    end
    for (int st = 0; st < mem_pkg::SETS; st++) begin
      for (int w = 0; w < mem_pkg::WAYS; w++) begin
        for (int pw = 0; pw < mem_pkg::WAYS; pw++) begin
          if ((u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w].state != prev_st[0][st][w])
              && mem_pkg::is_valid(u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w].state)
              && mem_pkg::is_valid(u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][pw].state)
              && !((u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w].state == LINE_S)
                && (u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][pw].state == LINE_S))
              && (u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][pw].tag
                  == u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w].tag)
              && (n_611 < 8)) begin
            n_611 <= n_611 + 1;
            $display("E611 cyc=%0d h0 %s->%s set=%0d tag=%h | peer_h1=%s | dst0=%0d sn0=%0d acqshr0=%b | coh st=%s own=%b rq=%s shr=%b ad=%h",
              cyc, prev_st[0][st][w].name(),
              u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w].state.name(), st,
              u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w].tag,
              u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][pw].state.name(),
              u_cl.u_cluster.g_hart[0].u_dc.dstate_q, u_cl.u_cluster.g_hart[0].u_dc.snstate_q,
              u_cl.u_cluster.g_hart[0].u_dc.acq_shared_q,
              u_cl.u_cluster.u_coh.st_q.name(), u_cl.u_cluster.u_coh.own_q, u_cl.u_cluster.u_coh.rq_q.name(),
              u_cl.u_cluster.u_coh.shr_q, u_cl.u_cluster.u_coh.ad_q);
          end
          if ((u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w].state != prev_st[1][st][w])
              && mem_pkg::is_valid(u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w].state)
              && mem_pkg::is_valid(u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][pw].state)
              && !((u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w].state == LINE_S)
                && (u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][pw].state == LINE_S))
              && (u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][pw].tag
                  == u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w].tag)
              && (n_611 < 8)) begin
            n_611 <= n_611 + 1;
            $display("E611 cyc=%0d h1 %s->%s set=%0d tag=%h | peer_h0=%s | dst1=%0d sn1=%0d acqshr1=%b | coh st=%s own=%b rq=%s shr=%b ad=%h",
              cyc, prev_st[1][st][w].name(),
              u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w].state.name(), st,
              u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w].tag,
              u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][pw].state.name(),
              u_cl.u_cluster.g_hart[1].u_dc.dstate_q, u_cl.u_cluster.g_hart[1].u_dc.snstate_q,
              u_cl.u_cluster.g_hart[1].u_dc.acq_shared_q,
              u_cl.u_cluster.u_coh.st_q.name(), u_cl.u_cluster.u_coh.own_q, u_cl.u_cluster.u_coh.rq_q.name(),
              u_cl.u_cluster.u_coh.shr_q, u_cl.u_cluster.u_coh.ad_q);
          end
        end
      end
    end
    for (int st = 0; st < mem_pkg::SETS; st++)
      for (int w = 0; w < mem_pkg::WAYS; w++) begin
        prev_st[0][st][w] <= u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w].state;
        prev_st[1][st][w] <= u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w].state;
      end

    swmr_quiet = (u_cl.u_cluster.u_coh.st_q == u_cl.u_cluster.u_coh.O_IDLE)
              && (u_cl.u_cluster.g_hart[0].u_dc.dstate_q  == u_cl.u_cluster.g_hart[0].u_dc.D_IDLE)
              && (u_cl.u_cluster.g_hart[1].u_dc.dstate_q  == u_cl.u_cluster.g_hart[1].u_dc.D_IDLE)
              && (u_cl.u_cluster.g_hart[0].u_dc.snstate_q == u_cl.u_cluster.g_hart[0].u_dc.SN_IDLE)
              && (u_cl.u_cluster.g_hart[1].u_dc.snstate_q == u_cl.u_cluster.g_hart[1].u_dc.SN_IDLE);
    if (swmr_quiet)
    for (int st = 0; st < mem_pkg::SETS; st++) begin
      for (int w0 = 0; w0 < mem_pkg::WAYS; w0++) begin
        for (int w1 = 0; w1 < mem_pkg::WAYS; w1++) begin
          if (mem_pkg::is_valid(u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w0].state)
           && mem_pkg::is_valid(u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w1].state)
           && (u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w0].tag
               == u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w1].tag)) begin
            if ((u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w0].state != LINE_S)
             || (u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w1].state != LINE_S)) begin
              n_swmr_viol <= n_swmr_viol + 1;
              if (n_swmr_viol < 12)
                $display("SWMR-VIOLATION cyc=%0d set=%0d tag=%h h0=%s h1=%s",
                         cyc, st, u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w0].tag,
                         u_cl.u_cluster.g_hart[0].u_dc.tag_q[st][w0].state.name(),
                         u_cl.u_cluster.g_hart[1].u_dc.tag_q[st][w1].state.name());
            end
          end
        end
      end
    end
    if ((u_cl.u_cluster.g_hart[1].u_dc.dstate_q == u_cl.u_cluster.g_hart[1].u_dc.D_FILL)
        && (fill_log_n < 24)
        && (u_cl.u_cluster.g_hart[1].u_dc.mshr_addr_q[31:4] == 28'h0000314)) begin
      fill_log_n <= fill_log_n + 1;
      $display("FILL h1 cyc=%0d data_w0=%0d shared=%b | mem=%0d | h0tag=%s",
               cyc, u_cl.u_cluster.g_hart[1].u_dc.line_rdata[31:0],
               u_cl.u_cluster.g_hart[1].u_dc.acq_shared_q,
               u_cl.u_mem.mem[16'hC50],
               u_cl.u_cluster.g_hart[0].u_dc.tag_q[20][0].state.name());
    end
    if (u_cl.u_cluster.u_lrsc.rsv_valid[0] && u_cl.u_cluster.u_lrsc.rsv_valid[1]
        && (u_cl.u_cluster.u_lrsc.rsv_line_q[0] == u_cl.u_cluster.u_lrsc.rsv_line_q[1]))
      n_both_live <= n_both_live + 1;
    if (!f_seen && u_cl.u_cluster.u_lrsc.sc_valid[1] && !u_cl.u_cluster.u_lrsc.sc_success[1]) begin
      f_seen    <= 1'b1;
      f_rsvline <= {u_cl.u_cluster.u_lrsc.rsv_line_q[1], {mem_pkg::OFF_W{1'b0}}};
      f_accaddr <= u_cl.u_cluster.u_lrsc.acc_addr[1];
      f_rsv     <= u_cl.u_cluster.u_lrsc.rsv_valid[1];
    end
  end

  int n_starve_i [NUM_HARTS];
  int n_starve_d [NUM_HARTS];
  int n_cyc_busy_m0, n_cyc_busy_m1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int k = 0; k < NUM_HARTS; k++) begin
        n_starve_i[k] <= 0; n_starve_d[k] <= 0;
      end
      n_cyc_busy_m0 <= 0; n_cyc_busy_m1 <= 0;
    end else begin
      for (int k = 0; k < NUM_HARTS; k++) begin
        if (ev_starve_i[k])            n_starve_i[k] <= n_starve_i[k] + 1;
        if (u_cl.u_cluster.ev_starve_d[k])       n_starve_d[k] <= n_starve_d[k] + 1;
      end
      if (u_cl.u_cluster.u_md.busy_q) n_cyc_busy_m0 <= n_cyc_busy_m0 + 1;
      if (u_cl.u_cluster.u_mi.busy_q) n_cyc_busy_m1 <= n_cyc_busy_m1 + 1;
    end
  end
  word_t [NUM_HARTS-1:0] daddr_o, dwdata_o;

  localparam int unsigned RTC_DIV = 32;
  int unsigned rtc_cnt;
  logic        rtc_tick;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin rtc_cnt <= 0; rtc_tick <= 1'b0; end
    else begin
      rtc_tick <= (rtc_cnt == RTC_DIV-1);
      rtc_cnt  <= (rtc_cnt == RTC_DIV-1) ? 0 : rtc_cnt + 1;
    end
  end

  soc_top #(.RESET_PC_P(32'h8000_0000), .MEM_WORDS(65536)) u_cl (
    .clk, .rst_n, .cfg_delay, .cfg_beat_delay, .rtc_tick,
    .rvfi_valid, .rvfi_order, .rvfi_insn, .rvfi_pc_rdata, .rvfi_rd_wdata,
    .rvfi_rd_addr, .rvfi_trap,
    .dreq_o, .dwe_o, .daddr_o, .dwdata_o,
    .msip_o, .mtip_o,
    .dbg_addr, .dbg_data, .err_overlap, .err_range, .ev_starve_i
  );

  word_t trunc_pc;
  logic [NUM_HARTS-1:0] hit_barrier;

  always_ff @(posedge clk) begin
    if (rst_n) begin
      for (int h = 0; h < NUM_HARTS; h++) begin
        for (int i = 0; i < COMMIT_W; i++) begin
          if (rvfi_valid[h][i]) begin
            if (trunc_pc != 0 && rvfi_pc_rdata[h][i] == trunc_pc)
              hit_barrier[h] <= 1'b1;
            if (!hit_barrier[h] &&
                !(trunc_pc != 0 && rvfi_pc_rdata[h][i] == trunc_pc))
              $display("H %0d %0d %h %h %0d %h", h,
                       rvfi_order[h][i], rvfi_pc_rdata[h][i], rvfi_insn[h][i],
                       rvfi_rd_addr[h][i], rvfi_rd_wdata[h][i]);
          end
          if (rvfi_trap[h][i])
            $display("X %0d trap pc=%h", h, rvfi_pc_rdata[h][i]);
        end
      end
    end
  end

  int unsigned ins_h [NUM_HARTS];
  int unsigned cyc;
  int n_req0, n_req1, n_snp, n_ack, n_snphit0, n_snphit1, n_shared;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin n_req0<=0; n_req1<=0; n_snp<=0; n_ack<=0; n_snphit0<=0; n_snphit1<=0; n_shared<=0; end
    else begin
      if (u_cl.u_cluster.coh_req_valid[0] && u_cl.u_cluster.coh_req_gnt[0]) n_req0<=n_req0+1;
      if (u_cl.u_cluster.coh_req_valid[1] && u_cl.u_cluster.coh_req_gnt[1]) n_req1<=n_req1+1;
      if (|u_cl.u_cluster.coh_snp_valid) n_snp<=n_snp+1;
      if (|u_cl.u_cluster.coh_snp_ack)   n_ack<=n_ack+1;
      if (u_cl.u_cluster.coh_snp_valid[0] && u_cl.u_cluster.g_hart[0].u_dc.sn_hit) n_snphit0<=n_snphit0+1;
      if (u_cl.u_cluster.coh_snp_valid[1] && u_cl.u_cluster.g_hart[1].u_dc.sn_hit) n_snphit1<=n_snphit1+1;
      if (|u_cl.u_cluster.coh_cmp_valid && u_cl.u_cluster.coh_cmp_shared) n_shared<=n_shared+1;
    end
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cyc <= 0;
      for (int h = 0; h < NUM_HARTS; h++) ins_h[h] <= 0;
    end else begin
      cyc <= cyc + 1;
      for (int h = 0; h < NUM_HARTS; h++)
        ins_h[h] <= ins_h[h] + $countones(rvfi_valid[h]);
    end
  end

  word_t tohost_addr;
  logic  done;

  always_ff @(posedge clk) begin
    if (rst_n && !done) begin
      for (int h = 0; h < NUM_HARTS; h++) begin
        if (dreq_o[h] && dwe_o[h] && daddr_o[h] == tohost_addr && dwdata_o[h] != 0) begin
          done <= 1'b1;
          if (h != 0)
            $display("DUAL FAIL: hart %0d wrote tohost -- only hart 0 may report", h);
          else if (dwdata_o[h] == 32'd1)
            $display("DUAL DONE PASS");
          else
            $display("DUAL DONE FAIL: testnum %0d", dwdata_o[h] >> 1);

          for (int k = 0; k < NUM_HARTS; k++)
            $display("HART %0d retired %0d", k, ins_h[k]);
          $display("LITMUS raw h0: x5=%0d x8=%0d | h1: x5=%0d x8=%0d  (x8: 0=SC SUCCESS)",
                   u_cl.u_mem.mem[16'hCA0], u_cl.u_mem.mem[16'hCA1],
                   u_cl.u_mem.mem[16'hCB0], u_cl.u_mem.mem[16'hCB1]);
          $display("LITMUS mem x@0x3100=%0d y@0x3140=%0d",
                   u_cl.u_mem.mem[16'hC40], u_cl.u_mem.mem[16'hC50]);
          $display("LITMUS obs h0=%0d h1=%0d",
                   u_cl.u_mem.mem[16'hC20], u_cl.u_mem.mem[16'hC30]);
          $display("STRESS counter=%0d  SC-OK h0=%0d h1=%0d  (expect counter == ITERS*NUM_HARTS)",
                   u_cl.u_mem.mem[16'hC50], n_scok[0], n_scok[1]);
      $display("CSTORES to counter line: h0=%0d h1=%0d  total=%0d  (MUST equal SC-OK sum)",
               n_cstore0, n_cstore1, n_cstore0+n_cstore1);
      $display("SWMR-VIOLATIONS cluster-wide: %0d   (MUST be 0)", n_swmr_viol);
          $display("SC-ON-UNOWNED-LINE h0=%0d h1=%0d   (MUST be 0/0)",
                   n_sc_nowrite[0], n_sc_nowrite[1]);
          $display("COH  snp_clr h0=%0d h1=%0d | BOTH-RSV-LIVE-SAME-LINE cycles=%0d",
                   n_snpclr[0], n_snpclr[1], n_both_live);
          $display("HAZARD h1 BOTH-OUTSTANDING cycles=%0d   (MUST be 0)", n_hazard);
          $display("HAZARD-PROBE h1: SN_WAIT cycles=%0d  main-outstanding cycles=%0d  D_FILL cycles=%0d",
                   n_snwait, n_mainout, n_fill);
          $display("DUAL cycles=%0d", cyc);
          $display("STARVE(measured, cycles asserted)  I: h0=%0d h1=%0d  D: h0=%0d h1=%0d",
                   n_starve_i[0], n_starve_i[NUM_HARTS-1],
                   n_starve_d[0], n_starve_d[NUM_HARTS-1]);
          $display("MASTER BUSY cycles  m0(D+MMIO)=%0d  m1(I)=%0d  of %0d",
                   n_cyc_busy_m0, n_cyc_busy_m1, cyc);

          for (int k = 0; k < NUM_HARTS; k++)
            if (ins_h[k] == 0)
              $display("DUAL FAIL: hart %0d retired ZERO instructions", k);
          $finish;
        end
      end
    end
  end

  string hexfile;
  int unsigned dly, bdly, skew0, skew1;
  initial begin
    if (!$value$plusargs("DELAY=%d", dly))        dly  = 10;
    if (!$value$plusargs("BEAT_DELAY=%d", bdly))  bdly = 1;
    if (!$value$plusargs("HEX=%s", hexfile))      hexfile = "asm/mh.hex";
    if (!$value$plusargs("TOHOST=%h", tohost_addr)) tohost_addr = 32'h8000_1000;
    if (!$value$plusargs("TRUNC_PC=%h", trunc_pc))  trunc_pc = 32'h0;
    if ($test$plusargs("VCD")) begin
      int unsigned vcd_end;
      if (!$value$plusargs("VCD_END=%d", vcd_end)) vcd_end = 100000;
      $dumpfile("/tmp/dual.vcd");
      $dumpvars(1, u_cl);
      $dumpvars(0, u_cl.u_cluster.u_lrsc);
      $dumpvars(1, u_cl.u_cluster.g_hart[1].u_core);
      $dumpvars(0, u_cl.u_cluster.u_coh);
      $dumpvars(0, u_cl.u_cluster.g_hart[0].u_dc);
      $dumpvars(0, u_cl.u_cluster.g_hart[1].u_dc);
      fork begin
        #(vcd_end);
        $dumpoff;
        $display("VCD WINDOW END at t=%0t", $time);
        $finish;
      end join_none
    end
    cfg_delay      = dly;
    cfg_beat_delay = bdly;
    done           = 1'b0;
    hit_barrier    = '0;

    for (int i = 0; i < 65536; i++) u_cl.u_mem.mem[i] = 32'h0;
    $readmemh(hexfile, u_cl.u_mem.mem);
    if ($value$plusargs("SKEW0=%d", skew0)) u_cl.u_mem.mem[16'hC80] = skew0;
    if ($value$plusargs("SKEW1=%d", skew1)) u_cl.u_mem.mem[16'hC90] = skew1;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
  end

  always_ff @(posedge clk) if (rst_n) begin
    if (err_range)   $display("DUAL FAIL: sim_mem range error");
    if (err_overlap) $display("DUAL FAIL: sim_mem overlap error");
  end

  initial begin
    #4000000;
    $display("DUAL TIMEOUT");
    $display("LRSC cnt0=%0d cnt1=%0d rsv=%b prot=%b defer=%b snpclr=%b",
             u_cl.u_cluster.u_lrsc.cnt_q[0], u_cl.u_cluster.u_lrsc.cnt_q[1],
             u_cl.u_cluster.rsv_valid, u_cl.u_cluster.prot_valid, u_cl.u_cluster.u_coh.prot_deferred,
             u_cl.u_cluster.snp_clr);
    $display("LRSC events  LR: h0=%0d h1=%0d | SC: h0=%0d h1=%0d | SC-OK: h0=%0d h1=%0d",
             n_lr[0], n_lr[1], n_sc[0], n_sc[1], n_scok[0], n_scok[1]);
    $display("FIRST FAILING SC (h1): rsv_line=%h  sc_addr=%h  rsv_valid=%b",
             f_rsvline, f_accaddr, f_rsv);
    $display("STRESS shared_buf[0]=%0d counter=%0d",
             u_cl.u_mem.mem[16'hC40], u_cl.u_mem.mem[16'hC50]);
    $display("set16 H0: %s/%h %s/%h | H1: %s/%h %s/%h",
             u_cl.u_cluster.g_hart[0].u_dc.tag_q[16][0].state.name(), u_cl.u_cluster.g_hart[0].u_dc.tag_q[16][0].tag,
             u_cl.u_cluster.g_hart[0].u_dc.tag_q[16][1].state.name(), u_cl.u_cluster.g_hart[0].u_dc.tag_q[16][1].tag,
             u_cl.u_cluster.g_hart[1].u_dc.tag_q[16][0].state.name(), u_cl.u_cluster.g_hart[1].u_dc.tag_q[16][0].tag,
             u_cl.u_cluster.g_hart[1].u_dc.tag_q[16][1].state.name(), u_cl.u_cluster.g_hart[1].u_dc.tag_q[16][1].tag);
    $display("MEM flag@0x3100=%h payload@0x3104=%h",
             u_cl.u_mem.mem[16'hC40], u_cl.u_mem.mem[16'hC41]);
    $display("SNOOP hits h0=%0d h1=%0d | completions with shared=1: %0d", n_snphit0, n_snphit1, n_shared);
    $display("COH reqs h0=%0d h1=%0d | snoops=%0d | acks=%0d | st0=%s st1=%s",
             n_req0, n_req1, n_snp, n_ack,
             u_cl.u_cluster.g_hart[0].u_dc.dstate_q.name(), u_cl.u_cluster.g_hart[1].u_dc.dstate_q.name());
    $display("M0 busy=%b own=%0d req=%b%b gnt=%b%b rvalid=%b%b addr=%h word=%b",
             u_cl.u_cluster.u_md.busy_q, u_cl.u_cluster.u_md.own_q,
             u_cl.u_cluster.m0_req[1], u_cl.u_cluster.m0_req[0], u_cl.u_cluster.m0_gnt[1], u_cl.u_cluster.m0_gnt[0],
             u_cl.u_cluster.m0_rvalid[1], u_cl.u_cluster.m0_rvalid[0], u_cl.u_cluster.md_addr, u_cl.u_cluster.md_word);
    $display("M1 busy=%b own=%0d ireq=%b%b ignt=%b%b addr=%h",
             u_cl.u_cluster.u_mi.busy_q, u_cl.u_cluster.u_mi.own_q,
             u_cl.u_cluster.i_req_a[1], u_cl.u_cluster.i_req_a[0], u_cl.u_cluster.i_gnt_a[1], u_cl.u_cluster.i_gnt_a[0],
             u_cl.u_cluster.mi_addr);
    $display("STARVE d=%b%b i=%b%b   (HANDOFF 6.3: MEASURED, not assumed)",
             u_cl.u_cluster.ev_starve_d[1], u_cl.u_cluster.ev_starve_d[0],
             u_cl.ev_starve_i[1], u_cl.ev_starve_i[0]);
    $display("MEM hart_done[0]=%h hart_done[1]=%h hart_result[0]=%h hart_result[1]=%h",
             u_cl.u_mem.mem[16'hC00], u_cl.u_mem.mem[16'hC10],
             u_cl.u_mem.mem[16'hC20], u_cl.u_mem.mem[16'hC30]);
    $display("SLAVES clint: req=%b gnt=%b rvalid=%b | mem ar_valid=%b aw_valid=%b",
             u_cl.cl_req, u_cl.cl_gnt, u_cl.cl_rvalid,
             u_cl.mem_req.ar_valid, u_cl.mem_req.aw_valid);
    for (int k = 0; k < NUM_HARTS; k++) $display("HART %0d retired %0d", k, ins_h[k]);
    $finish;
  end

endmodule
