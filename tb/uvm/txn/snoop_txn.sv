// ONE COHERENCE TRANSACTION, request through completion.
class snoop_txn extends uvm_sequence_item;
  `uvm_object_utils(snoop_txn)

  int unsigned  req_hart;
  coh_req_e     req_type;     // REQ_GETS / REQ_GETM / REQ_UPGRADE / REQ_PUTM
  word_t        req_addr;
  bit           req_atomic;   // LR write-intent: an LR that needs
  bit           granted;

  bit                      snp_sent;
  coh_snoop_e              snp_type;                 // SNP_TO_S / SNP_TO_I
  bit [NUM_HARTS-1:0]      snp_targets;              // who was snooped
  bit [NUM_HARTS-1:0]      snp_acked;
  coh_rsp_e                snp_rsp [NUM_HARTS];      // per-hart response

  bit           completed;
  bit           cmp_shared;   // does anyone else still hold a copy?
  bit           cmp_dirty;    // was dirty data supplied?
  bit           installed;

  bit           prot_deferred;
  bit           ord_violation;

  bit [NUM_HARTS-1:0] lr_valid;
  bit [NUM_HARTS-1:0] sc_valid;
  bit [NUM_HARTS-1:0] sc_success;
  bit [NUM_HARTS-1:0] rsv_valid;
  bit [NUM_HARTS-1:0] backing_off;   // rocket lrscBackingOff -- the 6.9 escape
  bit [NUM_HARTS-1:0] snoop_clear;   // a snoop killed a reservation
  bit [NUM_HARTS-1:0] trap_clear;    // a trap killed a reservation
  word_t              acc_addr [NUM_HARTS];
  word_t              prot_addr [NUM_HARTS];

  longint unsigned t_req, t_snp, t_cmp;

  function new(string name = "snoop_txn");
    super.new(name);
  endfunction

  function bit is_quiescent();
    return completed && installed
           && (snp_targets == '0 || snp_acked == snp_targets);
  endfunction

  function bit snoop_hit_reservation();
    if (!snp_sent) return 1'b0;
    for (int unsigned h = 0; h < NUM_HARTS; h++)
      if (rsv_valid[h] && snp_targets[h]
          && (req_addr >> OFF_W) == (prot_addr[h] >> OFF_W))
        return 1'b1;
    return 1'b0;
  endfunction

  function bit snoop_touched_any_reservation();
    return snp_sent && ((rsv_valid & snp_targets) != '0);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    snoop_txn r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal("SNOOP_TXN", "do_copy: type mismatch")
    req_hart = r.req_hart; req_type = r.req_type; req_addr = r.req_addr;
    req_atomic = r.req_atomic; granted = r.granted;
    snp_sent = r.snp_sent; snp_type = r.snp_type;
    snp_targets = r.snp_targets; snp_acked = r.snp_acked;
    foreach (r.snp_rsp[i]) snp_rsp[i] = r.snp_rsp[i];
    completed = r.completed; cmp_shared = r.cmp_shared;
    cmp_dirty = r.cmp_dirty; installed = r.installed;
    prot_deferred = r.prot_deferred; ord_violation = r.ord_violation;
    lr_valid = r.lr_valid; sc_valid = r.sc_valid; sc_success = r.sc_success;
    rsv_valid = r.rsv_valid; backing_off = r.backing_off;
    prot_addr = r.prot_addr;
    snoop_clear = r.snoop_clear; trap_clear = r.trap_clear;
    foreach (r.acc_addr[i]) acc_addr[i] = r.acc_addr[i];
    t_req = r.t_req; t_snp = r.t_snp; t_cmp = r.t_cmp;
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    snoop_txn r;
    if (!$cast(r, rhs)) return 0;
    if (req_hart !== r.req_hart || req_type !== r.req_type) return 0;
    if (req_addr !== r.req_addr || req_atomic !== r.req_atomic) return 0;
    if (snp_sent !== r.snp_sent) return 0;
    if (snp_sent && (snp_type !== r.snp_type || snp_targets !== r.snp_targets)) return 0;
    foreach (snp_rsp[i]) if (snp_targets[i] && snp_rsp[i] !== r.snp_rsp[i]) return 0;
    if (cmp_shared !== r.cmp_shared || cmp_dirty !== r.cmp_dirty) return 0;
    return 1;
  endfunction

  virtual function string convert2string();
    string s;
    s = $sformatf("h%0d %s addr=%08h%s%s", req_hart, req_type.name(), req_addr,
                  req_atomic ? " ATOMIC" : "", granted ? "" : " (ungranted)");
    if (snp_sent) begin
      s = {s, $sformatf(" | snoop %s to %b:", snp_type.name(), snp_targets)};
      foreach (snp_rsp[i]) if (snp_targets[i]) s = {s, $sformatf(" h%0d=%s", i, snp_rsp[i].name())};
    end
    if (completed)
      s = {s, $sformatf(" | shared=%0b dirty=%0b", cmp_shared, cmp_dirty)};
    if (snoop_hit_reservation())
      s = {s, $sformatf(" | SNOOP-IN-RSV-WINDOW rsv=%b", rsv_valid)};
    if (ord_violation) s = {s, " | DUT-REPORTS-ORD-VIOLATION"};
    return s;
  endfunction

endclass
