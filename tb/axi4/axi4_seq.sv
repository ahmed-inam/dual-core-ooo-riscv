// Transaction generator: one class configured by fields, not by subclassing.

class axi4_seq;

  mailbox #(axi4_txn) seq_mbx;
  string name = "SEQ";

  int unsigned n_items   = 1;
  bit          directed  = 0;

  dir_e        dir       = WRITE;
  bit          mixed_dir = 0;

  logic [ADDR_WIDTH-1:0] addr_q[$];
  logic [ID_WIDTH-1:0]   id_q[$];
  logic [7:0]            len_q[$];
  logic [2:0]            size_q[$];
  logic [1:0]            burst_q[$];
  dir_e                  dir_q[$];
  int unsigned           delay_q[$];

  int unsigned id_pool   = 3;
  int unsigned id_base   = 1;

  int unsigned w_s0      = 45;
  int unsigned w_s1      = 30;
  int unsigned w_bad     = 25;
  bit          force_s0  = 0;

  int unsigned w_incr    = 70;
  int unsigned w_wrap    = 20;

  int unsigned max_delay = 0;
  int unsigned unaligned_pct = 0;   // percent of INCR bursts with an unaligned start
  int unsigned seed_base = 32'hC0DE_0000;

  int unsigned addr_word_base = 0;
  int unsigned addr_word_cnt  = 1024;

  function new(mailbox #(axi4_txn) seq_mbx);
    this.seq_mbx = seq_mbx;
  endfunction

  function void push(dir_e d, logic [ID_WIDTH-1:0] id, logic [ADDR_WIDTH-1:0] addr,
                     logic [7:0] len = 8'd0, logic [2:0] size = 3'd2,
                     logic [1:0] burst = 2'b01, int unsigned delay = 0);
    directed = 1;
    dir_q.push_back(d);
    id_q.push_back(id);
    addr_q.push_back(addr);
    len_q.push_back(len);
    size_q.push_back(size);
    burst_q.push_back(burst);
    delay_q.push_back(delay);
    n_items = addr_q.size();
  endfunction

  function void push_burst_stream(dir_e d, logic [ID_WIDTH-1:0] id,
                                  logic [ADDR_WIDTH-1:0] base, int n,
                                  logic [7:0] len = 8'd1,
                                  int unsigned stride = 64);
    for (int i = 0; i < n; i++) push(d, id, base + i*stride, len);
  endfunction

  function void clear();
    addr_q.delete(); id_q.delete(); len_q.delete();
    size_q.delete(); burst_q.delete(); dir_q.delete(); delay_q.delete();
    n_items  = 0;
    directed = 0;
  endfunction

  task run();
    if (directed) begin
      assert (addr_q.size() >= n_items && id_q.size() >= n_items)
        else $fatal(1, "[%s] directed needs addr_q and id_q of at least %0d", name, n_items);
    end

    for (int i = 0; i < n_items; i++) begin
      axi4_txn t = new();
      if (directed) build_directed(t, i);
      else          build_random(t);
      t.fill_incr_data(seed_base);
      seq_mbx.put(t);
      if (verbose) $display("[%0t] [%s] sent %s", $time, name, t.convert2str());
    end
  endtask

  function void build_directed(axi4_txn t, int i);
    t.addr  = addr_q[i];
    t.id    = id_q[i];
    t.len   = (len_q.size()   > i) ? len_q[i]   : 8'd0;
    t.size  = (size_q.size()  > i) ? size_q[i]  : 3'd2;
    t.burst = (burst_q.size() > i) ? burst_q[i] : 2'b01;
    t.dir   = (dir_q.size()   > i) ? dir_q[i]   : dir;
    t.delay = (delay_q.size() > i) ? delay_q[i] : 0;
    t.make_legal();
  endfunction

  function void build_random(axi4_txn t);
    int r;
    t.id = id_base + $urandom_range(0, id_pool - 1);

    r = $urandom_range(0, 99);
    if (force_s0)                 t.addr = S0_BASE;
    else if (r < w_s0)            t.addr = S0_BASE;
    else if (r < w_s0 + w_s1)     t.addr = S1_BASE;
    else                          t.addr = BAD_BASE;
    t.addr |= ((addr_word_base + $urandom_range(0, addr_word_cnt - 1)) << 2);
    if (slverr_window && $urandom_range(0, 4) == 0)
      t.addr |= 32'h0400_0000;                             // into the SLVERR window

    r = $urandom_range(0, 99);
    t.burst = (r < w_incr) ? 2'b01 : (r < w_incr + w_wrap) ? 2'b10 : 2'b00;

    r = $urandom_range(0, 99);
    t.size = (r < 70) ? 3'd2 : (r < 85) ? 3'd1 : 3'd0;

    r = $urandom_range(0, 99);
    if      (r < 30) t.len = 8'd0;
    else if (r < 60) t.len = 8'($urandom_range(1, 7));
    else if (r < 80) t.len = 8'($urandom_range(8, 31));
    else             t.len = 8'($urandom_range(32, 80));

    t.dir   = mixed_dir ? (($urandom_range(0,1)) ? WRITE : READ) : dir;
    t.delay = $urandom_range(0, max_delay);
    if (t.burst == 2'b01 && $urandom_range(1, 100) <= unaligned_pct)
      t.addr |= $urandom_range(1, (1 << t.size) - 1);      // unaligned INCR start
    t.make_legal();
  endfunction

endclass
