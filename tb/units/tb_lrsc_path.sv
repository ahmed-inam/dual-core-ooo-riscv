// The LR/SC path end to end at unit level:.
module tb_lrsc_path
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
  import mem_pkg::*;
  import coherence_pkg::*;
  import platform_cfg_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0;
  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  logic      alloc_load, alloc_store, alloc_is_lr, alloc_is_sc;
  rob_ptr_t  alloc_rob_id;
  logic      lq_can_alloc, sq_can_alloc;
  logic      fill_valid, fill_is_store;
  rob_ptr_t  fill_rob_id;
  word_t     fill_addr, fill_wdata;
  mem_size_e fill_size;
  preg_t     fill_pdst;
  logic      ld_comp_valid, ld_comp_ready;
  rob_ptr_t  ld_comp_rob_id;
  preg_t     ld_comp_pdst;
  word_t     ld_comp_data;
  logic      store_release, load_release, lq_walk_pop, sq_walk_pop;
  logic      dreq, dgnt, dwe, drvalid;
  word_t     daddr, dwdata, drdata;
  logic [3:0] dwstrb;
  logic      recovering, quiet;
  logic [LQ_W:0] lq_tail_o, lq_restore_tail;
  logic [SQ_W:0] sq_tail_o, sq_restore_tail;
  logic      restore_valid, viol_valid;
  rob_ptr_t  viol_rob_id;
  logic      snoop_valid, snoop_hit;
  word_t     snoop_addr;
  rob_ptr_t  snoop_hit_rob_id;
  logic      lrsc_lr_valid, lrsc_sc_valid, lrsc_acc_valid, lrsc_sc_success;
  word_t     lrsc_addr;
  logic      sc_head_go;

  lsq u_lsq (
    .clk, .rst_n,
    .alloc_load, .alloc_store, .alloc_rob_id, .alloc_is_lr, .alloc_is_sc,
    .sc_head_go,
    .lq_can_alloc, .sq_can_alloc,
    .fill_valid, .fill_is_store, .fill_rob_id, .fill_addr, .fill_size,
    .fill_wdata, .fill_pdst,
    .ld_comp_valid, .ld_comp_ready, .ld_comp_rob_id, .ld_comp_pdst, .ld_comp_data,
    .rvfi_m_ld_valid(), .rvfi_m_ld_id(), .rvfi_m_ld_addr(),
    .rvfi_m_ld_rdata(), .rvfi_m_ld_rmask(),
    .rvfi_m_st_valid(), .rvfi_m_st_id(), .rvfi_m_st_addr(),
    .rvfi_m_st_wdata(), .rvfi_m_st_wmask(),

    .store_release, .load_release, .lq_walk_pop, .sq_walk_pop,
    .dreq, .dgnt, .daddr, .dwe, .dwstrb, .dwdata, .drvalid, .drdata,
    .recovering, .quiet, .lq_tail_o, .sq_tail_o,
    .restore_valid, .lq_restore_tail, .sq_restore_tail,
    .viol_valid, .viol_rob_id,
    .lrsc_lr_valid, .lrsc_sc_valid, .lrsc_addr, .lrsc_acc_valid, .lrsc_sc_success,
    .snoop_valid, .snoop_addr, .snoop_hit, .snoop_hit_rob_id
  );

  logic  [NUM_HARTS-1:0] lr_v, sc_v, acc_v, acc_hit, snp_clr, trp_clr;
  word_t                 acc_addr [NUM_HARTS];
  logic  [NUM_HARTS-1:0] sc_ok, prot_valid, rsv_valid, backing_off;
  word_t                 prot_addr [NUM_HARTS];

  assign lr_v[0]   = lrsc_lr_valid;
  assign sc_v[0]   = lrsc_sc_valid;
  assign acc_v[0]  = lrsc_acc_valid;
  assign acc_hit[0]= 1'b1;                // this TB's memory always "hits"
  assign lr_v[1]='0; assign sc_v[1]='0; assign acc_v[1]='0; assign acc_hit[1]='0;
  assign acc_addr[1] = '0;
  always_comb acc_addr[0] = lrsc_addr;
  assign lrsc_sc_success = sc_ok[0];

  lrsc_unit u_lrsc (
    .clk, .rst_n,
    .lr_valid(lr_v), .sc_valid(sc_v), .acc_valid(acc_v), .acc_addr, .acc_hit,
    .snoop_clear(snp_clr), .trap_clear(trp_clr),
    .sc_success(sc_ok), .prot_valid, .prot_addr, .rsv_valid, .backing_off
  );

  int n_writes;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin dgnt <= 1'b0; drvalid <= 1'b0; n_writes <= 0; end
    else begin
      dgnt    <= dreq;
      drvalid <= dgnt;
      drdata  <= 32'h5A5A_0000;
      if (dreq && dgnt && dwe && (dwstrb != 4'b0000)) n_writes <= n_writes + 1;
    end
  end

  task automatic idle();
    alloc_load='0; alloc_store='0; alloc_rob_id='0;
    alloc_is_lr='0; alloc_is_sc='0;
    fill_valid='0; fill_is_store='0; fill_rob_id='0; fill_addr='0;
    fill_size=MEM_W; fill_wdata='0; fill_pdst='0;
    store_release='0; load_release='0; lq_walk_pop='0; sq_walk_pop='0;
    restore_valid='0; lq_restore_tail='0; sq_restore_tail='0;
    snoop_valid='0; snoop_addr='0;
    snp_clr='0; trp_clr='0; sc_head_go='0;
  endtask

  task automatic do_lr(input rob_ptr_t rid, input word_t a);
    @(negedge clk); idle(); alloc_load=1'b1; alloc_is_lr=1'b1; alloc_rob_id=rid;
    @(posedge clk); #1; @(negedge clk); idle();
    fill_valid=1'b1; fill_is_store=1'b0; fill_rob_id=rid; fill_addr=a;
    fill_size=MEM_W; fill_pdst=5'd3;
    @(posedge clk); #1; @(negedge clk); idle();
    repeat (8) begin @(negedge clk); idle(); end
  endtask

  task automatic do_sc(input rob_ptr_t rid, input word_t a);
    @(negedge clk); idle(); alloc_store=1'b1; alloc_is_sc=1'b1; alloc_rob_id=rid;
    @(posedge clk); #1; @(negedge clk); idle();
    fill_valid=1'b1; fill_is_store=1'b1; fill_rob_id=rid; fill_addr=a;
    fill_size=MEM_W; fill_wdata=32'hC0DE_0001;
    @(posedge clk); #1; @(negedge clk); idle();
    store_release=1'b1;                       // commit it so it drains
    @(posedge clk); #1; @(negedge clk); idle();
    repeat (10) begin @(negedge clk); idle(); end
  endtask

  localparam word_t A = 32'h8000_1000;
  localparam word_t B = 32'h8000_2000;

  int w0;

  initial begin
    idle(); recovering=1'b0; ld_comp_ready=1'b1;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_lrsc_path ===");

    ck("no reservation at reset", rsv_valid[0] === 1'b0);
    do_lr(rob_ptr_t'(1), A);
    ck("an LR launching to memory ARMS the reservation", rsv_valid[0] === 1'b1);
    ck("the reservation is on the LR's line",
       u_lrsc.rsv_line_q[0] === A[31:OFF_W]);

    w0 = n_writes;
    do_sc(rob_ptr_t'(2), A);
    ck("SC to the reserved line WROTE memory", n_writes > w0);

    w0 = n_writes;
    do_sc(rob_ptr_t'(3), A);
    ck("a second SC finds NO reservation and writes NOTHING", n_writes == w0);

    do_lr(rob_ptr_t'(4), A);
    ck("re-armed", rsv_valid[0] === 1'b1);
    @(negedge clk); idle(); snp_clr[0]=1'b1;
    @(posedge clk); #1; @(negedge clk); idle();
    ck("a snooped GetM CLEARED the reservation", rsv_valid[0] === 1'b0);
    w0 = n_writes;
    do_sc(rob_ptr_t'(5), A);
    ck("an SC after the snoop writes NOTHING", n_writes == w0);

    do_lr(rob_ptr_t'(6), A);
    w0 = n_writes;
    do_sc(rob_ptr_t'(7), B);
    ck("SC to a different line than the LR writes NOTHING", n_writes == w0);

    w0 = n_writes;
    @(negedge clk); idle(); alloc_store=1'b1; alloc_rob_id=rob_ptr_t'(8);
    @(posedge clk); #1; @(negedge clk); idle();
    fill_valid=1'b1; fill_is_store=1'b1; fill_rob_id=rob_ptr_t'(8);
    fill_addr=B; fill_size=MEM_W; fill_wdata=32'hAAAA_5555;
    @(posedge clk); #1; @(negedge clk); idle();
    store_release=1'b1; @(posedge clk); #1; @(negedge clk); idle();
    repeat (10) begin @(negedge clk); idle(); end
    ck("an ORDINARY store still writes (no LR/SC regression)", n_writes > w0);

    // An SC that is the ROB head before it has executed must not be drained yet.
    do_lr(rob_ptr_t'(9), A);
    @(negedge clk); idle(); alloc_store=1'b1; alloc_is_sc=1'b1; alloc_rob_id=rob_ptr_t'(10);
    @(posedge clk); #1; @(negedge clk); idle();
    w0 = 0;
    repeat (6) begin
      @(negedge clk); idle(); sc_head_go=1'b1;
      #1; if (dreq) w0++;
    end
    ck("an SC at the head with NO address yet does not request memory", w0 == 0);
    @(negedge clk); idle(); sc_head_go=1'b1;
    fill_valid=1'b1; fill_is_store=1'b1; fill_rob_id=rob_ptr_t'(10); fill_addr=A;
    fill_size=MEM_W; fill_wdata=32'hC0DE_0002;
    @(posedge clk); #1; @(negedge clk); idle(); sc_head_go=1'b1;
    w0 = 0;
    repeat (6) begin
      #1; if (dreq && dwe) w0++;
      @(negedge clk); idle(); sc_head_go=1'b1;
    end
    ck("the same SC drains once its address is known", w0 > 0);
    repeat (10) begin @(negedge clk); idle(); end

    $display("=== tb_lrsc_path: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_LRSC_PATH PASS");
    else             $display("TB_LRSC_PATH BROKEN");
    $finish;
  end

  initial begin
    #300000; $display("TB_LRSC_PATH BROKEN (timeout)"); $finish;
  end

endmodule
