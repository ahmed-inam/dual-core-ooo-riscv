// Samples one hart's retirement stream.
class rvfi_monitor extends uvm_monitor;
  `uvm_component_utils(rvfi_monitor)

  virtual rvfi_if vif;
  int unsigned    hart_id;
  int             clk_period_ns = 10;

  uvm_analysis_port #(rvfi_txn) ap;

  int unsigned n_retired;
  int unsigned n_trapped;
  int unsigned n_dual_issue;   // cycles where BOTH slots retired

  int unsigned n_mem_read;
  int unsigned n_mem_write;
  int unsigned n_intr;

  int unsigned n_trap_without_valid;

  logic [63:0] last_order;
  bit          seen_any;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual rvfi_if)::get(this, "", "vif", vif))
      `uvm_fatal("RVFI_MON", $sformatf("no virtual interface for hart %0d", hart_id))
    void'(uvm_config_db #(int)::get(this, "", "clk_period_ns", clk_period_ns));
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);

      if (vif.rst_n !== 1'b1) begin
        seen_any = 0;   // a new reset restarts the order sequence
        continue;
      end

      if ($countones(vif.valid) > 1) n_dual_issue++;

      for (int unsigned s = 0; s < COMMIT_W; s++) begin
        if (vif.valid[s]) begin
          rvfi_txn t = rvfi_txn::type_id::create("t");
          t.hart     = hart_id;
          t.slot     = s;
          t.order    = vif.order[s];
          t.insn     = vif.insn[s];
          t.pc_rdata = vif.pc_rdata[s];
          t.rd_addr  = vif.rd_addr[s];
          t.rd_wdata = vif.rd_wdata[s];
          t.trap     = vif.trap[s];
          t.halt      = vif.halt[s];
          t.intr      = vif.intr[s];
          t.mode      = vif.mode[s];
          t.ixl       = vif.ixl[s];
          t.rs1_addr  = vif.rs1_addr[s];
          t.rs2_addr  = vif.rs2_addr[s];
          t.rs1_rdata = vif.rs1_rdata[s];
          t.rs2_rdata = vif.rs2_rdata[s];
          t.pc_wdata  = vif.pc_wdata[s];
          t.mem_addr  = vif.mem_addr[s];
          t.mem_rmask = vif.mem_rmask[s];
          t.mem_wmask = vif.mem_wmask[s];
          t.mem_rdata = vif.mem_rdata[s];
          t.mem_wdata = vif.mem_wdata[s];
          t.mem_rdata_known = 1'b1;
          t.cycle    = cycle_now();

          check_order(t);

          n_retired++;
          if (t.trap) n_trapped++;
          if (t.is_mem_read())  n_mem_read++;
          if (t.is_mem_write()) n_mem_write++;
          if (t.intr) n_intr++;
          ap.write(t);
        end
        else if (vif.trap[s]) begin
          n_trap_without_valid++;
        end
      end
    end
  endtask

  protected function void check_order(rvfi_txn t);
    if (seen_any) begin
      if (t.order <= last_order)
        `uvm_error("RVFI_MON", $sformatf(
          "hart %0d order not increasing: %0d after %0d (%s)",
          hart_id, t.order, last_order, t.convert2string()))
      else if (t.order != last_order + 1)
        `uvm_error("RVFI_MON", $sformatf(
          "hart %0d order GAP: %0d after %0d -- %0d retirement(s) unobserved",
          hart_id, t.order, last_order, t.order - last_order - 1))
    end
    last_order = t.order;
    seen_any   = 1;
  endfunction

  protected function longint unsigned cycle_now();
    return longint'($time / clk_period_ns);
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("RVFI_MON", $sformatf(
      "hart %0d: %0d retired (%0d traps, %0d dual-issue cycles)",
      hart_id, n_retired, n_trapped, n_dual_issue), UVM_LOW)

    `uvm_info("RVFI_MON", $sformatf(
      "hart %0d: memory channels -- %0d loads, %0d stores, %0d intr",
      hart_id, n_mem_read, n_mem_write, n_intr), UVM_LOW)

    if ((n_retired > 100) && (n_mem_read == 0) && (n_mem_write == 0))
      `uvm_error("RVFI_MON", $sformatf(
        {"hart %0d retired %0d instructions and reported NO memory access on ",
         "either mask. The mem_* channels are not carrying -- check the ",
         "interface connection before trusting any memory comparison."},
        hart_id, n_retired))

    if (n_retired == 0)
      `uvm_error("RVFI_MON", $sformatf(
        "hart %0d retired NOTHING -- tap not connected, or the hart never ran",
        hart_id))

    if (n_trap_without_valid != 0)
      `uvm_error("RVFI_MON", $sformatf(
        {"hart %0d: rvfi_trap asserted on %0d slot(s) with rvfi_valid low. ",
         "These were NOT published. If this is legitimate DUT behaviour the ",
         "monitor needs to emit them; if it is not, it is a finding."},
        hart_id, n_trap_without_valid))
  endfunction

endclass
