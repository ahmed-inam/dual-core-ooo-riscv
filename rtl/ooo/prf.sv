// 64-entry physical register file and its busy table.
module prf
  import core_cfg_pkg::*;
(
  input  logic   clk,
  input  logic   rst_n,

  input  preg_t [2*WIDTH-1:0]        raddr,
  output logic  [2*WIDTH-1:0][31:0]  rdata,

  input  logic  [WAKEUP_W-1:0]       wen,
  input  preg_t [WAKEUP_W-1:0]       waddr,
  input  logic  [WAKEUP_W-1:0][31:0] wdata,

  input  logic  [WIDTH-1:0]          set_busy,
  input  preg_t [WIDTH-1:0]          set_preg,
  input  preg_t [2*WIDTH-1:0]        busy_raddr,
  output logic  [2*WIDTH-1:0]        busy_rdata
);
  logic [31:0] regs [PRF_N];
  logic  busy_q [PRF_N];

  for (genvar gi = 0; gi < 2*WIDTH; gi++) begin : g_rd
    assign rdata[gi]      = (raddr[gi]      == '0) ? 32'd0 : regs[raddr[gi]];
    assign busy_rdata[gi] = (busy_raddr[gi] == '0) ? 1'b0  : busy_q[busy_raddr[gi]];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < PRF_N; i++) begin
        regs[i]   <= '0;
        busy_q[i] <= 1'b0;
      end
    end else begin
      for (int w = 0; w < WAKEUP_W; w++) begin
        if (wen[w] && waddr[w] != '0) begin
          regs[waddr[w]]   <= wdata[w];
          busy_q[waddr[w]] <= 1'b0;
        end
      end
      for (int s = 0; s < WIDTH; s++)
        if (set_busy[s] && set_preg[s] != '0)
          busy_q[set_preg[s]] <= 1'b1;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n) begin
      for (int a = 0; a < WAKEUP_W; a++)
        for (int b = a+1; b < WAKEUP_W; b++)
          if (wen[a] && wen[b] && waddr[a] == waddr[b] && waddr[a] != '0)
            $fatal(1, "prf: two writers hit p%0d in one cycle: one name, two producers", waddr[a]);
    end
  end
`endif

endmodule
