// Compares each observed transaction against the reference model.

class axi4_scoreboard;

  mailbox #(axi4_txn) mst_mbx[2];
  mailbox #(axi4_txn) slv_mbx[2];
  axi4_ref_model      ref_m;
  string name = "SCBD";

  protected axi4_txn wr_exp [2][16][$];
  protected axi4_txn rd_exp [2][16][$];

  int unsigned n_issued   = 0;
  int unsigned n_wr_done  = 0;
  int unsigned n_rd_done  = 0;
  int unsigned n_slv_seen = 0;
  int unsigned n_data_chk = 0;
  int unsigned n_held     = 0;
  int unsigned n_errors   = 0;
  int unsigned max_report  = 20;
  bit          stop_on_first = 0;

  function new(mailbox #(axi4_txn) mst_mbx[2],
               mailbox #(axi4_txn) slv_mbx[2],
               axi4_ref_model      ref_m);
    this.mst_mbx = mst_mbx;
    this.slv_mbx = slv_mbx;
    this.ref_m   = ref_m;
  endfunction

  protected function void err(string s);
    n_errors++;
    if (n_errors <= max_report) $display("[%0t] [%s] ERROR: %s", $time, name, s);
    if (stop_on_first) $fatal(1, "[%s] stopping at first error", name);
  endfunction

  function void predict(int m, axi4_txn t);
    if (!ref_m.admissible(m, t)) n_held++;
    ref_m.issue(m, t);
    if (t.dir == WRITE) wr_exp[m][t.id].push_back(t);
    else                rd_exp[m][t.id].push_back(t);
    n_issued++;
  endfunction

  task run();
    fork
      collect(0); collect(1);
      collect_slv(0); collect_slv(1);
    join
  endtask

  task collect(int m);
    forever begin
      axi4_txn o;
      mst_mbx[m].get(o);
      if (o.dir == WRITE) check_wr(m, o);
      else                check_rd(m, o);
    end
  endtask

  task check_wr(int m, axi4_txn o);
    axi4_txn e;
    if (wr_exp[m][o.id].size() == 0) begin
      err($sformatf("M%0d unexpected B id=%0d", m, o.id));
      return;
    end
    e = wr_exp[m][o.id].pop_front();
    if (o.resp !== ref_m.exp_resp(e))
      err($sformatf("M%0d id=%0d addr=%08h BRESP=%b expected %b",
                    m, o.id, e.addr, o.resp, ref_m.exp_resp(e)));
    ref_m.complete(m, e);
    n_wr_done++;
  endtask

  task check_rd(int m, axi4_txn o);
    axi4_txn e;
    if (rd_exp[m][o.id].size() == 0) begin
      err($sformatf("M%0d unexpected R id=%0d", m, o.id));
      return;
    end
    e = rd_exp[m][o.id].pop_front();

    if (o.resp !== ref_m.exp_resp(e))
      err($sformatf("M%0d id=%0d addr=%08h RRESP=%b expected %b",
                    m, o.id, e.addr, o.resp, ref_m.exp_resp(e)));

    if (o.beats_seen != e.n_beats())
      err($sformatf("M%0d id=%0d returned %0d beats, ARLEN implies %0d",
                    m, o.id, o.beats_seen, e.n_beats()));

    for (int i = 0; i < o.data.size() && i < e.n_beats(); i++) begin
      if (ref_m.data_checkable(e, i)) begin
        logic [DATA_WIDTH-1:0] mask = ref_m.beat_mask(e, i);
        logic [DATA_WIDTH-1:0] exp  = ref_m.mem_read(e.beat_addr(i));
        n_data_chk++;
        if ((o.data[i] & mask) !== (exp & mask))
          err($sformatf("M%0d id=%0d beat %0d addr=%08h RDATA=%08h expected %08h (mask %08h)",
                        m, o.id, i, e.beat_addr(i), o.data[i], exp, mask));
      end
    end

    ref_m.complete(m, e);
    n_rd_done++;
  endtask

  task collect_slv(int s);
    forever begin
      axi4_txn o;
      slv_mbx[s].get(o);
      n_slv_seen++;
      if (o.dest() != ((s == 0) ? DEST_S0_T : DEST_S1_T))
        err($sformatf("S%0d received addr=%08h which decodes elsewhere", s, o.addr));
      if (o.dir == WRITE) ref_m.mem_write(o);
    end
  endtask

  function int unsigned outstanding();
    int unsigned n = 0;
    for (int m = 0; m < 2; m++)
      for (int i = 0; i < 16; i++) begin
        n += wr_exp[m][i].size();
        n += rd_exp[m][i].size();
      end
    return n;
  endfunction

  function void flush();
    for (int m = 0; m < 2; m++)
      for (int i = 0; i < 16; i++) begin
        wr_exp[m][i].delete();
        rd_exp[m][i].delete();
      end
    ref_m.reset();
  endfunction

  function void report();
    $display("--------------------------------------------------");
    $display("[%s] issued=%0d wr_done=%0d rd_done=%0d slv_seen=%0d data_checks=%0d held=%0d",
             name, n_issued, n_wr_done, n_rd_done, n_slv_seen, n_data_chk, n_held);
    $display("[%s] outstanding=%0d errors=%0d", name, outstanding(), n_errors);
    if (n_errors == 0 && outstanding() == 0) $display("[%s] RESULT: PASS", name);
    else                                     $display("[%s] RESULT: FAIL", name);
    $display("--------------------------------------------------");
  endfunction

endclass
