// Cycle and instruction counters, plus the hardware performance counters.

module perf_counters
  import rv32i_pkg::*;
#(
  parameter bit HPM_ENABLE = 1'b1
) (
  input  logic clk,
  input  logic rst_n,

  input  logic [1:0] instr_retired,   // COUNT of retired instrs this
  input  logic branch_resolved, // E: a CF instruction resolved (update.valid)
  input  logic branch_mispred,  // E: ...and it was mispredicted
  input  logic stall_cycle,     // D: hazard_unit asserted a stall this cycle
  input  logic ic_miss,          // I-cache: an accepted access that missed
  input  logic dc_miss,          // D-cache: an accepted cacheable access, missed
  input  logic dc_writeback,     // D-cache: a dirty line went out to memory
  input  logic mem_stall_cycle,  // a cycle lost waiting on memory, NOT load-use
  input  logic flush_cycle,      // one pulse per redirect EVENT (not per wasted

  input  logic [11:0] raddr,
  output word_t       rdata,
  output logic        addr_hit,   // "this address belongs to me" -- feeds

  input  logic        commit_we,     // a retiring CSR instr is writing
  input  logic [11:0] commit_addr,
  input  csr_op_e     commit_op,
  input  word_t       commit_operand // rs1 value or zero-extended uimm
);

  logic [63:0] mcycle_q,   mcycle_d;
  logic [63:0] minstret_q, minstret_d;
  logic [63:0] hpm3_q,     hpm3_d;   // branches resolved
  logic [63:0] hpm4_q,     hpm4_d;   // mispredicts
  logic [63:0] hpm5_q,     hpm5_d;   // stall cycles
  logic [63:0] hpm6_q,     hpm6_d;   // flush cycles
  logic [63:0] hpm7_q,     hpm7_d;   // I-cache misses
  logic [63:0] hpm8_q,     hpm8_d;   // D-cache misses
  logic [63:0] hpm9_q,     hpm9_d;   // D-cache writebacks
  logic [63:0] hpm10_q,    hpm10_d;  // memory stall cycles

  assign addr_hit = csr_is_perf(raddr);


  always_comb begin
    unique case (raddr)
      CSR_MCYCLE:     rdata = mcycle_q  [31:0];
      CSR_MCYCLEH:    rdata = mcycle_q  [63:32];
      CSR_MINSTRET:   rdata = minstret_q[31:0];
      CSR_MINSTRETH:  rdata = minstret_q[63:32];
      CSR_MHPM3:      rdata = hpm3_q    [31:0];
      CSR_MHPM3H:     rdata = hpm3_q    [63:32];
      CSR_MHPM4:      rdata = hpm4_q    [31:0];
      CSR_MHPM4H:     rdata = hpm4_q    [63:32];
      CSR_MHPM5:      rdata = hpm5_q    [31:0];
      CSR_MHPM5H:     rdata = hpm5_q    [63:32];
      CSR_MHPM6:      rdata = hpm6_q    [31:0];
      CSR_MHPM6H:     rdata = hpm6_q    [63:32];
      CSR_MHPM7:      rdata = hpm7_q    [31:0];
      CSR_MHPM7H:     rdata = hpm7_q    [63:32];
      CSR_MHPM8:      rdata = hpm8_q    [31:0];
      CSR_MHPM8H:     rdata = hpm8_q    [63:32];
      CSR_MHPM9:      rdata = hpm9_q    [31:0];
      CSR_MHPM9H:     rdata = hpm9_q    [63:32];
      CSR_MHPM10:     rdata = hpm10_q   [31:0];
      CSR_MHPM10H:    rdata = hpm10_q   [63:32];
      CSR_CYCLE,
      CSR_TIME:       rdata = mcycle_q  [31:0];
      CSR_CYCLEH,
      CSR_TIMEH:      rdata = mcycle_q  [63:32];
      CSR_INSTRET:    rdata = minstret_q[31:0];
      CSR_INSTRETH:   rdata = minstret_q[63:32];
      default:        rdata = '0;
    endcase
  end

  word_t old_at_commit, wval;
  always_comb begin
    unique case (commit_addr)
      CSR_MCYCLE:     old_at_commit = mcycle_q  [31:0];
      CSR_MCYCLEH:    old_at_commit = mcycle_q  [63:32];
      CSR_MINSTRET:   old_at_commit = minstret_q[31:0];
      CSR_MINSTRETH:  old_at_commit = minstret_q[63:32];
      CSR_MHPM3:      old_at_commit = hpm3_q    [31:0];
      CSR_MHPM3H:     old_at_commit = hpm3_q    [63:32];
      CSR_MHPM4:      old_at_commit = hpm4_q    [31:0];
      CSR_MHPM4H:     old_at_commit = hpm4_q    [63:32];
      CSR_MHPM5:      old_at_commit = hpm5_q    [31:0];
      CSR_MHPM5H:     old_at_commit = hpm5_q    [63:32];
      CSR_MHPM6:      old_at_commit = hpm6_q    [31:0];
      CSR_MHPM6H:     old_at_commit = hpm6_q    [63:32];
      CSR_MHPM7:      old_at_commit = hpm7_q    [31:0];
      CSR_MHPM7H:     old_at_commit = hpm7_q    [63:32];
      CSR_MHPM8:      old_at_commit = hpm8_q    [31:0];
      CSR_MHPM8H:     old_at_commit = hpm8_q    [63:32];
      CSR_MHPM9:      old_at_commit = hpm9_q    [31:0];
      CSR_MHPM9H:     old_at_commit = hpm9_q    [63:32];
      CSR_MHPM10:     old_at_commit = hpm10_q   [31:0];
      CSR_MHPM10H:    old_at_commit = hpm10_q   [63:32];
      default:        old_at_commit = '0;
    endcase
  end
  assign wval = csr_next_val(old_at_commit, commit_op, commit_operand);

  always_comb begin
    mcycle_d   = mcycle_q   + 64'd1;               // free-running
    minstret_d = minstret_q + 64'(instr_retired);
    if (HPM_ENABLE) begin
      hpm3_d   = hpm3_q     + (branch_resolved? 64'd1 : 64'd0);
      hpm4_d   = hpm4_q     + (branch_mispred ? 64'd1 : 64'd0);
      hpm5_d   = hpm5_q     + (stall_cycle    ? 64'd1 : 64'd0);
      hpm6_d   = hpm6_q     + (flush_cycle    ? 64'd1 : 64'd0);
      hpm7_d   = hpm7_q     + (ic_miss        ? 64'd1 : 64'd0);
      hpm8_d   = hpm8_q     + (dc_miss        ? 64'd1 : 64'd0);
      hpm9_d   = hpm9_q     + (dc_writeback   ? 64'd1 : 64'd0);
      hpm10_d  = hpm10_q    + (mem_stall_cycle? 64'd1 : 64'd0);
    end else begin
      hpm3_d   = '0;  hpm4_d = '0;  hpm5_d = '0;  hpm6_d = '0;
      hpm7_d   = '0;  hpm8_d = '0;  hpm9_d = '0;  hpm10_d = '0;
    end

    if (commit_we) begin
      unique case (commit_addr)
        CSR_MCYCLE:     mcycle_d   = {mcycle_q  [63:32], wval};
        CSR_MCYCLEH:    mcycle_d   = {wval, mcycle_q  [31:0]};
        CSR_MINSTRET:   minstret_d = {minstret_q[63:32], wval};
        CSR_MINSTRETH:  minstret_d = {wval, minstret_q[31:0]};
        CSR_MHPM3:      if (HPM_ENABLE) hpm3_d = {hpm3_q    [63:32], wval};
        CSR_MHPM3H:     if (HPM_ENABLE) hpm3_d = {wval, hpm3_q    [31:0]};
        CSR_MHPM4:      if (HPM_ENABLE) hpm4_d = {hpm4_q    [63:32], wval};
        CSR_MHPM4H:     if (HPM_ENABLE) hpm4_d = {wval, hpm4_q    [31:0]};
        CSR_MHPM5:      if (HPM_ENABLE) hpm5_d = {hpm5_q    [63:32], wval};
        CSR_MHPM5H:     if (HPM_ENABLE) hpm5_d = {wval, hpm5_q    [31:0]};
        CSR_MHPM6:      if (HPM_ENABLE) hpm6_d = {hpm6_q    [63:32], wval};
        CSR_MHPM6H:     if (HPM_ENABLE) hpm6_d = {wval, hpm6_q    [31:0]};
        CSR_MHPM7:      if (HPM_ENABLE) hpm7_d = {hpm7_q    [63:32], wval};
        CSR_MHPM7H:     if (HPM_ENABLE) hpm7_d = {wval, hpm7_q    [31:0]};
        CSR_MHPM8:      if (HPM_ENABLE) hpm8_d = {hpm8_q    [63:32], wval};
        CSR_MHPM8H:     if (HPM_ENABLE) hpm8_d = {wval, hpm8_q    [31:0]};
        CSR_MHPM9:      if (HPM_ENABLE) hpm9_d = {hpm9_q    [63:32], wval};
        CSR_MHPM9H:     if (HPM_ENABLE) hpm9_d = {wval, hpm9_q    [31:0]};
        CSR_MHPM10:     if (HPM_ENABLE) hpm10_d = {hpm10_q  [63:32], wval};
        CSR_MHPM10H:    if (HPM_ENABLE) hpm10_d = {wval, hpm10_q  [31:0]};
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mcycle_q   <= '0;
      minstret_q <= '0;
      hpm3_q     <= '0;
      hpm4_q     <= '0;
      hpm5_q     <= '0;
      hpm6_q     <= '0;
      hpm7_q     <= '0;
      hpm8_q     <= '0;
      hpm9_q     <= '0;
      hpm10_q    <= '0;
    end else begin
      mcycle_q   <= mcycle_d;
      minstret_q <= minstret_d;
      hpm3_q     <= hpm3_d;
      hpm4_q     <= hpm4_d;
      hpm5_q     <= hpm5_d;
      hpm6_q     <= hpm6_d;
      hpm7_q     <= hpm7_d;
      hpm8_q     <= hpm8_d;
      hpm9_q     <= hpm9_d;
      hpm10_q    <= hpm10_d;
    end
  end

endmodule
