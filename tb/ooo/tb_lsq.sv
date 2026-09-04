// Unit proof of the load/store queue.
`timescale 1ns/1ps
module tb_lsq;
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic alloc_load, alloc_store; rob_ptr_t alloc_rob_id;
  logic lq_can_alloc, sq_can_alloc;
  logic fill_valid, fill_is_store; rob_ptr_t fill_rob_id;
  word_t fill_addr, fill_wdata; mem_size_e fill_size; preg_t fill_pdst;
  logic ld_comp_valid, ld_comp_ready;
  rob_ptr_t ld_comp_rob_id; preg_t ld_comp_pdst; word_t ld_comp_data;
  logic ld_comp_err; word_t ld_comp_addr;
  logic drerr = 1'b0;
  logic store_release, load_release, lq_walk_pop, sq_walk_pop;
  logic dreq, dgnt, dwe, drvalid; word_t daddr, dwdata, drdata;
  logic [3:0] dwstrb;
  logic quiet;
  logic [LQ_W:0] lq_tail_o; logic [SQ_W:0] sq_tail_o;
  logic viol_valid; rob_ptr_t viol_rob_id;
  logic       rvfi_m_ld_valid, rvfi_m_st_valid;
  rob_ptr_t   rvfi_m_ld_id,    rvfi_m_st_id;
  word_t      rvfi_m_ld_addr,  rvfi_m_ld_rdata;
  word_t      rvfi_m_st_addr,  rvfi_m_st_wdata;
  logic [3:0] rvfi_m_ld_rmask, rvfi_m_st_wmask;

  logic  alloc_is_lr = 1'b0, alloc_is_sc = 1'b0;
  logic  lrsc_lr_valid, lrsc_sc_valid, lrsc_acc_valid;
  word_t lrsc_addr;
  logic  lrsc_sc_success = 1'b0;
  logic snoop_valid = 1'b0;
  word_t snoop_addr = '0;
  logic snoop_hit; rob_ptr_t snoop_hit_rob_id;

  logic restore_valid;
  logic [LQ_W:0] lq_restore_tail; logic [SQ_W:0] sq_restore_tail;

  logic recovering;
  rob_ptr_t pick_rob_id_o;
  logic lr_go_ok = 1'b1;

  preg_t    alloc_pdst;
  logic     sc_head_go;
  logic     dis_lr;        // LR write-intent out of the lsq
  logic     sc_done_pulse;
  rob_ptr_t sc_done_rob_id;
  preg_t    sc_done_pdst;
  word_t    sc_done_val;
  assign alloc_pdst = '0;
  assign sc_head_go = 1'b0;

  lsq dut (.*);

  word_t mem [0:255];
  assign dgnt = dreq;
  logic  rv_q; word_t rd_q;
  always_ff @(posedge clk) begin
    rv_q <= dreq && dgnt;
    if (dreq && dgnt) begin
      rd_q <= mem[daddr[9:2]];
      if (dwe) begin
        if (dwstrb[0]) mem[daddr[9:2]][7:0]   <= dwdata[7:0];
        if (dwstrb[1]) mem[daddr[9:2]][15:8]  <= dwdata[15:8];
        if (dwstrb[2]) mem[daddr[9:2]][23:16] <= dwdata[23:16];
        if (dwstrb[3]) mem[daddr[9:2]][31:24] <= dwdata[31:24];
      end
    end
  end
  assign drvalid = rv_q;
  assign drdata  = rd_q;

  int errors = 0;
  task chk(string s, logic c); if (!c) begin $display("FAIL %s", s); errors++; end endtask

  int rid = 0;
  task automatic alloc(input logic st, output rob_ptr_t id);
    @(negedge clk);
    id = rob_ptr_t'(rid); rid++;
    alloc_rob_id = id;
    alloc_store = st; alloc_load = !st;
    @(negedge clk);
    alloc_store = 0; alloc_load = 0;
  endtask

  task automatic fill_st(input rob_ptr_t id, input word_t a,
                         input mem_size_e sz, input word_t d);
    @(negedge clk);
    fill_rob_id = id; fill_addr = a; fill_size = sz; fill_wdata = d;
    fill_is_store = 1; fill_valid = 1;
    @(negedge clk);
    fill_valid = 0;
  endtask

  task automatic fill_ld(input rob_ptr_t id, input word_t a,
                         input mem_size_e sz, input preg_t pd);
    @(negedge clk);
    fill_rob_id = id; fill_addr = a; fill_size = sz; fill_pdst = pd;
    fill_is_store = 0; fill_valid = 1;
    @(negedge clk);
    fill_valid = 0;
  endtask

  typedef struct { int id; word_t d; } comp_t;
  comp_t obs [$];
  logic auto_rel;
  always @(negedge clk) load_release <= 1'b0;
  always @(negedge clk)
    if (rst_n && ld_comp_valid && ld_comp_ready)
      begin
        automatic comp_t e;
        e.id = int'(ld_comp_rob_id);
        e.d  = ld_comp_data;
        obs.push_back(e);
        if (auto_rel) load_release <= 1'b1;
      end

  task automatic fill_st_watch(input rob_ptr_t id, input word_t a,
                               input mem_size_e sz, input word_t d,
                               output logic saw, output rob_ptr_t sid);
    @(negedge clk);
    fill_rob_id = id; fill_addr = a; fill_size = sz; fill_wdata = d;
    fill_is_store = 1; fill_valid = 1;
    #1;
    saw = viol_valid; sid = viol_rob_id;
    @(negedge clk);
    fill_valid = 0; fill_is_store = 0;
  endtask

  task automatic takec(output comp_t c, input int limit);
    c.id = -1; c.d = '0;
    for (int i = 0; i < limit; i++) begin
      if (obs.size() > 0) begin c = obs.pop_front(); return; end
      @(negedge clk);
    end
    if (obs.size() > 0) c = obs.pop_front();
  endtask

  int ld_accesses;
  always @(negedge clk) if (rst_n && dreq && dgnt && !dwe)
    ld_accesses = ld_accesses + 1;

  rob_ptr_t s1, s2, l1, l2;
  comp_t c;
  initial begin
    alloc_load=0; alloc_store=0; alloc_rob_id='0;
    fill_valid=0; fill_is_store=0; fill_rob_id='0;
    fill_addr='0; fill_size=MEM_W; fill_wdata='0; fill_pdst='0;
    store_release=0; load_release=0; lq_walk_pop=0; sq_walk_pop=0;
    restore_valid=0; lq_restore_tail='0; sq_restore_tail='0; recovering=0;
    auto_rel=1;
    ld_comp_ready=1;
    ld_accesses=0;
    for (int i = 0; i < 256; i++) mem[i] = 32'hC0DE0000 + i;
    #12 rst_n = 1;

    alloc(1, s1); fill_st(s1, 32'h40, MEM_W, 32'hAABBCCDD);
    @(negedge clk); chk("committed-undrained: not quiet? (uncommitted is inert -> quiet)", quiet == 1'b1);
    @(negedge clk); store_release = 1; @(negedge clk); store_release = 0;
    @(negedge clk); chk("committed: NOT quiet", quiet == 1'b0);
    repeat (6) @(negedge clk);
    chk("drained: quiet again", quiet == 1'b1);
    chk("memory took the store", mem[32'h40>>2] == 32'hAABBCCDD);

    alloc(0, l1); fill_ld(l1, 32'h80, MEM_W, preg_t'(40));
    takec(c, 10);
    chk("plain load completes", c.id == int'(l1));
    chk("plain load data", c.d == mem[32'h80>>2]);

    ld_accesses = 0;
    alloc(1, s1); fill_st(s1, 32'h44, MEM_W, 32'h1234_5678);
    alloc(0, l1); fill_ld(l1, 32'h44, MEM_W, preg_t'(41));
    takec(c, 10);
    chk("word forward completes", c.id == int'(l1));
    chk("word forward data", c.d == 32'h1234_5678);
    chk("word forward took NO memory access", ld_accesses == 0);
    @(negedge clk); store_release = 1; @(negedge clk); store_release = 0;
    repeat (6) @(negedge clk);

    alloc(1, s1); fill_st(s1, 32'h49, MEM_B, 32'h0000_00F5);
    alloc(0, l1); fill_ld(l1, 32'h49, MEM_B, preg_t'(42));
    takec(c, 10);
    chk("LB forward sign-extends", c.d == 32'hFFFF_FFF5);
    alloc(0, l2); fill_ld(l2, 32'h49, MEM_BU, preg_t'(43));
    takec(c, 10);
    chk("LBU forward zero-extends", c.d == 32'h0000_00F5);
    @(negedge clk); store_release = 1; @(negedge clk); store_release = 0;
    repeat (6) @(negedge clk);

    alloc(1, s1); fill_st(s1, 32'h50, MEM_W, 32'h01D0_0001);
    alloc(1, s2); fill_st(s2, 32'h50, MEM_W, 32'hFEED_F00D);
    alloc(0, l1); fill_ld(l1, 32'h50, MEM_W, preg_t'(44));
    takec(c, 10);
    chk("freshness: the YOUNGER store's data forwards", c.d == 32'hFEED_F00D);
    repeat (2) begin
      @(negedge clk); store_release = 1; @(negedge clk); store_release = 0;
      repeat (6) @(negedge clk);
    end

    ld_accesses = 0;
    alloc(1, s1);                                  // address UNKNOWN
    alloc(0, l1); fill_ld(l1, 32'h90, MEM_W, preg_t'(45));
    takec(c, 12);
    chk("load speculates past unknown older store",
        c.id == int'(l1) && ld_accesses == 1);
    chk("speculative load read memory", c.d == mem[32'h90>>2]);
    begin
      automatic logic vs; automatic rob_ptr_t vi;
      fill_st_watch(s1, 32'h60, MEM_W, 32'h1, vs, vi);      // diff word
      chk("disjoint fill after speculation: no violation", !vs);
    end
    @(negedge clk); store_release = 1; @(negedge clk); store_release = 0;
    repeat (6) @(negedge clk);

    alloc(1, s1); fill_st(s1, 32'h71, MEM_B, 32'h0000_00AA);  // byte in word 0x70
    alloc(0, l1); fill_ld(l1, 32'h70, MEM_W, preg_t'(46));    // whole word
    repeat (6) @(negedge clk);
    chk("conflict load parked while store resident", obs.size() == 0);
    @(negedge clk); store_release = 1; @(negedge clk); store_release = 0;
    takec(c, 16);
    chk("conflict load completes after drain", c.id == int'(l1));
    chk("conflict load sees the drained byte",
        c.d == {mem[32'h70>>2][31:16], 8'hAA, mem[32'h70>>2][7:0]});

    ld_accesses = 0;
    alloc(0, l1);
    alloc(1, s1); fill_st(s1, 32'hA0, MEM_W, 32'hDEAD_BEEF);  // younger, known
    fill_ld(l1, 32'hA0, MEM_W, preg_t'(47));
    takec(c, 10);
    chk("older load ignored the younger store (memory data)",
        c.d == mem[32'hA0>>2] && c.d != 32'hDEAD_BEEF);
    @(negedge clk); store_release = 1; @(negedge clk); store_release = 0;
    repeat (6) @(negedge clk);

    ld_comp_ready = 0;
    alloc(0, l1); fill_ld(l1, 32'hB0, MEM_W, preg_t'(48));
    repeat (8) @(negedge clk);
    chk("completion offered under backpressure", ld_comp_valid == 1'b1);
    chk("not recorded while lane held", obs.size() == 0);
    @(negedge clk); ld_comp_ready = 1;
    takec(c, 6);
    chk("skid delivers on ready", c.id == int'(l1) && c.d == mem[32'hB0>>2]);

    alloc(1, s1); fill_st(s1, 32'hC0, MEM_W, 32'h5);
    alloc(0, l1);
    @(negedge clk); lq_walk_pop = 1; @(negedge clk); lq_walk_pop = 0;
    @(negedge clk); sq_walk_pop = 1; @(negedge clk); sq_walk_pop = 0;
    repeat (3) @(negedge clk);
    chk("walked store never drains", mem[32'hC0>>2] != 32'h5);
    chk("quiet after walk", quiet == 1'b1);

    begin
      automatic logic [LQ_W:0] lt; automatic logic [SQ_W:0] st;
      lt = lq_tail_o; st = sq_tail_o;
      alloc(1, s1); fill_st(s1, 32'hD0, MEM_W, 32'h7);
      alloc(0, l1);
      @(negedge clk);
      restore_valid = 1; lq_restore_tail = lt; sq_restore_tail = st;
      @(negedge clk); restore_valid = 0;
      repeat (4) @(negedge clk);
      chk("restore: dropped store never drains", mem[32'hD0>>2] != 32'h7);
      chk("restore: tails rolled back",
          lq_tail_o == lt && sq_tail_o == st);
      chk("restore: quiet (nothing in flight)", quiet == 1'b1);
    end

    rst_n = 0; repeat (2) @(negedge clk); rst_n = 1; @(negedge clk);
    auto_rel = 0;   // 4f-c movements model an unretired-resident ROB
    begin
      automatic rob_ptr_t su, lu; automatic comp_t cc;
      alloc(1, su);                                   // never filled here
      alloc(0, lu);
      fill_ld(lu, 32'h80, MEM_W, preg_t'(40));
      takec(cc, 12);
      chk("spec: load executes past unknown-addr older store",
          cc.id == int'(lu) && cc.d == 32'hC0DE0020);
      begin
        automatic logic vs; automatic rob_ptr_t vi;
        fill_st_watch(su, 32'h84, MEM_W, 32'h9, vs, vi);      // disjoint
        chk("spec: disjoint fill raises no violation", !vs);
      end
      store_release = 1; @(negedge clk); store_release = 0;
      repeat (6) @(negedge clk);                      // drain, tidy
      load_release = 1; @(negedge clk); load_release = 0;
    end

    begin
      automatic rob_ptr_t sv, lv; automatic comp_t cc;
      alloc(1, sv);
      alloc(0, lv);
      fill_ld(lv, 32'h90, MEM_W, preg_t'(41));
      takec(cc, 12);
      chk("viol: stale load completed (pre-fill)", cc.id == int'(lv));
      begin
        automatic logic vs; automatic rob_ptr_t vi;
        fill_st_watch(sv, 32'h90, MEM_W, 32'h5, vs, vi);
        chk("viol: CAM fires on overlapping fill", vs);
        chk("viol: reports the violating load id",  vi == lv);
      end
      restore_valid = 1;
      lq_restore_tail = lq_tail_o - (LQ_W+1)'(1);
      sq_restore_tail = sq_tail_o - (SQ_W+1)'(1);
      @(negedge clk); restore_valid = 0; @(negedge clk);
    end

    begin
      automatic rob_ptr_t sa, sb, lp; automatic comp_t cc;
      alloc(1, sa);                                   // older, unknown
      alloc(1, sb);                                   // younger
      fill_st(sb, 32'hA0, MEM_W, 32'h77);
      alloc(0, lp);
      fill_ld(lp, 32'hA0, MEM_W, preg_t'(42));
      takec(cc, 12);
      chk("prov: load forwarded from the younger store",
          cc.id == int'(lp) && cc.d == 32'h77);
      begin
        automatic logic vs; automatic rob_ptr_t vi;
        fill_st_watch(sa, 32'hA0, MEM_W, 32'h11, vs, vi);
        chk("prov: older fill is masked -- no violation", !vs);
      end
      restore_valid = 1;
      lq_restore_tail = lq_tail_o - (LQ_W+1)'(1);
      sq_restore_tail = sq_tail_o - (SQ_W+1)'(2);
      @(negedge clk); restore_valid = 0; @(negedge clk);
    end

    begin
      automatic rob_ptr_t sm, lm2;
      alloc(1, sm);
      alloc(0, lm2);
      fill_ld(lm2, 32'hB0, MEM_W, preg_t'(43));
      begin
        automatic logic vs; automatic rob_ptr_t vi;
        fill_st_watch(sm, 32'hB0, MEM_W, 32'h6, vs, vi);      // in flight
        chk("midflight: fill during memory access still violates",
            vs && vi == lm2);
      end
      repeat (4) @(negedge clk);
      restore_valid = 1;
      lq_restore_tail = lq_tail_o - (LQ_W+1)'(1);
      sq_restore_tail = sq_tail_o - (SQ_W+1)'(1);
      @(negedge clk); restore_valid = 0; @(negedge clk);
    end

    begin
      automatic comp_t c; automatic rob_ptr_t lr;
      repeat (4) @(negedge clk);
      ld_accesses = 0; obs.delete(); auto_rel = 0;
      recovering = 1;                                 // recovery active
      alloc(0, lr); fill_ld(lr, 32'h140, MEM_W, preg_t'(9));
      repeat (8) @(negedge clk);                      // give it every chance
      chk("recovering: ready load did NOT launch a memory access",
          ld_accesses == 0);
      chk("recovering: no completion offered", obs.size() == 0 && !ld_comp_valid);
      recovering = 0;                                 // recovery ends
      takec(c, 12);                                   // now it must go
      chk("post-recovery: the same load launches and completes",
          c.id == int'(lr) && ld_accesses == 1);
      chk("post-recovery: load read the right memory word",
          c.d == mem[32'h140>>2]);
    end

    if (errors == 0) $display("LSQ PASS");
    else $display("LSQ FAIL: %0d", errors);
    $finish;
  end
endmodule
