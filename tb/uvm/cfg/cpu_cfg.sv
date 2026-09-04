// One configuration object for the whole environment.
class cpu_cfg extends uvm_object;
  `uvm_object_utils(cpu_cfg)

  int unsigned num_harts = NUM_HARTS;

  string hex_path      = "";                 // +HEX=
  string elf_path      = "";                 // +ELF=, for Spike (may differ in format)
  word_t tohost_addr   = 32'h8000_1000;      // +TOHOST=, matches tb_dual_ooo default

  word_t expected_tohost = 32'h0000_0001;

  bit          randomize_latency = 1'b1;

  int unsigned fixed_delay       = 10;       // == +DELAY=10      when randomize_latency=0
  int unsigned fixed_beat_delay  = 1;        // == +BEAT_DELAY=1

  rand int unsigned lat_min = 0,  lat_max = 32;   // first-beat latency window
  rand int unsigned gap_min = 0,  gap_max = 4;    // inter-beat gap window

  constraint c_lat  { soft lat_min == 0;  soft lat_max == 32; lat_min <= lat_max; }
  constraint c_gap  { soft gap_min == 0;  soft gap_max == 4;  gap_min <= gap_max; }

  bit          reorder_responses  = 1'b0;
  int unsigned slverr_percent     = 0;       // fault injection, off by default
  word_t       slverr_lo          = 32'h0;   // inject only at or above this address

  int unsigned w_stall_percent = 25;

  word_t       clint_base   = 32'h0200_0000; // mem_pkg::CLINT_BASE
  int unsigned rtc_period   = 100;           // sim cycles per mtime increment

  typedef enum bit { REF_SPIKE, REF_QEMU } ref_sel_e;
  ref_sel_e ref_model  = REF_SPIKE;

  bit use_ref_model = 1'b1;
  string    spike_path = "/opt/spike/bin/spike";

  string ref_isa = "rv32im_zicsr";

  typedef enum bit { CMP_FREERUN, CMP_MERGED } cmp_mode_e;
  cmp_mode_e cmp_mode = CMP_FREERUN;

  word_t trunc_pc     = 32'h0;   // +TRUNC_PC=   -- park_forever
  word_t trunc_pc_alt = 32'h0;   // +TRUNC_PC2=  -- _f3_barrier_begin, gate-exact only

  function bit is_trunc_pc(word_t pc);
    return (trunc_pc     != 0 && pc == trunc_pc)
        || (trunc_pc_alt != 0 && pc == trunc_pc_alt);
  endfunction

  function bit trunc_enabled();
    return (trunc_pc != 0) || (trunc_pc_alt != 0);
  endfunction

  bit cov_enable = 1'b1;

  bit cov_assert_type_inst_differ = 1'b1;

  longint unsigned timeout_cycles = 2_000_000;

  int unsigned min_quiescence_samples = 100;

  int unsigned max_load_deferrals = 50;

  int unsigned min_rvfi_matches_hart0 = 99;
  int unsigned min_rvfi_matches_hart1 = 99;

  function new(string name = "cpu_cfg");
    super.new(name);
  endfunction

  function void apply_plusargs();
    string  s;
    int     i;
    if ($value$plusargs("HEX=%s",    s)) hex_path    = s;
    if ($value$plusargs("ELF=%s",    s)) elf_path    = s;
    if ($value$plusargs("TOHOST=%h", tohost_addr)) ;
    if ($value$plusargs("DELAY=%d",  i)) begin
      fixed_delay = i; randomize_latency = 0;   // an explicit +DELAY means determinism
    end
    if ($value$plusargs("BEAT_DELAY=%d", i)) begin
      fixed_beat_delay = i; randomize_latency = 0;
    end
    if ($test$plusargs("RAND_LATENCY")) randomize_latency = 1;  // wins over the above
    if ($value$plusargs("TRUNC_PC=%h",  trunc_pc)) ;
    if ($value$plusargs("TRUNC_PC2=%h", trunc_pc_alt)) ;
    if ($test$plusargs("MERGED")) cmp_mode = CMP_MERGED;

    if ($value$plusargs("FLOOR_H0=%d", i))    min_rvfi_matches_hart0 = i;
    if ($value$plusargs("FLOOR_H1=%d", i))    min_rvfi_matches_hart1 = i;
    if ($value$plusargs("FLOOR_QUIES=%d", i)) min_quiescence_samples = i;
    if ($value$plusargs("FLOOR_DEFER=%d", i)) max_load_deferrals     = i;
    if ($value$plusargs("FLOOR_TIMEOUT=%d", i)) timeout_cycles       = i;
    if ($value$plusargs("REF=%d", i))   use_ref_model = (i != 0);   // override a test's choice
    if ($value$plusargs("SPIKE=%s", s)) spike_path    = s;
  endfunction

  function void check_valid();
    if (hex_path == "")
      `uvm_fatal("CPU_CFG", "no program image: pass +HEX=<file>")
    if (randomize_latency && (lat_min > lat_max))
      `uvm_fatal("CPU_CFG", $sformatf("lat_min %0d > lat_max %0d", lat_min, lat_max))

    if (randomize_latency && (lat_max == 0) && (gap_max == 0))
      `uvm_error("CPU_CFG",
        {"randomize_latency=1 but the window is [0:0] -- the memory will answer ",
         "with ZERO latency on every transaction. That is the one timing regime ",
         "least likely to expose a memory-speculation defect. Set the window, or ",
         "set randomize_latency=0 with fixed_delay=0 to ask for this on purpose."})
    if (min_quiescence_samples == 0)
      `uvm_warning("CPU_CFG",
        "min_quiescence_samples=0: sb_coherence can pass without ever sampling")
  endfunction

  virtual function string convert2string();
    return $sformatf(
      {"cpu_cfg: harts=%0d hex=%s tohost=%08h\n",
       "  memory: %s\n",
       "  clint_base=%08h rtc_period=%0d  ref=%s  cov=%0b\n",
       "  floors: quiescence>=%0d  rvfi h0>=%0d h1>=%0d  timeout=%0d"},
      num_harts, hex_path, tohost_addr,
      randomize_latency
        ? $sformatf("random lat=[%0d:%0d] gap=[%0d:%0d] reorder=%0b slverr=%0d%%",
                    lat_min, lat_max, gap_min, gap_max, reorder_responses, slverr_percent)
        : $sformatf("fixed delay=%0d beat_delay=%0d", fixed_delay, fixed_beat_delay),
      clint_base, rtc_period,
      $sformatf("%s/%s%s%s", ref_model.name(), cmp_mode.name(),
                (cmp_mode == CMP_FREERUN && trunc_pc != 0)
                  ? $sformatf(" trunc@%08h", trunc_pc) : "",
                (cmp_mode == CMP_FREERUN && trunc_pc_alt != 0)
                  ? $sformatf("+%08h", trunc_pc_alt) : ""),
      cov_enable,
      min_quiescence_samples, min_rvfi_matches_hart0, min_rvfi_matches_hart1,
      timeout_cycles);
  endfunction

endclass
