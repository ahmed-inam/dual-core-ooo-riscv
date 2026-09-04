// The map table: 32 architectural names onto 64 physical registers.
module rename
  import core_cfg_pkg::*;
(
  input  logic      clk,
  input  logic      rst_n,

  input  logic      [WIDTH-1:0][4:0] lrs1,
  input  logic      [WIDTH-1:0][4:0] lrs2,
  input  logic      [WIDTH-1:0][4:0] ldst,
  output preg_t     [WIDTH-1:0]      prs1,
  output preg_t     [WIDTH-1:0]      prs2,
  output preg_t     [WIDTH-1:0]      stale_pdst,

  input  logic      [WIDTH-1:0]      remap_valid,
  input  preg_t     [WIDTH-1:0]      remap_pdst,

  input  logic      [WIDTH-1:0]      snap_take,  // slot i post-state -> id_i[i]
  input  snap_ptr_t [WIDTH-1:0]      snap_id_i,
  input  logic                       snap_restore,
  input  snap_ptr_t                  snap_id_r,

  output preg_t     [31:0]           map_dbg
);

  preg_t map_q [32];
  preg_t snap_q [SNAP_N][32];

  logic [WIDTH-1:0] rv;
  always_comb
    for (int i = 0; i < WIDTH; i++)
      rv[i] = remap_valid[i] && (ldst[i] != 5'd0);

  always_comb begin
    for (int i = 0; i < WIDTH; i++) begin
      prs1[i]       = (lrs1[i] == 5'd0) ? preg_t'(0) : map_q[lrs1[i]];
      prs2[i]       = (lrs2[i] == 5'd0) ? preg_t'(0) : map_q[lrs2[i]];
      stale_pdst[i] = (ldst[i] == 5'd0) ? preg_t'(0) : map_q[ldst[i]];
      for (int j = 0; j < WIDTH; j++) begin
        if (j < i) begin
          if (rv[j] && ldst[j] == lrs1[i]) prs1[i]       = remap_pdst[j];
          if (rv[j] && ldst[j] == lrs2[i]) prs2[i]       = remap_pdst[j];
          if (rv[j] && ldst[j] == ldst[i]) stale_pdst[i] = remap_pdst[j];
        end
      end
    end
  end

  preg_t post [WIDTH][32];
  always_comb begin
    for (int i = 0; i < WIDTH; i++)
      for (int r = 0; r < 32; r++) begin
        post[i][r] = map_q[r];
        for (int j = 0; j < WIDTH; j++)
          if (j <= i && rv[j] && ldst[j] == 5'(r))
            post[i][r] = remap_pdst[j];
      end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int r = 0; r < 32; r++) map_q[r] <= preg_t'(r);
      for (int s = 0; s < SNAP_N; s++)
        for (int r = 0; r < 32; r++) snap_q[s][r] <= preg_t'(r);
    end else begin
      if (snap_restore) begin
        for (int r = 0; r < 32; r++) map_q[r] <= snap_q[snap_id_r][r];
      end else begin
        for (int i = 0; i < WIDTH; i++)
          if (rv[i]) map_q[ldst[i]] <= remap_pdst[i];
      end
      for (int i = 0; i < WIDTH; i++)
        if (snap_take[i])
          for (int r = 0; r < 32; r++)
            snap_q[snap_id_i[i]][r] <= post[i][r];
    end
  end

  always_comb
    for (int r = 0; r < 32; r++) map_dbg[r] = map_q[r];

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n && !snap_restore) begin
      for (int i = 0; i < WIDTH; i++) begin
        if (rv[i]) begin
          for (int r = 0; r < 32; r++)
            if (map_q[r] == remap_pdst[i] && 5'(r) != ldst[i])
              $fatal(1, "rename: remap installs p%0d already mapped at x%0d (freed-reg-reused at the moment of infection)",
                     remap_pdst[i], r);
        end
      end
    end
  end
`endif

endmodule
