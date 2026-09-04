// Predicts what a transaction should produce.

class axi4_ref_model;

  string name = "REF";

  typedef struct {
    logic [ID_WIDTH-1:0] id;
    tdest_e              dest;
    int unsigned         count;
  } thread_t;

  protected thread_t wr_thr [2][NUM_THREADS];
  protected thread_t rd_thr [2][NUM_THREADS];

  int unsigned n_pred = 0;
  int unsigned n_wr_beats = 0;

  protected logic [7:0] mem [logic [ADDR_WIDTH-1:0]];

  protected int epoch = 0;
  protected int last_wr  [logic [ADDR_WIDTH-1:0]];
  protected int inflight [logic [ADDR_WIDTH-1:0]];

  int unsigned n_outstanding [2][2];
  int unsigned max_outstanding_seen = 0;
  int unsigned n_data_skip  = 0;

  function logic [1:0] exp_resp(axi4_txn t);
    return (t.dest() == DEST_BAD) ? RESP_DECERR : RESP_OKAY;
  endfunction

  function logic exp_tag(int m);
    return m[0];
  endfunction

  function bit admissible(int m, axi4_txn t);
    thread_t thr[NUM_THREADS] = (t.dir == WRITE) ? wr_thr[m] : rd_thr[m];
    bit all_busy = 1;
    foreach (thr[i]) begin
      if (thr[i].count != 0 && thr[i].id == t.id)
        return (thr[i].dest == t.dest());
      if (thr[i].count == 0) all_busy = 0;
    end
    return !all_busy;
  endfunction

  function int unsigned lane_of(logic [ADDR_WIDTH-1:0] a);
    return a[$clog2(STRB_WIDTH)-1:0];
  endfunction

  function logic [ADDR_WIDTH-1:0] word_of(logic [ADDR_WIDTH-1:0] a);
    return a & ~(ADDR_WIDTH'(STRB_WIDTH - 1));
  endfunction

  function void mem_write(axi4_txn t);
    for (int i = 0; i < t.n_beats() && i < t.data.size(); i++) begin
      logic [ADDR_WIDTH-1:0] a    = t.beat_addr(i);
      int unsigned           lane = lane_of(a);
      int unsigned           nb   = 1 << t.size;
      for (int b = 0; b < nb; b++)
        if (t.strb[i][lane + b])
          mem[word_of(a) + lane + b] = t.data[i][8*(lane + b) +: 8];
      n_wr_beats++;
    end
  endfunction

  function logic [DATA_WIDTH-1:0] mem_read(logic [ADDR_WIDTH-1:0] a);
    logic [ADDR_WIDTH-1:0] w = word_of(a);
    mem_read = '0;
    for (int b = 0; b < STRB_WIDTH; b++)
      mem_read[8*b +: 8] = mem.exists(w + b) ? mem[w + b] : 8'hDE;
  endfunction

  function logic [DATA_WIDTH-1:0] beat_mask(axi4_txn t, int unsigned beat);
    int unsigned lane = lane_of(t.beat_addr(beat));
    int unsigned nb   = 1 << t.size;
    beat_mask = '0;
    for (int b = 0; b < nb; b++)
      if (beat < t.strb.size() ? t.strb[beat][lane + b] : 1'b1)
        beat_mask[8*(lane + b) +: 8] = 8'hFF;
  endfunction

  protected function void stamp(axi4_txn t);
    epoch++;
    for (int i = 0; i < t.n_beats(); i++) begin
      logic [ADDR_WIDTH-1:0] x = word_of(t.beat_addr(i));
      last_wr[x] = epoch;
      if (!inflight.exists(x)) inflight[x] = 0;
      inflight[x]++;
    end
  endfunction

  protected function void unstamp(axi4_txn t);
    for (int i = 0; i < t.n_beats(); i++) begin
      logic [ADDR_WIDTH-1:0] x = word_of(t.beat_addr(i));
      if (inflight.exists(x)) begin
        inflight[x]--;
        if (inflight[x] <= 0) inflight.delete(x);
      end
    end
  endfunction

  protected function bit any_inflight(axi4_txn t);
    for (int i = 0; i < t.n_beats(); i++)
      if (inflight.exists(word_of(t.beat_addr(i)))) return 1;
    return 0;
  endfunction

  function bit data_checkable(axi4_txn t, int unsigned beat);
    logic [ADDR_WIDTH-1:0] a = word_of(t.beat_addr(beat));
    if (exp_resp(t) != RESP_OKAY) return 0;
    if (t.poisoned) begin n_data_skip++; return 0; end
    if (inflight.exists(a)) begin n_data_skip++; return 0; end
    if (last_wr.exists(a) && last_wr[a] >  t.issue_epoch) begin n_data_skip++; return 0; end
    return 1;
  endfunction

  function void issue(int m, axi4_txn t);
    int slot = -1;
    if (t.dir == WRITE) begin
      for (int i = 0; i < NUM_THREADS; i++)
        if (wr_thr[m][i].count != 0 && wr_thr[m][i].id == t.id) slot = i;
      if (slot < 0)
        for (int i = 0; i < NUM_THREADS; i++)
          if (wr_thr[m][i].count == 0 && slot < 0) slot = i;
      if (slot >= 0) begin
        wr_thr[m][slot].id   = t.id;
        wr_thr[m][slot].dest = t.dest();
        wr_thr[m][slot].count++;
      end
    end
    else begin
      for (int i = 0; i < NUM_THREADS; i++)
        if (rd_thr[m][i].count != 0 && rd_thr[m][i].id == t.id) slot = i;
      if (slot < 0)
        for (int i = 0; i < NUM_THREADS; i++)
          if (rd_thr[m][i].count == 0 && slot < 0) slot = i;
      if (slot >= 0) begin
        rd_thr[m][slot].id   = t.id;
        rd_thr[m][slot].dest = t.dest();
        rd_thr[m][slot].count++;
      end
    end
    t.tag         = exp_tag(m);
    t.resp        = exp_resp(t);
    t.issue_epoch = epoch;
    t.poisoned    = (t.dir == READ) ? any_inflight(t) : 1'b0;
    if (t.dir == WRITE && t.dest() != DEST_BAD) stamp(t);

    n_outstanding[m][int'(t.dir)]++;
    if (n_outstanding[m][int'(t.dir)] > max_outstanding_seen)
      max_outstanding_seen = n_outstanding[m][int'(t.dir)];
    n_pred++;
  endfunction

  function void complete(int m, axi4_txn t);
    if (n_outstanding[m][int'(t.dir)] > 0) n_outstanding[m][int'(t.dir)]--;

    if (t.dir == WRITE && t.dest() != DEST_BAD) unstamp(t);

    if (t.dir == WRITE) begin
      for (int i = 0; i < NUM_THREADS; i++)
        if (wr_thr[m][i].count != 0 && wr_thr[m][i].id == t.id) begin
          wr_thr[m][i].count--;
          return;
        end
      ;
    end
    else begin
      for (int i = 0; i < NUM_THREADS; i++)
        if (rd_thr[m][i].count != 0 && rd_thr[m][i].id == t.id) begin
          rd_thr[m][i].count--;
          return;
        end
      ;
    end
  endfunction

  function int unsigned dests_outstanding(int m, dir_e d);
    bit      seen[3];
    thread_t thr[NUM_THREADS] = (d == WRITE) ? wr_thr[m] : rd_thr[m];
    int unsigned n = 0;
    foreach (thr[i]) if (thr[i].count != 0) seen[int'(thr[i].dest)] = 1;
    foreach (seen[i]) if (seen[i]) n++;
    return n;
  endfunction

  function void reset();
    for (int m = 0; m < 2; m++) begin
      for (int i = 0; i < NUM_THREADS; i++) begin
        wr_thr[m][i].count = 0;
        rd_thr[m][i].count = 0;
      end
      n_outstanding[m][0] = 0;
      n_outstanding[m][1] = 0;
    end
    inflight.delete();
  endfunction

  function void report();
    $display("[%s] predictions=%0d wr_beats=%0d peak_outstanding=%0d data_skipped=%0d",
             name, n_pred, n_wr_beats, max_outstanding_seen, n_data_skip);
  endfunction

endclass
