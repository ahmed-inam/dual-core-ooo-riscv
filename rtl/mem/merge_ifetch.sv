// Aggregates both harts' instruction fills onto one master.
module merge_ifetch
  import rv32i_pkg::*;
  import mem_pkg::*;
  import platform_cfg_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic  [NUM_HARTS-1:0] i_req,
  output logic  [NUM_HARTS-1:0] i_gnt,
  input  word_t                 i_addr [NUM_HARTS],
  output logic  [NUM_HARTS-1:0] i_rvalid,
  output logic [LINE_W-1:0]     i_rdata,      // shared: only the owner samples it
  output logic                  i_rerr,

  output logic              out_req,
  input  logic              out_gnt,
  output word_t             out_addr,
  output logic              out_we,       // always 0: I-fetch never writes
  output logic              out_word,     // always 0: always a line
  output logic [3:0]        out_wstrb,
  output logic [LINE_W-1:0] out_wdata,
  input  logic              out_rvalid,
  input  logic [LINE_W-1:0] out_rdata,
  input  logic              out_rerr = 1'b0,

  output logic [NUM_HARTS-1:0] ev_starve_i
);

  logic              busy_q;
  logic [HART_W-1:0] own_q;
  logic              last_q;        // the only fairness state
  logic [HART_W-1:0] pick;
  logic              any_req;

  always_comb begin
    any_req = |i_req;
    if      (i_req[0] && i_req[1]) pick = last_q ? 1'b0 : 1'b1;  // alternate
    else if (i_req[0])             pick = 1'b0;
    else                           pick = 1'b1;
  end

  assign out_req   = !busy_q && any_req;
  assign out_addr  = i_addr[busy_q ? own_q : pick];
  assign out_we    = 1'b0;                 // I-fetch is read-only, always
  assign out_word  = 1'b0;                 // always a full line
  assign out_wstrb = 4'b0000;
  assign out_wdata = '0;

  for (genvar h = 0; h < NUM_HARTS; h++) begin : g_port
    assign i_gnt[h]    = !busy_q && any_req && (pick == HART_W'(h)) && out_gnt;
    assign i_rvalid[h] = out_rvalid && busy_q && (own_q == HART_W'(h));
    assign ev_starve_i[h] = i_req[h] && busy_q && (own_q != HART_W'(h));
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

  assign i_rdata = out_rdata;
  assign i_rerr  = out_rerr;

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if ($countones(i_gnt) > 1)
      $fatal(1, "merge_ifetch: more than one hart granted in a cycle");
    if (out_rvalid && !busy_q)
      $fatal(1, "merge_ifetch: response with no owner -- fetch lost");
    if ($countones(i_rvalid) > 1)
      $fatal(1, "merge_ifetch: response delivered to both harts");
    if (out_req && out_we)
      $fatal(1, "merge_ifetch: a WRITE on the instruction-fetch master");
  end
`endif

endmodule
