// Per-ID ordering guard, so responses cannot overtake within an ID.

module thread_tracker
  import axi4_pkg::*;
(
  input  logic                aclk,
  input  logic                arst_n,

  input  logic [ID_WIDTH-1:0] q_id,        // candidate AW/AR
  input  dest_e               q_dest,
  output logic                q_ok,        // combinational: safe to admit?
  input  logic                alloc,       // admit happened this cycle

  input  logic                cpl_valid,   // from resp_return_mux, tag already stripped
  input  logic [ID_WIDTH-1:0] cpl_id
);

  thread_t thr [NUM_THREADS];

  logic [NUM_THREADS-1:0] active, match_id, match_dest, cpl_match, alloc_sel;
  logic [NUM_THREADS-1:0] inc, dec;

  always_comb begin
    for (int i = 0; i < NUM_THREADS; i++) begin
      active[i]     = (thr[i].count != '0);
      match_id[i]   = active[i] && (thr[i].id == q_id);
      match_dest[i] = match_id[i] && (thr[i].dest == q_dest);
      cpl_match[i]  = active[i] && (thr[i].id == cpl_id);
    end
  end

  always_comb begin
    alloc_sel = '0;
    for (int i = 0; i < NUM_THREADS; i++) begin
      if (!active[i]) begin
        alloc_sel[i] = 1'b1;
        break;
      end
    end
  end

  assign q_ok = (|match_dest) || (!(|match_id) && !(&active));

  always_comb begin
    for (int i = 0; i < NUM_THREADS; i++) begin
      inc[i] = alloc     && (match_dest[i] || (!(|match_id) && alloc_sel[i]));
      dec[i] = cpl_valid && cpl_match[i];
    end
  end

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      for (int i = 0; i < NUM_THREADS; i++) thr[i] <= '0;
    end
    else begin
      for (int i = 0; i < NUM_THREADS; i++) begin
        if (inc[i] && !dec[i]) begin
          thr[i].count <= thr[i].count + 1'b1;
          if (!active[i]) begin            // fresh entry: latch id and dest
            thr[i].id   <= q_id;
            thr[i].dest <= q_dest;
          end
        end
        else if (!inc[i] && dec[i]) begin
          thr[i].count <= thr[i].count - 1'b1;
        end
      end
    end
  end

  always @(posedge aclk) if (arst_n) begin
    a_cpl_has_thread: assert (!cpl_valid || (|cpl_match))
      else $error("thread_tracker: cpl_id %0d has no active thread", cpl_id);

    a_alloc_legal: assert (!alloc || q_ok)
      else $error("thread_tracker: alloc while q_ok low");
  end

endmodule : thread_tracker
