// Single-port synchronous array, for the cache data.

module sram_1rw #(
  parameter int unsigned WIDTH = 128,               // bits per entry
  parameter int unsigned DEPTH = 64,                // entries
  parameter              IMPL  = "BEHAVIORAL",      // BEHAVIORAL | BRAM | MACRO
  parameter bit          INIT_POISON = 1'b1,
  parameter logic [31:0] POISON_WORD = 32'hBAD1_BAD1
) (
  input  logic              clk,

  input  logic              en,      // access this cycle (read or write)
  input  logic              we,      // 1 = write, 0 = read
  input  logic [$clog2((DEPTH > 1) ? DEPTH : 2)-1:0] addr,
  input  logic [WIDTH-1:0]  wdata,
  input  logic [WIDTH/8-1:0] be,     // byte enables, write only
  output logic [WIDTH-1:0]  rdata    // valid the cycle AFTER en && !we
);

  localparam int unsigned ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int unsigned BE_W   = WIDTH / 8;

`ifndef SYNTHESIS
  initial begin
    if (WIDTH % 8 != 0)
      $fatal(1, "sram_1rw: WIDTH (%0d) must be a multiple of 8", WIDTH);
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
        if (en) begin
          if (we) begin
            for (int b = 0; b < BE_W; b++)
              if (be[b]) mem[addr][b*8 +: 8] <= wdata[b*8 +: 8];
          end else begin
            rdata <= mem[addr];
          end
        end
      end
    end else begin : g_macro
`ifndef SYNTHESIS
      initial $fatal(1, "sram_1rw: IMPL=MACRO selected but no macro is bound");
`endif
    end
  endgenerate

endmodule
