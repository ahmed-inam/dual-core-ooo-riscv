// ISA-level functional coverage: opcodes, operands, hazards and traps.
`uvm_analysis_imp_decl(_ci_rvfi)
`uvm_analysis_imp_decl(_ci_mem)

class cov_isa extends uvm_component;
  `uvm_component_utils(cov_isa)

  uvm_analysis_imp_ci_rvfi #(rvfi_txn, cov_isa) rvfi_imp;
  uvm_analysis_imp_ci_mem  #(mem_txn,  cov_isa) mem_imp;

  cpu_cfg cfg;

  virtual core_probe_if probe [];
  protected virtual core_probe_if p0;

  protected word_t last_cause [NUM_HARTS];
  protected bit    cause_seen [NUM_HARTS];
  protected bit    last_trap  [NUM_HARTS];
  protected bit    last_mie   [NUM_HARTS];

  protected logic [3:0]  br_hist   [NUM_HARTS];   // gshare-shaped shift register
  protected bit          irq_entry_pend [NUM_HARTS];
  protected bit          irq_exit_pend  [NUM_HARTS];

  protected bit          prev_valid [NUM_HARTS];
  protected logic [4:0]  prev_rd    [NUM_HARTS];
  protected logic [4:0]  prev_rs1   [NUM_HARTS];
  protected logic [4:0]  prev_rs2   [NUM_HARTS];
  protected int unsigned prev_class [NUM_HARTS];
  localparam int unsigned MEM_WIN = SQ_N;

  protected bit          mw_valid [NUM_HARTS][MEM_WIN];
  protected bit          mw_is_st [NUM_HARTS][MEM_WIN];
  protected word_t       mw_addr  [NUM_HARTS][MEM_WIN];
  protected int unsigned mw_next  [NUM_HARTS];

  int unsigned n_sampled;
  int unsigned n_raw, n_war, n_waw, n_none;
  int unsigned n_lsu_raw, n_lsu_war, n_lsu_waw;
  int unsigned n_lsu_pairs;
  int unsigned n_br_taken, n_br_ntaken, n_div_zero, n_csr, n_bad_mask;
  int unsigned n_trap_binned, n_mstatus_edge;
  int unsigned n_mispred [5];
  int unsigned n_irq_ctx, n_mem_txn;
  int unsigned n_slot_marked [COMMIT_W];
  int unsigned n_slot1, n_slot1_serialising;
  int unsigned n_region_outside;
  word_t       first_region_outside;
  int unsigned n_lat_min = 32'hFFFF_FFFF;
  int unsigned n_lat_max;
  int unsigned n_axi_bad_burst, n_axi_bad_size, n_axi_exokay;

  localparam int unsigned HZ_NONE = 0;
  localparam int unsigned HZ_RAW  = 1;
  localparam int unsigned HZ_WAR  = 2;
  localparam int unsigned HZ_WAW  = 3;

  localparam int unsigned C_ALU    = 0;
  localparam int unsigned C_LOAD   = 1;
  localparam int unsigned C_STORE  = 2;
  localparam int unsigned C_BRANCH = 3;
  localparam int unsigned C_JUMP   = 4;
  localparam int unsigned C_MULDIV = 5;
  localparam int unsigned C_CSR    = 6;
  localparam int unsigned C_OTHER  = 7;

  covergroup cg_hazard with function sample(int unsigned a_hz,
                                            int unsigned a_class,
                                            int unsigned a_hart);
    option.per_instance = 1;

    cp_gpr_hazard : coverpoint a_hz {
      bins none = {HZ_NONE};
      bins raw  = {HZ_RAW};
      bins war  = {HZ_WAR};
      bins waw  = {HZ_WAW};
    }

    cp_class : coverpoint a_class {
      bins alu    = {C_ALU};
      bins load   = {C_LOAD};
      bins store  = {C_STORE};
      bins branch = {C_BRANCH};
      bins jump   = {C_JUMP};
      bins muldiv = {C_MULDIV};
      bins csr    = {C_CSR};
      bins other  = {C_OTHER};
    }

    cp_hz_hart : coverpoint a_hart { bins hart[] = {[0:NUM_HARTS-1]}; }

    x_hazard_class : cross cp_gpr_hazard, cp_class;
  endgroup

  covergroup cg_lsu_hazard with function sample(int unsigned a_hz,
                                                bit          a_same_word);
    option.per_instance = 1;

    cp_lsu_hazard : coverpoint a_hz {
      bins raw  = {HZ_RAW};   // store -> load, the forwarding case
      bins war  = {HZ_WAR};   // load  -> store
      bins waw  = {HZ_WAW};   // store -> store
    }

    cp_same_word : coverpoint a_same_word {
      bins exact     = {0};
      bins word_only = {1};
    }

    x_lsu : cross cp_lsu_hazard, cp_same_word {
    }
  endgroup


  covergroup cg_opcode with function sample(logic [6:0] a_op, int unsigned a_class);
    option.per_instance = 1;
    cp_opcode : coverpoint a_op {
      bins load     = {7'b0000011};
      bins op_imm   = {7'b0010011};
      bins auipc    = {7'b0010111};
      bins store    = {7'b0100011};
      bins op       = {7'b0110011};
      bins lui      = {7'b0110111};
      bins branch   = {7'b1100011};
      bins jalr     = {7'b1100111};
      bins jal      = {7'b1101111};
      bins system   = {7'b1110011};
      bins amo      = {7'b0101111};
      bins misc_mem = {7'b0001111};
      bins other    = default;
    }
    cp_op_class : coverpoint a_class {
      bins alu = {C_ALU}; bins load = {C_LOAD}; bins store = {C_STORE};
      bins branch = {C_BRANCH}; bins jump = {C_JUMP}; bins muldiv = {C_MULDIV};
      bins csr = {C_CSR}; bins other = {C_OTHER};
    }
  endgroup

  covergroup cg_operand with function sample(logic [4:0] a_rs1, logic [4:0] a_rs2,
                                             logic [4:0] a_rd,
                                             int unsigned a_s1, int unsigned a_s2,
                                             int unsigned a_sd, bit a_eq, bit a_gt,
                                             bit a_s1_v, bit a_s2_v, bit a_sd_v);
    option.per_instance = 1;
    cp_rs1 : coverpoint a_rs1 {
      bins x0 = {0}; bins link = {1, 5}; bins other = default;
    }
    cp_rs2 : coverpoint a_rs2 {
      bins x0 = {0}; bins link = {1, 5}; bins other = default;
    }
    cp_rd  : coverpoint a_rd {
      bins x0 = {0}; bins link = {1, 5}; bins other = default;
    }

    cp_rs1_sign : coverpoint a_s1 iff (a_s1_v) { bins zero = {0}; bins pos = {1}; bins neg = {2}; }
    cp_rs2_sign : coverpoint a_s2 iff (a_s2_v) { bins zero = {0}; bins pos = {1}; bins neg = {2}; }
    cp_rd_sign  : coverpoint a_sd iff (a_sd_v) { bins zero = {0}; bins pos = {1}; bins neg = {2}; }


    cp_rs1_eq_rs2 : coverpoint a_eq iff (a_s1_v && a_s2_v) { bins ne = {0}; bins eq = {1}; }
    cp_rs1_gt_rs2 : coverpoint a_gt iff (a_s1_v && a_s2_v) { bins le = {0}; bins gt = {1}; }
  endgroup

  covergroup cg_sign with function sample(int unsigned a_s1, int unsigned a_s2);
    option.per_instance = 1;
    cp_s1 : coverpoint a_s1 { bins zero = {0}; bins pos = {1}; bins neg = {2}; }
    cp_s2 : coverpoint a_s2 { bins zero = {0}; bins pos = {1}; bins neg = {2}; }
    x_sign : cross cp_s1, cp_s2;
  endgroup

  covergroup cg_memshape with function sample(int unsigned a_size, logic [1:0] a_off,
                                              bit a_is_store, int unsigned a_region);
    option.per_instance = 1;
    cp_size : coverpoint a_size { bins byte_ = {1}; bins half = {2}; bins word = {4}; }
    cp_offset : coverpoint a_off {
      bins off0 = {0}; bins off1 = {1}; bins off2 = {2}; bins off3 = {3};
    }
    cp_dir : coverpoint a_is_store { bins load = {0}; bins store = {1}; }
    cp_region : coverpoint a_region {
      bins text  = {0};
      bins data  = {1};
      bins stack = {2};
      bins other = {3};
    }
    x_shape : cross cp_size, cp_offset, cp_dir;
  endgroup

  covergroup cg_ras with function sample(int unsigned a_rs1l, int unsigned a_rdl,
                                         bit a_is_jal);
    option.per_instance = 1;
    cp_rs1_link : coverpoint a_rs1l { bins ra = {1}; bins t1 = {5}; bins non_link = {0}; }
    cp_rd_link  : coverpoint a_rdl  { bins ra = {1}; bins t1 = {5}; bins non_link = {0}; }
    cp_is_jal   : coverpoint a_is_jal { bins jalr = {0}; bins jal = {1}; }
    x_ras : cross cp_rs1_link, cp_rd_link;
  endgroup

  covergroup cg_branch with function sample(bit a_taken, bit a_back, logic [1:0] a_tgt_align);
    option.per_instance = 1;
    cp_branch_hit : coverpoint a_taken { bins not_taken = {0}; bins taken = {1}; }
    cp_direction  : coverpoint a_back  { bins forward = {0}; bins backward = {1}; }
    cp_tgt_align  : coverpoint a_tgt_align { bins aligned = {0}; bins mis[] = {[1:3]}; }
    x_branch : cross cp_branch_hit, cp_direction;
  endgroup

  covergroup cg_muldiv with function sample(int unsigned a_kind, int unsigned a_res);
    option.per_instance = 1;
    cp_kind : coverpoint a_kind {
      bins mul_ = {0}; bins mulh = {1}; bins div_ = {2}; bins rem_ = {3};
    }
    cp_div_result : coverpoint a_res {
      bins normal    = {0};
      bins by_zero   = {1};   // rs2 == 0
      bins overflow  = {2};   // most-negative / -1
    }
    x_div : cross cp_kind, cp_div_result;
  endgroup

  covergroup cg_csr with function sample(logic [11:0] a_csr);
    option.per_instance = 1;
    cp_csr : coverpoint a_csr {
      bins mstatus  = {12'h300}; bins mie     = {12'h304}; bins mtvec = {12'h305};
      bins mscratch = {12'h340}; bins mepc    = {12'h341}; bins mcause = {12'h342};
      bins mtval    = {12'h343}; bins mip     = {12'h344};
      bins mcycle   = {12'hB00}; bins minstret = {12'hB02};
      bins mhartid  = {12'hF14};
      bins misa     = {12'h301};
      bins mhpm     = {[12'hB03:12'hB0A]};
      bins counter_h = {[12'hB80:12'hB8A]};
      bins unpriv_ro = {[12'hC00:12'hC82]};
      bins id_ro    = {[12'hF11:12'hF13]};
      bins other    = default;
    }
  endgroup

  covergroup cg_mem_axi with function sample(int unsigned a_len, logic [2:0] a_size,
                                             logic [1:0] a_burst, logic [1:0] a_resp,
                                             bit a_is_write, int unsigned a_lat_b);
    option.per_instance = 1;
    cp_len : coverpoint a_len {
      bins single = {0};
      bins short_burst = {[1:3]};
      bins long_burst  = {[4:255]};
    }
    cp_size  : coverpoint a_size { bins word4 = {3'd2}; }
    cp_burst : coverpoint a_burst {
      bins incr = {2'd1};
      illegal_bins reserved = {2'd3};
    }
    cp_resp : coverpoint a_resp {
      bins okay = {2'd0};
      bins slverr = {2'd2}; bins decerr = {2'd3};
    }
    cp_dir : coverpoint a_is_write { bins read = {0}; bins write = {1}; }
    cp_lat : coverpoint a_lat_b {
      bins immediate = {0}; bins short_lat = {1}; bins medium_lat = {2}; bins long_lat = {3};
    }
    x_resp_dir : cross cp_resp, cp_dir;
    x_len_dir  : cross cp_len,  cp_dir;
    x_lat_dir  : cross cp_lat,  cp_dir;
  endgroup

  covergroup cg_branch_history with function sample(logic [3:0] a_hist, bit a_taken);
    option.per_instance = 1;
    cp_history : coverpoint a_hist {
      bins p00 = {0};
      bins p01 = {1};
      bins p02 = {2};
      bins p03 = {3};
      bins p04 = {4};
      bins p05 = {5};
      bins p06 = {6};
      bins p07 = {7};
      bins p08 = {8};
      bins p09 = {9};
      bins p10 = {10};
      bins p11 = {11};
      bins p12 = {12};
      bins p13 = {13};
      bins p14 = {14};
      bins p15 = {15};
    }
    cp_next    : coverpoint a_taken { bins not_taken = {0}; bins taken = {1}; }
    x_hist_next : cross cp_history, cp_next;
  endgroup


  covergroup cg_commit_slot with function sample(int unsigned a_slot,
                                                 bit a_marked, int unsigned a_hart);
    option.per_instance = 1;
    cp_slot   : coverpoint a_slot { bins slot0 = {0}; bins slot1 = {1}; }
    cp_marked : coverpoint a_marked { bins clean = {0}; bins marked = {1}; }
    cp_cs_hart : coverpoint a_hart { bins hart[] = {[0:NUM_HARTS-1]}; }
    x_slot_marked : cross cp_slot, cp_marked;
  endgroup

  covergroup cg_slot_class with function sample(int unsigned a_slot,
                                                int unsigned a_kind);
    option.per_instance = 1;
    cp_sc_slot : coverpoint a_slot { bins slot0 = {0}; bins slot1 = {1}; }
    cp_sc_kind : coverpoint a_kind {
      bins serialising = {0};   // CSR / mret / fence / fence.i -- slot 0 ONLY
      bins memory      = {1};   // one release per cycle, so at most one per group
      bins plain       = {2};   // everything with no retirement-time side effect
    }
    x_slot_kind : cross cp_sc_slot, cp_sc_kind;
  endgroup

  covergroup cg_irq_context with function sample(int unsigned a_class, bit a_is_exit);
    option.per_instance = 1;
    cp_ctx_class : coverpoint a_class {
      bins alu = {C_ALU}; bins load = {C_LOAD}; bins store = {C_STORE};
      bins branch = {C_BRANCH}; bins jump = {C_JUMP}; bins muldiv = {C_MULDIV};
      bins csr = {C_CSR}; bins other = {C_OTHER};
    }
    cp_ctx_when : coverpoint a_is_exit { bins entry = {0}; bins exit_ = {1}; }
    x_irq_ctx : cross cp_ctx_class, cp_ctx_when;
  endgroup

  covergroup cg_exception with function sample(bit a_is_irq, int unsigned a_code);
    option.per_instance = 1;
    cp_kind : coverpoint a_is_irq { bins exception = {0}; bins interrupt = {1}; }
    cp_cause : coverpoint a_code {
      bins insn_misaligned  = {0};
      bins insn_fault       = {1};
      bins illegal_insn     = {2};
      bins load_fault       = {5};
      bins load_misaligned  = {4};
      bins store_misaligned = {6};
      bins irq_soft         = {3};   // only when bit 31 is set -- see cp_kind
      bins irq_timer        = {7};
      bins other            = default;
    }
    x_trap : cross cp_kind, cp_cause;
  endgroup

  covergroup cg_mstatus with function sample(bit a_mie, bit a_mpie,
                                             logic [1:0] a_mpp, bit a_entry);
    option.per_instance = 1;
    cp_mie  : coverpoint a_mie  { bins disabled = {0}; bins enabled = {1}; }
    cp_mpie : coverpoint a_mpie { bins zero = {0}; bins one = {1}; }
    cp_mpp  : coverpoint a_mpp { bins hardwired_m = {2'd3}; bins unexpected = {[0:2]}; }
    cp_when : coverpoint a_entry { bins exit_ = {0}; bins entry = {1}; }
    x_mstatus : cross cp_mie, cp_mpie, cp_when;
  endgroup

  covergroup cg_mispredict_src with function sample(int unsigned a_src, bit a_hart);
    option.per_instance = 1;
    cp_src : coverpoint a_src {
      bins ras_return   = {0};   // ret: the return-address stack was wrong
      bins call_target  = {1};   // call: BTB target for a call
      bins gshare_dir   = {2};   // conditional branch: direction was wrong
      bins indirect_tgt = {3};   // jalr, neither call nor return
      bins direct_tgt   = {4};   // jal, not a call
    }
    cp_ms_hart : coverpoint a_hart { bins hart0 = {0}; bins hart1 = {1}; }
    x_src_hart : cross cp_src, cp_ms_hart;
  endgroup

  covergroup cg_isa_selftest with function sample(int unsigned a_v, int unsigned a_w,
                                                  int unsigned a_g);
    option.per_instance = 1;
    cp_st_a : coverpoint a_v { bins zero = {0}; bins one = {1}; }
    cp_st_b : coverpoint a_w { bins zero = {0}; bins one = {1}; }
    x_st    : cross cp_st_a, cp_st_b;
    cp_st_g : coverpoint a_g iff (a_g != 0) { bins one = {1}; bins two = {2}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rvfi_imp = new("rvfi_imp", this);
    mem_imp  = new("mem_imp",  this);
    cg_hazard     = new();
    cg_lsu_hazard = new();
    cg_opcode     = new();
    cg_operand    = new();
    cg_sign    = new();
    cg_memshape   = new();
    cg_ras        = new();
    cg_branch     = new();
    cg_muldiv     = new();
    cg_csr        = new();
    cg_isa_selftest = new();
    cg_exception    = new();
    cg_mstatus      = new();
    cg_mispredict_src = new();
    cg_branch_history = new();
    cg_irq_context    = new();
    cg_mem_axi        = new();
    cg_commit_slot    = new();
    cg_slot_class     = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(cpu_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("COV_ISA", "no cpu_cfg")

    probe = new[cfg.num_harts];
    for (int unsigned h = 0; h < cfg.num_harts; h++) begin
      string key = $sformatf("core_probe_vif_%0d", h);
      if (!uvm_config_db #(virtual core_probe_if)::get(this, "", key, probe[h]))
        `uvm_fatal("COV_ISA", $sformatf(
          {"no '%s'. mcause, mstatus and the predictor update are BOUND into ",
           "core, not carried on RVFI -- without the probe this model cannot ",
           "distinguish which trap fired or which predictor was wrong."}, key))
    end
    p0 = probe[0];
  endfunction

  task run_phase(uvm_phase phase);
    if (!cfg.cov_enable) return;
    forever begin
      @(posedge p0.clk);
      if (p0.rst_n !== 1'b1) continue;

      for (int unsigned h = 0; h < cfg.num_harts; h++) begin
        virtual core_probe_if ph = probe[h];
        bit mie  = ph.mstatus[3];
        bit mpie = ph.mstatus[7];

        if (ph.trap_taken && !last_trap[h]) begin
          cg_exception.sample(ph.trap_cause[31], int'(ph.trap_cause[30:0]));
          n_trap_binned++;
          if (ph.trap_cause[31]) irq_entry_pend[h] = 1;
        end
        last_trap[h] = ph.trap_taken;
        last_cause[h] = ph.trap_cause;
        cause_seen[h] = 1;

        if (mie != last_mie[h]) begin
          cg_mstatus.sample(mie, mpie, ph.mstatus[12:11], !mie);
          last_mie[h] = mie;
          n_mstatus_edge++;
        end

        for (int unsigned sl = 0; sl < COMMIT_W; sl++) begin
          int unsigned idx = (int'(ph.rob_head_id) + sl) % ROB_N;
          cg_commit_slot.sample(sl, ph.rob_viol[idx], h);
          if (ph.rob_viol[idx]) n_slot_marked[sl]++;
        end

        if (ph.bp_mispredict) begin
          int unsigned src;
          if      (ph.bp_ret)                     src = 0;   // RAS return
          else if (ph.bp_call)                    src = 1;   // call target
          else if (ph.bp_cf_type == CF_BRANCH)    src = 2;   // gshare direction
          else if (ph.bp_cf_type == CF_JALR)      src = 3;   // indirect target
          else                                    src = 4;   // direct target
          cg_mispredict_src.sample(src, h[0]);
          n_mispred[src]++;
        end
      end
    end
  endtask

  protected function int unsigned class_of(word_t insn);
    logic [6:0] op = insn[6:0];
    case (op)
      7'b0000011: return C_LOAD;                    // lb/lh/lw/lbu/lhu
      7'b0100011: return C_STORE;                   // sb/sh/sw
      7'b1100011: return C_BRANCH;                  // beq/bne/blt/bge/bltu/bgeu
      7'b1101111,                                   // jal
      7'b1100111: return C_JUMP;                    // jalr
      7'b1110011: return C_CSR;                     // system/CSR
      7'b0110011: return (insn[31:25] == 7'b0000001) ? C_MULDIV : C_ALU;
      7'b0010011,
      7'b0110111,
      7'b0010111: return C_ALU;                     // op-imm, lui, auipc
      default:    return C_OTHER;                   // fence, atomics, rest
    endcase
  endfunction

  protected function bit reads_rs1(word_t insn);
    logic [6:0] op = insn[6:0];
    return !(op inside {7'b0110111, 7'b0010111, 7'b1101111});  // lui/auipc/jal
  endfunction

  protected function bit reads_rs2(word_t insn);
    logic [6:0] op = insn[6:0];
    return (op inside {7'b0110011, 7'b0100011, 7'b1100011});   // R, store, branch
  endfunction

  virtual function void write_ci_rvfi(rvfi_txn t);
    int unsigned h, cls, hz;
    bit r1, r2;

    if (!cfg.cov_enable) return;
    h = t.hart;
    if (h >= NUM_HARTS) return;

    cls = class_of(t.insn);
    r1  = reads_rs1(t.insn);
    r2  = reads_rs2(t.insn);

    hz = HZ_NONE;
    if (prev_valid[h]) begin
      if ((prev_rd[h] != 5'd0) &&
          ((r1 && (t.rs1_addr == prev_rd[h])) || (r2 && (t.rs2_addr == prev_rd[h]))))
        hz = HZ_RAW;
      else if ((t.rd_addr != 5'd0) &&
               ((t.rd_addr == prev_rs1[h]) || (t.rd_addr == prev_rs2[h])))
        hz = HZ_WAR;
      else if ((t.rd_addr != 5'd0) && (t.rd_addr == prev_rd[h]))
        hz = HZ_WAW;
    end

    cg_hazard.sample(hz, cls, h);
    n_sampled++;
    case (hz)
      HZ_RAW:  n_raw++;
      HZ_WAR:  n_war++;
      HZ_WAW:  n_waw++;
      default: n_none++;
    endcase

    sample_lsu(t, h);
    sample_stateless(t, cls, r1, r2);

    prev_valid[h] = 1;
    prev_rd[h]    = t.rd_addr;
    prev_rs1[h]   = r1 ? t.rs1_addr : 5'd0;
    prev_rs2[h]   = r2 ? t.rs2_addr : 5'd0;
    prev_class[h] = cls;
  endfunction

  virtual function void write_ci_mem(mem_txn t);
    int unsigned      lat_b;
    longint unsigned  lat_c;
    if (!cfg.cov_enable) return;

    lat_c = t.observed_latency();
    if (lat_c < n_lat_min) n_lat_min = int'(lat_c);
    if (lat_c > n_lat_max) n_lat_max = int'(lat_c);

    if      (lat_c <= 1)  lat_b = 0;
    else if (lat_c <= 8)  lat_b = 1;
    else if (lat_c <= 20) lat_b = 2;
    else                  lat_b = 3;

    cg_mem_axi.sample(int'(t.len), t.size, t.burst, t.resp,
                      (t.dir == MEM_WRITE), lat_b);
    n_mem_txn++;

    if (t.burst != 2'd1) n_axi_bad_burst++;
    if (t.size  != 3'd2) n_axi_bad_size++;
    if (t.resp  == 2'd1) n_axi_exokay++;
  endfunction

  protected function int unsigned sign_of(word_t v);
    if (v == 32'd0)  return 0;          // zero
    if (v[31])       return 2;          // negative
    return 1;                           // positive
  endfunction

  protected function int unsigned region_of(word_t a);
    if (a >= 32'h8003_0000) return 2;                     // stack
    if (a >= 32'h8000_3000) return 1;                     // data
    if (a >= 32'h8000_0000) return 0;                     // text
    return 3;                                             // MMIO / elsewhere
  endfunction

  protected function int unsigned link_of(logic [4:0] r);
    if (r == 5'd1) return 1;            // ra
    if (r == 5'd5) return 5;            // t1 (the ISA's alternate link register)
    return 0;                           // non-link
  endfunction

  protected function void sample_stateless(rvfi_txn t, int unsigned cls,
                                           bit r1, bit r2);
    logic [6:0] op = t.insn[6:0];
    int unsigned sz, kind, dres;
    bit is_st;

    cg_opcode.sample(op, cls);

    cg_operand.sample(r1 ? t.rs1_addr : 5'd0,
                      r2 ? t.rs2_addr : 5'd0,
                      t.rd_addr,
                      r1 ? sign_of(t.rs1_rdata) : 0,
                      r2 ? sign_of(t.rs2_rdata) : 0,
                      (t.rd_addr != 0) ? sign_of(t.rd_wdata) : 0,
                      (r1 && r2) ? (t.rs1_rdata == t.rs2_rdata) : 1'b0,
                      (r1 && r2) ? ($signed(t.rs1_rdata) > $signed(t.rs2_rdata)) : 1'b0,
                      r1, r2, (t.rd_addr != 0));

    if (r1 && r2)
      cg_sign.sample(sign_of(t.rs1_rdata), sign_of(t.rs2_rdata));

    if (t.touched_mem()) begin
      is_st = t.is_mem_write();
      sz    = is_st ? $countones(t.mem_wmask) : $countones(t.mem_rmask);
      if (sz inside {1, 2, 4}) begin
        cg_memshape.sample(sz, t.mem_addr[1:0], is_st, region_of(t.mem_addr));
        if (region_of(t.mem_addr) == 3) begin
          if (n_region_outside == 0) first_region_outside = t.mem_addr;
          n_region_outside++;
        end
      end
      else begin
        n_bad_mask++;
      end
    end

    if (op inside {7'b1100111, 7'b1101111})   // jalr, jal
      cg_ras.sample(link_of(r1 ? t.rs1_addr : 5'd0), link_of(t.rd_addr),
                    (op == 7'b1101111));

    if (op == 7'b1100011) begin
      bit taken = (t.pc_wdata != (t.pc_rdata + 32'd4));
      cg_branch.sample(taken, (t.pc_wdata < t.pc_rdata), t.pc_wdata[1:0]);
      if (taken) n_br_taken++; else n_br_ntaken++;

      cg_branch_history.sample(br_hist[t.hart], taken);
      br_hist[t.hart] = {br_hist[t.hart][2:0], taken};
    end

    if ((op == 7'b0110011) && (t.insn[31:25] == 7'b0000001)) begin
      case (t.insn[14:12])
        3'b000:  kind = 0;                       // mul
        3'b001,
        3'b010,
        3'b011:  kind = 1;                       // mulh / mulhsu / mulhu
        3'b100,
        3'b101:  kind = 2;                       // div / divu
        default: kind = 3;                       // rem / remu
      endcase
      dres = 0;
      if (r2 && (t.rs2_rdata == 32'd0))                          dres = 1;
      else if (r1 && r2 && (t.rs1_rdata == 32'h8000_0000)
                        && (t.rs2_rdata == 32'hFFFF_FFFF))       dres = 2;
      cg_muldiv.sample(kind, dres);
      if (dres == 1) n_div_zero++;
    end

    if (irq_entry_pend[t.hart]) begin
      cg_irq_context.sample(prev_valid[t.hart] ? prev_class[t.hart] : C_OTHER,
                            1'b0);
      irq_entry_pend[t.hart] = 0;
      n_irq_ctx++;
    end
    if (irq_exit_pend[t.hart]) begin
      cg_irq_context.sample(cls, 1'b1);
      irq_exit_pend[t.hart] = 0;
      n_irq_ctx++;
    end
    if ((op == 7'b1110011) && (t.insn[14:12] == 3'b000) && (t.insn[31:20] == 12'h302))
      irq_exit_pend[t.hart] = 1;

    begin
      int unsigned sk;
      logic [2:0]  f3 = t.insn[14:12];
      if      ((op == 7'b1110011) && (f3 != 3'b000) && (f3 != 3'b100)) sk = 0;
      else if ((op == 7'b1110011) && (f3 == 3'b000)
                                 && (t.insn[31:20] == 12'h302))       sk = 0;
      else if  (op == 7'b0001111)                                     sk = 0;
      else if (t.touched_mem())               sk = 1;          // LSQ release
      else                                    sk = 2;
      if (t.slot < COMMIT_W) begin
        cg_slot_class.sample(t.slot, sk);
        if (t.slot == 1) begin
          n_slot1++;
          if (sk == 0) n_slot1_serialising++;
        end
      end
    end

    if ((op == 7'b1110011) && (t.insn[14:12] != 3'b000)) begin
      cg_csr.sample(t.insn[31:20]);
      n_csr++;
    end
  endfunction

  protected function void sample_lsu(rvfi_txn t, int unsigned h);
    bit cur_ld = t.is_mem_read();
    bit cur_st = t.is_mem_write();
    bit exact;
    int unsigned hz, idx;

    if (!(cur_ld || cur_st)) return;

    for (int unsigned k = 0; k < MEM_WIN; k++) begin
      idx = (mw_next[h] + MEM_WIN - 1 - k) % MEM_WIN;
      if (!mw_valid[h][idx]) continue;
      if (t.mem_addr[31:2] != mw_addr[h][idx][31:2]) continue;

      exact = (t.mem_addr == mw_addr[h][idx]);
      hz    = HZ_NONE;
      if      (mw_is_st[h][idx] && cur_ld) hz = HZ_RAW;  // store->load: FORWARDING
      else if (!mw_is_st[h][idx] && cur_st) hz = HZ_WAR; // load ->store
      else if (mw_is_st[h][idx] && cur_st) hz = HZ_WAW;  // store->store
      else break;                                        // load->load: no hazard

      n_lsu_pairs++;
      cg_lsu_hazard.sample(hz, !exact);
      case (hz)
        HZ_RAW: n_lsu_raw++;
        HZ_WAR: n_lsu_war++;
        HZ_WAW: n_lsu_waw++;
        default: ;
      endcase
      break;
    end

    mw_valid[h][mw_next[h]] = 1;
    mw_is_st[h][mw_next[h]] = cur_st;
    mw_addr [h][mw_next[h]] = t.mem_addr;
    mw_next [h]             = (mw_next[h] + 1) % MEM_WIN;
  endfunction

  function void report_phase(uvm_phase phase);
    real hz_i, lsu_i, self_i;

    if (!cfg.cov_enable) return;

    cg_isa_selftest.sample(0, 0, 1);
    cg_isa_selftest.sample(0, 1, 2);
    cg_isa_selftest.sample(1, 0, 1);
    cg_isa_selftest.sample(1, 1, 2);
    cg_isa_selftest.sample(1, 1, 0);   // guard FALSE: must not create a bin
    self_i = cg_isa_selftest.get_inst_coverage();
    `uvm_info("COV_ISA", $sformatf(
      "instrument self-test: %0.2f%% (must be 100.00)", self_i), UVM_LOW)
    if (self_i != 100.0)
      `uvm_error("COV_ISA", $sformatf(
        {"coverage SELF-TEST reads %0.2f%%, not 100%%. It samples a plain ",
         "coverpoint, a CROSS and an `iff`-guarded coverpoint -- the three ",
         "shapes this model is built from -- with values that hit every bin by ",
         "construction and no dependence on the DUT. This is the INSTRUMENT ",
         "failing, and EVERY figure below is meaningless until it reads 100."},
        self_i))

    hz_i  = cg_hazard.get_inst_coverage();
    lsu_i = cg_lsu_hazard.get_inst_coverage();

    `uvm_info("COV_ISA", $sformatf(
      "hazard %0.2f%%  lsu_hazard %0.2f%%", hz_i, lsu_i), UVM_LOW)
    `uvm_info("COV_ISA", $sformatf(
      "%0d retirements binned: RAW %0d, WAR %0d, WAW %0d, none %0d",
      n_sampled, n_raw, n_war, n_waw, n_none), UVM_LOW)
    `uvm_info("COV_ISA", $sformatf(
      {"memory hazards: store->load %0d, load->store %0d, store->store %0d, ",
       "over %0d same-word pair(s) examined. The pair count replaces the ",
       "deleted cp_lsu_hazard.none bin: it answers 'were any pairs examined at ",
       "all' without letting the ~95%% of instruction pairs that touch no ",
       "memory dominate the group's percentage."},
      n_lsu_raw, n_lsu_war, n_lsu_waw, n_lsu_pairs), UVM_LOW)

    `uvm_info("COV_ISA", $sformatf(
      "opcode %0.2f%%  operand %0.2f%%  memshape %0.2f%%  ras %0.2f%%  branch %0.2f%%  muldiv %0.2f%%  csr %0.2f%%",
      cg_opcode.get_inst_coverage(),   cg_operand.get_inst_coverage(),
      cg_memshape.get_inst_coverage(), cg_ras.get_inst_coverage(),
      cg_branch.get_inst_coverage(),   cg_muldiv.get_inst_coverage(),
      cg_csr.get_inst_coverage()), UVM_LOW)

    `uvm_info("COV_ISA", $sformatf(
      "branches %0d taken / %0d not-taken; %0d divide-by-zero; %0d CSR access(es)",
      n_br_taken, n_br_ntaken, n_div_zero, n_csr), UVM_LOW)

    `uvm_info("COV_ISA", $sformatf(
      "commit_slot %0.2f%%  -- marked entries seen at slot0 %0d, slot1 %0d",
      cg_commit_slot.get_inst_coverage(),
      n_slot_marked[0], (COMMIT_W > 1) ? n_slot_marked[1] : 0), UVM_LOW)

    `uvm_info("COV_ISA", $sformatf(
      "slot_class %0.2f%% -- %0d retirement(s) in commit slot 1",
      cg_slot_class.get_inst_coverage(), n_slot1), UVM_LOW)

    if (n_region_outside != 0)
      `uvm_error("COV_ISA", $sformatf(
        {"%0d data access(es) OUTSIDE THE LINKED IMAGE, first at %08h. ",
         "cluster.sv masks the data address to 18 bits, so this did not fault ",
         "-- it was ALIASED into the 256 KB image and wrote over whatever lives ",
         "there. That is the irq_mh.S hang (a handler storing to the CLINT at ",
         "0x0200_4000), and it is a PROGRAM defect, not stimulus."},
        n_region_outside, first_region_outside))

    if (n_slot1_serialising != 0)
      `uvm_error("COV_ISA", $sformatf(
        {"%0d serialising retirement(s) (CSR / mret / fence / fence.i) in ",
         "COMMIT SLOT 1. rob.sv:226 blocks these from any slot but 0 and makes ",
         "them the sole retirement of their cycle, because their side effects ",
         "are head-gated. This is a DESIGN finding, not stimulus."},
        n_slot1_serialising))

    if ((n_sampled > 1000) && (n_slot1 == 0))
      `uvm_error("COV_ISA", $sformatf(
        {"%0d retirements binned and NOT ONE in commit slot 1. This is a 2-wide ",
         "machine; either it never dual-issued, or rvfi_txn.slot is not being ",
         "carried. Cross-check against RVFI_MON dual-issue cycles."}, n_sampled))

    if ((n_axi_bad_burst != 0) || (n_axi_bad_size != 0) || (n_axi_exokay != 0))
      `uvm_error("COV_ISA", $sformatf(
        {"AXI transactions contradict axi_adapter.sv: %0d not BURST_INCR, %0d ",
         "not AXI_SIZE_4B, %0d EXOKAY. The adapter builds every request with ",
         "those constants (:150,:155) and axi4_pkg.sv:53 says EXOKAY is never ",
         "generated, so any of these is a design change nobody declared."},
        n_axi_bad_burst, n_axi_bad_size, n_axi_exokay))

    `uvm_info("COV_ISA", $sformatf(
      "mem_axi %0.2f%% over %0d transaction(s)",
      cg_mem_axi.get_inst_coverage(), n_mem_txn), UVM_LOW)

    if (n_mem_txn > 0)
      `uvm_info("COV_ISA", $sformatf(
        {"AXI first-beat latency: min %0d cycles, max %0d. cp_lat.immediate is ",
         "the <=1 bucket -- the fastest this fabric goes. A min above 1 means ",
         "that bucket is unreachable and the boundary is wrong, which is the ",
         "state it was in when it asked for 0."},
        n_lat_min, n_lat_max), UVM_LOW)

    if (n_mem_txn > 100)
      `uvm_info("COV_ISA",
        {"if cg_mem_axi's slverr/decerr bins are unhit, that is cpu_cfg's ",
         "slverr_percent never being set by any test -- a STIMULUS gap with a ",
         "named knob, not an unreachable bin."}, UVM_LOW)

    `uvm_info("COV_ISA", $sformatf(
      "branch_history %0.2f%%  irq_context %0.2f%% (%0d context sample(s))",
      cg_branch_history.get_inst_coverage(),
      cg_irq_context.get_inst_coverage(), n_irq_ctx), UVM_LOW)

    `uvm_info("COV_ISA", $sformatf(
      "exception %0.2f%%  mstatus %0.2f%%  mispredict_src %0.2f%%",
      cg_exception.get_inst_coverage(), cg_mstatus.get_inst_coverage(),
      cg_mispredict_src.get_inst_coverage()), UVM_LOW)
    `uvm_info("COV_ISA", $sformatf(
      "%0d trap cause(s) binned, %0d mstatus edge(s); mispredict source: RAS %0d, call %0d, gshare %0d, indirect %0d, direct %0d",
      n_trap_binned, n_mstatus_edge,
      n_mispred[0], n_mispred[1], n_mispred[2], n_mispred[3], n_mispred[4]), UVM_LOW)

    if ((n_mispred.sum() == 0) && (n_sampled > 1000))
      `uvm_warning("COV_ISA", $sformatf(
        {"%0d retirements and NOT ONE mispredict attributed to a predictor ",
         "structure. cp_rcause.mispredict may still be counting them -- if so ",
         "the classification here is wrong, not the predictor."}, n_sampled))

    if (n_bad_mask != 0)
      `uvm_error("COV_ISA", $sformatf(
        {"%0d memory access(es) reported a byte mask that is not 1, 2 or 4 bytes ",
         "wide. RV32I has no such access -- the mask is being built wrongly."},
        n_bad_mask))

    if ((n_sampled > 1000) && (n_waw == 0))
      `uvm_info("COV_ISA", $sformatf(
        {"no adjacent WAW in %0d retirements. Expected of compiled code -- an ",
         "adjacent WAW is a dead write. Hit it from hand-written assembly."},
        n_sampled), UVM_LOW)

    if ((n_sampled > 1000) && (n_raw == 0))
      `uvm_error("COV_ISA", $sformatf(
        {"%0d retirements binned and NOT ONE register RAW hazard. This core ",
         "renames, bypasses and speculates loads specifically to handle those. ",
         "Either the hazard derivation is wrong or the programs are unlike any ",
         "compiled code -- both are findings."}, n_sampled))

    if ((n_sampled > 1000) && (n_lsu_raw + n_lsu_war + n_lsu_waw == 0))
      `uvm_warning("COV_ISA", $sformatf(
        {"%0d retirements and no same-word memory hazard of any kind. The ",
         "store-to-load forwarding path and the violation CAM were not ",
         "exercised; defect 2d-4 lived exactly there and its fix has no ",
         "coverage witness in this run."}, n_sampled))
  endfunction

endclass
