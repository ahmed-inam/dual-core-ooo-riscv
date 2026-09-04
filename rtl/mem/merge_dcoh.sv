// Aggregates both harts' data traffic onto one master.
module merge_dcoh
  import rv32i_pkg::*;
  import mem_pkg::*;
  import platform_cfg_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic  [NUM_HARTS-1:0] h_req,
  output logic  [NUM_HARTS-1:0] h_gnt,
  input  word_t                 h_addr  [NUM_HARTS],
  input  logic  [NUM_HARTS-1:0] h_we,
  input  logic  [NUM_HARTS-1:0] h_word,      // 1 = single word (MMIO), 0 = line
  input  logic  [3:0]           h_wstrb [NUM_HARTS],
  input  logic [LINE_W-1:0]     h_wdata [NUM_HARTS],
  output logic  [NUM_HARTS-1:0] h_rvalid,
  output logic [LINE_W-1:0]     h_rdata,     // shared: only the owner samples it
  output logic                  h_rerr,

  output logic              out_req,
  input  logic              out_gnt,
  output word_t             out_addr,
  output logic              out_we,
  output logic              out_word,
  output logic [3:0]        out_wstrb,
  output logic [LINE_W-1:0] out_wdata,
  input  logic              out_rvalid,
  input  logic [LINE_W-1:0] out_rdata,
  input  logic              out_rerr = 1'b0,

  output logic [NUM_HARTS-1:0] ev_starve_d
);

  logic              busy_q;
  logic [HART_W-1:0] own_q;
  logic              last_q;        // the only fairness state
  logic [HART_W-1:0] pick;
  logic              any_req;
  logic [HART_W-1:0] sel;

  always_comb begin
    any_req = |h_req;
    if      (h_req[0] && h_req[1]) pick = last_q ? 1'b0 : 1'b1;  // alternate
    else if (h_req[0])             pick = 1'b0;
    else                           pick = 1'b1;
  end

  assign sel = busy_q ? own_q : pick;

  assign out_req   = !busy_q && any_req;
  assign out_addr  = h_addr [sel];
  assign out_we    = h_we   [sel];
  assign out_word  = h_word [sel];
  assign out_wstrb = h_wstrb[sel];
  assign out_wdata = h_wdata[sel];

  for (genvar h = 0; h < NUM_HARTS; h++) begin : g_port
    assign h_gnt[h]    = !busy_q && any_req && (pick == HART_W'(h)) && out_gnt;
    assign h_rvalid[h] = out_rvalid && busy_q && (own_q == HART_W'(h));
    assign ev_starve_d[h] = h_req[h] && busy_q && (own_q != HART_W'(h));
  end : g_port

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0;
      own_q  <= '0;
      last_q <= 1'b0;
    end else if (!busy_q) begin
      if (any_req && out_gnt) begin
        busy_q <= 1'b1;
        own_q  <= pick;
        last_q <= pick;                    // rotate away from the winner
      end
    end else if (out_rvalid) begin
      busy_q <= 1'b0;
    end
  end

  assign h_rdata = out_rdata;
  assign h_rerr  = out_rerr;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if ($countones(h_gnt) > 1)
      $fatal(1, "merge_dcoh: more than one hart granted in a cycle");
    if (out_rvalid && !busy_q)
      $fatal(1, "merge_dcoh: response with no owner -- transaction lost");
    if (busy_q && h_we[own_q] && (out_wdata !== h_wdata[own_q]))
      $fatal(1, "merge_dcoh: write payload does not belong to the owner");
  end
`endif

endmodule
