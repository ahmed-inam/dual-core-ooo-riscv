// Testbench-side line-granular memory for Phase 3.
`timescale 1ns/1ps
module stub_linemem
  import rv32i_pkg::*;
  import mem_pkg::*;
#(
  parameter int unsigned LATENCY = 10,
  parameter int unsigned WORDS   = 4096
) (
  input  logic  clk,
  input  logic  rst_n,

  input  logic  req,
  output logic  gnt,
  input  word_t addr,
  input  logic  we,                        // whole-line write (writeback)
  input  logic [LINE_W-1:0] wdata,
  output logic  rvalid,                    // read data valid / write complete
  output logic [LINE_W-1:0] rdata
);

  word_t mem [WORDS];

  logic [15:0] cnt_q;
  logic        busy_q;
  word_t       addr_q;
  logic        we_q;
  logic [LINE_W-1:0] wdata_q;

  assign gnt = req && !busy_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_q <= 1'b0; cnt_q <= '0; addr_q <= '0; we_q <= 1'b0; wdata_q <= '0;
    end else if (req && gnt) begin
      busy_q <= 1'b1; cnt_q <= '0; addr_q <= addr;
      we_q <= we; wdata_q <= wdata;
    end else if (busy_q) begin
      if (cnt_q >= 16'(LATENCY)) busy_q <= 1'b0;
      else                       cnt_q  <= cnt_q + 16'd1;
    end
  end

  assign rvalid = busy_q && (cnt_q >= 16'(LATENCY));

  always_ff @(posedge clk) if (busy_q && we_q && (cnt_q >= 16'(LATENCY)))
    for (int i = 0; i < BEATS_PER_LINE; i++)
      mem[(addr_q[31:2] + 30'(i)) % 30'(WORDS)] <= wdata_q[i*32 +: 32];

  logic [29:0] w0;
  assign w0 = addr_q[31:2];
  always_comb begin
    for (int i = 0; i < BEATS_PER_LINE; i++)
      rdata[i*32 +: 32] = mem[(w0 + 30'(i)) % 30'(WORDS)];
  end

endmodule
