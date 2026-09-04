// Gate for the LSQ snoop search port.
module tb_lsq_snoop
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
  import mem_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0;

  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  logic      alloc_load, alloc_store;
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
  logic      restore_valid;
  logic      viol_valid;
  rob_ptr_t  viol_rob_id;
  logic      snoop_valid, snoop_hit;
  word_t     snoop_addr;
  rob_ptr_t  snoop_hit_rob_id;

  lsq dut (
    .clk, .rst_n,
    .alloc_load, .alloc_store, .alloc_rob_id,
    .alloc_is_lr(1'b0), .alloc_is_sc(1'b0),
    .lrsc_lr_valid(), .lrsc_sc_valid(), .lrsc_addr(), .lrsc_acc_valid(),
    .lrsc_sc_success(1'b0), .lq_can_alloc, .sq_can_alloc,
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
    .snoop_valid, .snoop_addr, .snoop_hit, .snoop_hit_rob_id
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin dgnt <= 1'b0; drvalid <= 1'b0; drdata <= '0; end
    else begin
      dgnt    <= dreq;
      drvalid <= dgnt && !dwe;
      drdata  <= 32'hA5A5_1234;
    end
  end

  task automatic idle();
    alloc_load='0; alloc_store='0; alloc_rob_id='0;
    fill_valid='0; fill_is_store='0; fill_rob_id='0; fill_addr='0;
    fill_size=MEM_W; fill_wdata='0; fill_pdst='0;
    store_release='0; load_release='0; lq_walk_pop='0; sq_walk_pop='0;
    restore_valid='0; lq_restore_tail='0; sq_restore_tail='0;
    snoop_valid='0; snoop_addr='0;
  endtask

  task automatic alloc_ld(input rob_ptr_t rid);
    @(negedge clk); idle(); alloc_load=1'b1; alloc_rob_id=rid;
    @(posedge clk); #1; @(negedge clk); idle();
  endtask

  task automatic addr_ld(input rob_ptr_t rid, input word_t a, input mem_size_e sz);
    @(negedge clk); idle();
    fill_valid=1'b1; fill_is_store=1'b0; fill_rob_id=rid; fill_addr=a;
    fill_size=sz; fill_pdst=5'd7;
    @(posedge clk); #1; @(negedge clk); idle();
  endtask

  task automatic snoop(input word_t a, output logic hit, output rob_ptr_t rid);
    @(negedge clk); idle();
    snoop_valid=1'b1; snoop_addr=a;
    #1; hit = snoop_hit; rid = snoop_hit_rob_id;
    @(negedge clk); idle();
  endtask

  localparam word_t A = 32'h8000_1000;
  localparam word_t B = 32'h8000_2000;

  logic     hit;
  rob_ptr_t rid;
  int       guard;

  initial begin
    idle(); recovering=1'b0; ld_comp_ready=1'b1;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_lsq_snoop ===");

    alloc_ld(rob_ptr_t'(1));
    addr_ld(rob_ptr_t'(1), A, MEM_W);
    guard = 0;
    while (!ld_comp_valid && guard < 60) begin @(negedge clk); idle(); guard++; end
    ck("the oldest load executed and completed", ld_comp_valid === 1'b1 || guard < 60);
    snoop(A, hit, rid);
    ck("snoop does NOT flag the OLDEST in-flight load (nothing older can disagree)", hit === 1'b0);

    alloc_ld(rob_ptr_t'(2));                       // older, address never resolved
    alloc_ld(rob_ptr_t'(3));
    snoop(A, hit, rid);
    ck("snoop misses a load with no address yet", hit === 1'b0);

    addr_ld(rob_ptr_t'(3), A, MEM_W);              // executes ahead of load 2
    guard = 0;
    while (!ld_comp_valid && guard < 60) begin @(negedge clk); idle(); guard++; end
    ck("the younger load executed and completed", ld_comp_valid === 1'b1 || guard < 60);

    snoop(A, hit, rid);
    ck("snoop HITS a load executed ahead of an older unbound load", hit === 1'b1);
    ck("snoop reports the offending load's rob_id", rid === rob_ptr_t'(3));

    snoop(B, hit, rid);
    ck("snoop to a DIFFERENT line misses", hit === 1'b0);

    snoop(A + 32'd16, hit, rid);
    ck("snoop to the NEXT line misses", hit === 1'b0);

    @(negedge clk); idle(); #1;
    ck("snoop_hit is low when snoop_valid is low", snoop_hit === 1'b0);

    load_release=1'b0;
    alloc_ld(rob_ptr_t'(5));
    addr_ld(rob_ptr_t'(5), A + 32'd9, MEM_B);      // byte in word 2 of A's line
    guard = 0;
    while (guard < 40) begin @(negedge clk); idle(); guard++; end
    snoop(A, hit, rid);                             // the snoop names the line base
    ck("snoop on the line base hits a byte load in another word of the line", hit === 1'b1);
    snoop(A + 32'd16, hit, rid);                    // the next line
    ck("snoop on the next line misses the byte load",
       (hit === 1'b0) || (rid !== rob_ptr_t'(5)));

    recovering = 1'b1;
    alloc_ld(rob_ptr_t'(9));
    addr_ld(rob_ptr_t'(9), B, MEM_W);          // address known, cannot execute
    repeat (6) begin @(negedge clk); idle(); end
    snoop(B, hit, rid);
    ck("snoop MISSES a load that has an address but has NOT executed",
       (hit === 1'b0) || (rid !== rob_ptr_t'(9)));
    recovering = 1'b0;
    repeat (10) begin @(negedge clk); idle(); end

    snoop(A, hit, rid);
    ck("a snoop does NOT raise the store-fill violation output",
       viol_valid === 1'b0);

    $display("=== tb_lsq_snoop: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_LSQ_SNOOP PASS");
    else             $display("TB_LSQ_SNOOP BROKEN");
    $finish;
  end

  initial begin
    #200000; $display("TB_LSQ_SNOOP BROKEN (timeout)"); $finish;
  end

endmodule
