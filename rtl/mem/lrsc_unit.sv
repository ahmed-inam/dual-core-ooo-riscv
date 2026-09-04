// Per-hart LR/SC reservation, the SC verdict, and the anti-hogging back-off.
module lrsc_unit
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coherence_pkg::*;
  import platform_cfg_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic  [NUM_HARTS-1:0] lr_valid,    // an LR is completing for this hart
  input  logic  [NUM_HARTS-1:0] sc_valid,    // an SC is being attempted
  input  logic  [NUM_HARTS-1:0] acc_valid,   // any OTHER qualifying data access
  input  word_t                 acc_addr  [NUM_HARTS],
  input  logic  [NUM_HARTS-1:0] acc_hit,

  input  logic  [NUM_HARTS-1:0] snoop_clear,
  input  logic  [NUM_HARTS-1:0] trap_clear,  // a trap on this hart clears it

  output logic  [NUM_HARTS-1:0] sc_success,

  output logic  [NUM_HARTS-1:0] prot_valid,
  output word_t                 prot_addr [NUM_HARTS],

  output logic  [NUM_HARTS-1:0] rsv_valid,
  output logic  [NUM_HARTS-1:0] backing_off
);

  logic [LRSC_CNT_W-1:0] cnt_q [NUM_HARTS];
  logic [LRSC_CNT_W-1:0] cnt_d [NUM_HARTS];
  logic [31:OFF_W]       rsv_line_q [NUM_HARTS];
  logic [31:OFF_W]       rsv_line_d [NUM_HARTS];

  for (genvar h = 0; h < NUM_HARTS; h++) begin : g_state
    assign rsv_valid[h]   = cnt_q[h] > LRSC_CNT_W'(LRSC_BACKOFF);
    assign backing_off[h] = (cnt_q[h] != '0) && !rsv_valid[h];
    assign prot_valid[h]  = rsv_valid[h];
    assign prot_addr[h]   = {rsv_line_q[h], {OFF_W{1'b0}}};
  end : g_state

  for (genvar h = 0; h < NUM_HARTS; h++) begin : g_sc
    // An SC in the backoff phase fails: the retry loop must re-execute its LR.
    assign sc_success[h] = sc_valid[h] && rsv_valid[h]
                           && (acc_addr[h][31:OFF_W] == rsv_line_q[h]);
  end : g_sc

  always_comb begin
    for (int h = 0; h < NUM_HARTS; h++) begin
      rsv_line_d[h] = rsv_line_q[h];

      if (snoop_clear[h] || trap_clear[h]) begin
        cnt_d[h] = '0;
      end else if ((acc_valid[h] || sc_valid[h]) && rsv_valid[h] && !lr_valid[h]) begin
        cnt_d[h] = LRSC_CNT_W'(LRSC_BACKOFF);
      end else if (lr_valid[h]) begin
        if (acc_hit[h] && (cnt_q[h] == '0)) begin
          cnt_d[h]      = LRSC_CNT_W'(LRSC_WINDOW_N);
          rsv_line_d[h] = acc_addr[h][31:OFF_W];
        end else if (rsv_valid[h]) begin
          if (acc_hit[h] && (acc_addr[h][31:OFF_W] == rsv_line_q[h])) begin
            cnt_d[h]      = LRSC_CNT_W'(LRSC_WINDOW_N);
            rsv_line_d[h] = acc_addr[h][31:OFF_W];
          end else begin
            cnt_d[h] = LRSC_CNT_W'(LRSC_BACKOFF);
          end
        end else if (cnt_q[h] != '0) begin
          cnt_d[h] = cnt_q[h] - 1'b1;   // backing off: no reservation, and the back-off is not restarted
        end else begin
          cnt_d[h] = (cnt_q[h] != '0) ? cnt_q[h] - 1'b1 : '0;
        end
      end else begin
        cnt_d[h] = (cnt_q[h] != '0) ? cnt_q[h] - 1'b1 : '0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int h = 0; h < NUM_HARTS; h++) begin
        cnt_q[h]      <= '0;
        rsv_line_q[h] <= '0;
      end
    end else begin
      for (int h = 0; h < NUM_HARTS; h++) begin
        cnt_q[h]      <= cnt_d[h];
        rsv_line_q[h] <= rsv_line_d[h];
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (LRSC_BACKOFF >= LRSC_WINDOW_N)
      $fatal(1, "lrsc_unit: LRSC_BACKOFF >= LRSC_WINDOW_N -- the protection window can never open");
    for (int h = 0; h < NUM_HARTS; h++)
      if (rsv_valid[h] && backing_off[h])
        $fatal(1, "lrsc_unit: hart %0d both valid and backing off", h);
    for (int h = 0; h < NUM_HARTS; h++)
      if (sc_success[h] && !rsv_valid[h])
        $fatal(1, "lrsc_unit: SC succeeded on hart %0d with no valid reservation", h);
    for (int h = 0; h < NUM_HARTS; h++)
      if (snoop_clear[h] && rsv_valid[h] && (cnt_d[h] != '0))
        $fatal(1, "lrsc_unit: snoop_clear did not clear hart %0d's reservation", h);
  end
`endif

endmodule
