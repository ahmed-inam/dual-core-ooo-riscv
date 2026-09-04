// Builds and connects the agents, scoreboard and reference model.

class axi4_env;

  virtual axi4_if #(.ID_W(ID_WIDTH)) m_vif[2];
  virtual axi4_if #(.ID_W(M_ID_W))   s_vif[2];

  axi4_mst_agent  m_agt[2];
  axi4_slv_agent  s_agt[2];
  axi4_ref_model  ref_m;
  axi4_scoreboard scb;

  protected mailbox #(axi4_txn) m_mon_mbx[2];
  protected mailbox #(axi4_txn) s_mon_mbx[2];

  function new(virtual axi4_if #(.ID_W(ID_WIDTH)) m0,
               virtual axi4_if #(.ID_W(ID_WIDTH)) m1,
               virtual axi4_if #(.ID_W(M_ID_W))   s0,
               virtual axi4_if #(.ID_W(M_ID_W))   s1);
    m_vif[0] = m0;  m_vif[1] = m1;
    s_vif[0] = s0;  s_vif[1] = s1;
  endfunction

  function void build();
    foreach (m_mon_mbx[i]) m_mon_mbx[i] = new();
    foreach (s_mon_mbx[i]) s_mon_mbx[i] = new();

    ref_m = new();
    scb   = new(m_mon_mbx, s_mon_mbx, ref_m);
    `TB_BUILD("axi4_env",        "ENV");
    `TB_BUILD("axi4_ref_model",  ref_m.name);
    `TB_BUILD("axi4_scoreboard", scb.name);

    foreach (m_agt[i]) begin
      m_agt[i] = new(m_vif[i], i);
      m_agt[i].build();
      m_agt[i].add_sub(m_mon_mbx[i]);
    end
    foreach (s_agt[i]) begin
      s_agt[i] = new(s_vif[i], i);
      s_agt[i].build();
      s_agt[i].add_sub(s_mon_mbx[i]);
    end
  endfunction

  task run();
    foreach (m_agt[i]) m_agt[i].run();
    foreach (s_agt[i]) s_agt[i].run();
    fork
      scb.run();
      issue_thread(0);
      issue_thread(1);
    join_none
  endtask

  protected task issue_thread(int m);
    forever begin
      axi4_txn t;
      m_agt[m].seq_out_mbx.get(t);
      scb.predict(m, t);
      m_agt[m].drv_in_mbx.put(t);
    end
  endtask

  function void flush();
    scb.flush();
  endfunction

  function bit idle();
    return (scb.outstanding() == 0);
  endfunction

  function void report();
    scb.report();
    ref_m.report();
  endfunction

endclass
