// Proves the 1r1w predictor SRAM: synchronous read (data.
`timescale 1ns/1ps
module tb_sram_1r1w;
  localparam int W = 32, D = 16;
  logic clk = 0; always #5 clk = ~clk;

  logic rd_en, wr_en;
  logic [$clog2(D)-1:0] rd_addr, wr_addr;
  logic [W-1:0] rd_data, wr_data;
  logic [W/8-1:0] wr_be;

  sram_1r1w #(.WIDTH(W), .DEPTH(D), .INIT_POISON(1'b0)) dut (
    .clk, .rd_en, .rd_addr, .rd_data, .wr_en, .wr_addr, .wr_data, .wr_be
  );

  int errors = 0;
  task chk(string s, logic [W-1:0] g, e);
    if (g !== e) begin $display("FAIL %s: got %h exp %h", s, g, e); errors++; end
  endtask
  task idle(); rd_en=0; wr_en=0; rd_addr=0; wr_addr=0; wr_data=0; wr_be='1; endtask

  initial begin
    idle();
    @(negedge clk);

    @(negedge clk); wr_en=1; wr_addr=3; wr_data=32'hDEAD_BEEF; wr_be='1;
    @(negedge clk); wr_en=0;
    @(negedge clk); rd_en=1; rd_addr=3;
    @(negedge clk); rd_en=0;          // read issued last edge; data now valid
    chk("read-back addr3", rd_data, 32'hDEAD_BEEF);

    @(negedge clk); wr_en=1; wr_addr=5; wr_data=32'h1234_5678; wr_be='1;
    @(negedge clk); wr_en=0; rd_en=1; rd_addr=5;   // request addr5 this edge
    chk("pre-latency holds old", rd_data, 32'hDEAD_BEEF);
    @(negedge clk); rd_en=0;
    chk("addr5 valid next cycle", rd_data, 32'h1234_5678);

    @(negedge clk); wr_en=1; wr_addr=8; wr_data=32'hCAFE_F00D; wr_be='1;
                    rd_en=1; rd_addr=3;             // read 3 WHILE writing 8
    @(negedge clk); wr_en=0; rd_en=0;
    chk("concurrent read (addr3)", rd_data, 32'hDEAD_BEEF);
    @(negedge clk); rd_en=1; rd_addr=8;
    @(negedge clk); rd_en=0;
    chk("concurrent write (addr8)", rd_data, 32'hCAFE_F00D);

    @(negedge clk); wr_en=1; wr_addr=3; wr_data=32'h0000_0000; wr_be='1;
                    rd_en=1; rd_addr=3;
    @(negedge clk); wr_en=0; rd_en=0;
    chk("read-old on collision", rd_data, 32'hDEAD_BEEF);   // OLD value, not 0
    @(negedge clk); rd_en=1; rd_addr=3;
    @(negedge clk); rd_en=0;
    chk("write visible next cycle", rd_data, 32'h0000_0000);

    @(negedge clk); wr_en=1; wr_addr=10; wr_data=32'hFFFF_FFFF; wr_be='1;
    @(negedge clk); wr_en=1; wr_addr=10; wr_data=32'h0000_00AA; wr_be=4'b0001;
    @(negedge clk); wr_en=0; rd_en=1; rd_addr=10;
    @(negedge clk); rd_en=0;
    chk("byte-enable partial", rd_data, 32'hFFFF_FFAA);

    if (errors == 0) $display("SRAM_1R1W PASS");
    else $display("SRAM_1R1W FAIL: %0d", errors);
    $finish;
  end

  initial begin #10000; $display("SRAM_1R1W TIMEOUT"); $finish; end
endmodule
