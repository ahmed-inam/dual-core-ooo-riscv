// Gate for merge_d_mmio and merge_ifetch, the two.
module tb_merges
  import rv32i_pkg::*;
  import mem_pkg::*;
  import platform_cfg_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0;
  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  logic              a_dreq, a_dgnt, a_dwe, a_drvalid;
  word_t             a_daddr;
  logic [LINE_W-1:0] a_dwdata, a_drdata;
  logic              a_mreq, a_mgnt, a_mwe, a_mrvalid;
  word_t             a_maddr, a_mwdata, a_mrdata;
  logic [3:0]        a_mwstrb;
  logic              a_oreq, a_ognt, a_owe, a_oword, a_orvalid;
  word_t             a_oaddr;
  logic [3:0]        a_owstrb;
  logic [LINE_W-1:0] a_owdata, a_ordata;
  logic              a_starve_m;

  merge_d_mmio u_a (
    .clk, .rst_n,
    .d_req(a_dreq), .d_gnt(a_dgnt), .d_addr(a_daddr), .d_we(a_dwe),
    .d_wdata(a_dwdata), .d_rvalid(a_drvalid), .d_rdata(a_drdata),
    .m_req(a_mreq), .m_gnt(a_mgnt), .m_addr(a_maddr), .m_we(a_mwe),
    .m_wstrb(a_mwstrb), .m_wdata(a_mwdata), .m_rvalid(a_mrvalid), .m_rdata(a_mrdata),
    .out_req(a_oreq), .out_gnt(a_ognt), .out_addr(a_oaddr), .out_we(a_owe),
    .out_word(a_oword), .out_wstrb(a_owstrb), .out_wdata(a_owdata),
    .out_rvalid(a_orvalid), .out_rdata(a_ordata),
    .ev_starve_m(a_starve_m)
  );

  logic a_pend;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin a_pend <= 1'b0; a_orvalid <= 1'b0; a_ordata <= '0; end
    else begin
      a_orvalid <= 1'b0;
      if (a_oreq && a_ognt) a_pend <= 1'b1;
      else if (a_pend) begin
        a_pend   <= 1'b0;
        a_orvalid <= 1'b1;
        a_ordata <= {32'hD4D4D4D4, 32'hC3C3C3C3, 32'hB2B2B2B2, 32'hA1A1A1A1};
      end
    end
  end
  assign a_ognt = a_oreq;

  logic  [NUM_HARTS-1:0] b_ireq, b_ignt, b_irvalid, b_starve;
  word_t                 b_iaddr [NUM_HARTS];
  logic [LINE_W-1:0]     b_irdata;
  logic                  b_oreq, b_ognt, b_owe, b_oword, b_orvalid;
  word_t                 b_oaddr;
  logic [3:0]            b_owstrb;
  logic [LINE_W-1:0]     b_owdata, b_ordata;

  merge_ifetch u_b (
    .clk, .rst_n,
    .i_req(b_ireq), .i_gnt(b_ignt), .i_addr(b_iaddr),
    .i_rvalid(b_irvalid), .i_rdata(b_irdata),
    .out_req(b_oreq), .out_gnt(b_ognt), .out_addr(b_oaddr), .out_we(b_owe),
    .out_word(b_oword), .out_wstrb(b_owstrb), .out_wdata(b_owdata),
    .out_rvalid(b_orvalid), .out_rdata(b_ordata),
    .ev_starve_i(b_starve)
  );

  logic b_pend;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin b_pend <= 1'b0; b_orvalid <= 1'b0; b_ordata <= '0; end
    else begin
      b_orvalid <= 1'b0;
      if (b_oreq && b_ognt) b_pend <= 1'b1;
      else if (b_pend) begin
        b_pend <= 1'b0; b_orvalid <= 1'b1; b_ordata <= {4{32'hFEED_0000}};
      end
    end
  end
  assign b_ognt = b_oreq;

  int i, w0, w1, guard;

  initial begin
    a_dreq=0; a_daddr='0; a_dwe=0; a_dwdata='0;
    a_mreq=0; a_maddr='0; a_mwe=0; a_mwstrb=4'h0; a_mwdata='0;
    b_ireq='0; b_iaddr[0]='0; b_iaddr[1]='0;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_merges ===");

    @(negedge clk); a_dreq=1'b1; a_daddr=32'h8000_1000; a_dwe=1'b0;
    #1; ck("A: D alone is granted", a_dgnt === 1'b1);
    ck("A: D traffic is a LINE (out_word low)", a_oword === 1'b0);
    ck("A: downstream address is D's", a_oaddr === 32'h8000_1000);
    @(posedge clk); #1; a_dreq=1'b0;
    guard=0; while (!a_drvalid && guard<20) begin @(posedge clk); #1; guard++; end
    ck("A: D got its response", a_drvalid === 1'b1);
    ck("A: MMIO did NOT get D's response", a_mrvalid === 1'b0);
    ck("A: D response data is the fill", a_drdata[31:0] === 32'hA1A1A1A1);
    @(negedge clk);

    @(negedge clk); a_mreq=1'b1; a_maddr=32'h0200_0000; a_mwe=1'b1;
    a_mwstrb=4'hF; a_mwdata=32'hCAFE_0001;
    #1; ck("A: MMIO alone is granted", a_mgnt === 1'b1);
    ck("A: MMIO traffic is a WORD (out_word high)", a_oword === 1'b1);
    ck("A: MMIO write data rides the low word", a_owdata[31:0] === 32'hCAFE_0001);
    ck("A: MMIO strobes pass through", a_owstrb === 4'hF);
    @(posedge clk); #1; a_mreq=1'b0;
    guard=0; while (!a_mrvalid && guard<20) begin @(posedge clk); #1; guard++; end
    ck("A: MMIO got its response", a_mrvalid === 1'b1);
    ck("A: D did NOT get MMIO's response", a_drvalid === 1'b0);
    @(negedge clk);

    @(negedge clk);
    a_dreq=1'b1; a_daddr=32'h8000_2000; a_dwe=1'b0;
    a_mreq=1'b1; a_maddr=32'h0200_0004; a_mwe=1'b0; a_mwstrb=4'h0;
    #1;
    ck("A: D WINS when both ask (mem_arbiter's ruling carried over)",
       a_dgnt === 1'b1 && a_mgnt === 1'b0);
    ck("A: starvation counter flags the losing MMIO", a_starve_m === 1'b1);
    ck("A: never two grants in one cycle", !(a_dgnt && a_mgnt));
    @(posedge clk); #1; a_dreq=1'b0;
    guard=0; while (!a_mrvalid && guard<40) begin @(posedge clk); #1; guard++; end
    ck("A: the deferred MMIO is served afterwards (not dropped)", a_mrvalid === 1'b1);
    a_mreq=1'b0; @(negedge clk);

    @(negedge clk); b_ireq=2'b01; b_iaddr[0]=32'h8000_3000;
    #1; ck("B: hart0 alone is granted", b_ignt[0] === 1'b1);
    ck("B: I-fetch never writes", b_owe === 1'b0);
    ck("B: I-fetch is always a line", b_oword === 1'b0);
    @(posedge clk); #1; b_ireq='0;
    guard=0; while (!b_irvalid[0] && guard<20) begin @(posedge clk); #1; guard++; end
    ck("B: hart0 got its line", b_irvalid[0] === 1'b1);
    ck("B: hart1 did NOT get hart0's line", b_irvalid[1] === 1'b0);
    @(negedge clk);

    w0=0; w1=0;
    for (i = 0; i < 200; i++) begin
      @(negedge clk);
      b_ireq = 2'b11; b_iaddr[0]=32'h8000_4000; b_iaddr[1]=32'h8000_5000;
      #1;
      if (b_ignt[0]) w0++;
      if (b_ignt[1]) w1++;
      if (b_ignt[0] && b_ignt[1]) begin errors++; $display("  [BAD ] B: two grants in one cycle"); end
      @(posedge clk);
    end
    b_ireq='0;
    $display("  [info] B fairness: hart0 grants=%0d hart1 grants=%0d", w0, w1);
    ck("B: BOTH harts were granted (no starvation)", (w0 > 0) && (w1 > 0));
    ck("B: grants are roughly balanced (round-robin, not priority)",
       (w0 * 4 > w1) && (w1 * 4 > w0));

    $display("=== tb_merges: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_MERGES PASS");
    else             $display("TB_MERGES BROKEN");
    $finish;
  end

  initial begin
    #200000; $display("TB_MERGES BROKEN (timeout)"); $finish;
  end

endmodule
