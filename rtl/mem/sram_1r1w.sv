// One-read one-write synchronous array, for the predictor tables.
module sram_1r1w #(
  parameter int unsigned WIDTH = 64,                // bits per entry
  parameter int unsigned DEPTH = 64,                // entries
  parameter              IMPL  = "BEHAVIORAL",       // BEHAVIORAL | BRAM | MACRO
  parameter bit          INIT_POISON = 1'b1,
  parameter logic [31:0] POISON_WORD = 32'hBAD2_BAD2
) (
  input  logic              clk,
  input  logic              rd_en,
  input  logic [$clog2((DEPTH > 1) ? DEPTH : 2)-1:0] rd_addr,
  output logic [WIDTH-1:0]  rd_data,
  input  logic              wr_en,
  input  logic [$clog2((DEPTH > 1) ? DEPTH : 2)-1:0] wr_addr,
  input  logic [WIDTH-1:0]  wr_data,
  input  logic [WIDTH/8-1:0] wr_be    // byte enables, write only
);

  localparam int unsigned ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int unsigned BE_W   = WIDTH / 8;

`ifndef SYNTHESIS
  initial begin
    if (WIDTH % 8 != 0)
      $fatal(1, "sram_1r1w: WIDTH (%0d) must be a multiple of 8", WIDTH);
  end
`endif

  generate
    if (IMPL == "BEHAVIORAL" || IMPL == "BRAM") begin : g_infer
      logic [WIDTH-1:0] mem [DEPTH];
`ifndef SYNTHESIS
      initial begin
        if (INIT_POISON)
          for (int i = 0; i < DEPTH; i++)
            for (int w = 0; w < WIDTH/32; w++)
              mem[i][w*32 +: 32] = POISON_WORD;
      end
`endif
      always_ff @(posedge clk) begin
        if (rd_en) rd_data <= mem[rd_addr];
        if (wr_en)
          for (int b = 0; b < BE_W; b++)
            if (wr_be[b]) mem[wr_addr][b*8 +: 8] <= wr_data[b*8 +: 8];
      end
    end else begin : g_macro
`ifndef SYNTHESIS
      initial $fatal(1, "sram_1r1w: IMPL=MACRO selected but no macro is bound");
`endif
    end
  endgenerate

endmodule
