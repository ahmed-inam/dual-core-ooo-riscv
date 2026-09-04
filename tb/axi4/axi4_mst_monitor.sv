// Passive observer of one master interface.

class axi4_mst_monitor;

  virtual axi4_if #(.ID_W(ID_WIDTH)) vif;
  mailbox #(axi4_txn) subs[$];
  string name = "MST_MON";

  protected axi4_txn aw_q[$];
  protected axi4_txn w_q[$];
  protected axi4_txn pend_wr[logic [ID_WIDTH-1:0]][$];
  protected axi4_txn pend_rd[logic [ID_WIDTH-1:0]][$];

  int unsigned n_wr = 0, n_rd = 0;

  function new(virtual axi4_if #(.ID_W(ID_WIDTH)) vif);
    this.vif = vif;
  endfunction

  function void add_sub(mailbox #(axi4_txn) m);
    subs.push_back(m);
  endfunction

  protected function void publish(axi4_txn t);
    foreach (subs[i]) void'(subs[i].try_put(t.copy()));
  endfunction

  task run();
    forever begin
      wait (vif.arst_n === 1'b1);
      fork
        begin
          fork
            aw_thread();
            w_thread();
            b_thread();
            ar_thread();
            r_thread();
          join
        end
        @(negedge vif.arst_n);
      join_any
      disable fork;
      aw_q.delete();
      w_q.delete();
      pend_wr.delete();
      pend_rd.delete();
    end
  endtask

  task aw_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.awvalid && vif.awready) begin
        axi4_txn t = new();
        t.dir = WRITE;  t.id = vif.awid;    t.addr  = vif.awaddr;
        t.len = vif.awlen; t.size = vif.awsize; t.burst = vif.awburst;
        t.issued_at = $time;
        aw_q.push_back(t);
        join_wr();
      end
    end
  endtask

  task w_thread();
    axi4_txn cur = null;
    forever begin
      @(posedge vif.aclk);
      if (vif.wvalid && vif.wready) begin
        if (cur == null) cur = new();
        cur.data.push_back(vif.wdata);
        cur.strb.push_back(vif.wstrb);
        if (vif.wlast) begin
          w_q.push_back(cur);
          cur = null;
          join_wr();
        end
      end
    end
  endtask

  protected function void join_wr();
    while (aw_q.size() > 0 && w_q.size() > 0) begin
      axi4_txn a = aw_q.pop_front();
      axi4_txn w = w_q.pop_front();
      a.data = w.data;
      a.strb = w.strb;
      pend_wr[a.id].push_back(a);
    end
  endfunction

  task b_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.bvalid && vif.bready) begin
        if (pend_wr[vif.bid].size() == 0)
          begin $error("[%0t] [%s] B for id=%0d with nothing outstanding", $time, name, vif.bid); tb_mon_errors++; end
        else begin
          axi4_txn t = pend_wr[vif.bid].pop_front();
          t.resp    = vif.bresp;
          t.done_at = $time;
          n_wr++;
          publish(t);
          if (verbose) $display("[%0t] [%s] %s", $time, name, t.convert2str());
        end
      end
    end
  endtask

  task ar_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.arvalid && vif.arready) begin
        axi4_txn t = new();
        t.dir = READ;   t.id = vif.arid;    t.addr  = vif.araddr;
        t.len = vif.arlen; t.size = vif.arsize; t.burst = vif.arburst;
        t.issued_at = $time;
        pend_rd[t.id].push_back(t);
      end
    end
  endtask

  task r_thread();
    forever begin
      @(posedge vif.aclk);
      if (vif.rvalid && vif.rready) begin
        if (pend_rd[vif.rid].size() == 0)
          begin $error("[%0t] [%s] R beat for id=%0d with nothing outstanding", $time, name, vif.rid); tb_mon_errors++; end
        else begin
          axi4_txn t = pend_rd[vif.rid][0];
          t.data.push_back(vif.rdata);
          t.beat_resp.push_back(vif.rresp);
          t.beats_seen++;
          if (vif.rlast) begin
            void'(pend_rd[vif.rid].pop_front());
            t.resp    = vif.rresp;
            t.done_at = $time;
            n_rd++;
            publish(t);
            if (verbose) $display("[%0t] [%s] %s", $time, name, t.convert2str());
          end
        end
      end
    end
  endtask

  function int unsigned outstanding();
    int unsigned n = 0;
    foreach (pend_wr[i]) n += pend_wr[i].size();
    foreach (pend_rd[i]) n += pend_rd[i].size();
    return n + aw_q.size() + w_q.size();
  endfunction

endclass
