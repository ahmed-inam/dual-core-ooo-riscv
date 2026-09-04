// Unit proof of the physical regfile + busy table.
`timescale 1ns/1ps
module tb_prf;
  import core_cfg_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  preg_t [2*WIDTH-1:0] raddr; logic [2*WIDTH-1:0][31:0] rdata;
  logic [WAKEUP_W-1:0] wen; preg_t [WAKEUP_W-1:0] waddr;
  logic [WAKEUP_W-1:0][31:0] wdata;
  logic [WIDTH-1:0] set_busy; preg_t [WIDTH-1:0] set_preg;
  preg_t [2*WIDTH-1:0] busy_raddr; logic [2*WIDTH-1:0] busy_rdata;

  prf dut (.*);

  int errors = 0;
  task chk(string s, logic c); if (!c) begin $display("FAIL %s", s); errors++; end endtask
  task automatic idle();
    for (int i = 0; i < WAKEUP_W; i++) begin wen[i]=0; waddr[i]='0; wdata[i]='0; end
    for (int i = 0; i < WIDTH; i++)    begin set_busy[i]=0; set_preg[i]='0; end
    for (int i = 0; i < 2*WIDTH; i++)  begin raddr[i]='0; busy_raddr[i]='0; end
  endtask

  initial begin
    idle();
    #12 rst_n = 1;

    @(negedge clk);
    waddr[0] = preg_t'(0); wdata[0] = 32'hDEAD_BEEF; wen[0] = 1;
    @(negedge clk);
    wen[0] = 0; raddr[0] = preg_t'(0); busy_raddr[0] = preg_t'(0);
    @(negedge clk);
    chk("p0 reads 0 after write attempt", rdata[0] == 32'd0);
    chk("p0 never busy", busy_rdata[0] == 1'b0);

    for (int r = 1; r < PRF_N; r++) begin
      @(negedge clk);
      waddr[0] = preg_t'(r); wdata[0] = 32'hA5A5_0000 + r; wen[0] = 1;
      @(negedge clk);
      wen[0] = 0;
    end
    for (int r = 1; r < PRF_N; r++) begin
      raddr[0] = preg_t'(r);
      @(negedge clk);
      chk($sformatf("read p%0d", r), rdata[0] == 32'hA5A5_0000 + r);
    end

    @(negedge clk);
    set_preg[0] = preg_t'(9); set_busy[0] = 1;
    @(negedge clk);
    set_busy[0] = 0; busy_raddr[0] = preg_t'(9);
    @(negedge clk);   // settle a full edge: port-comb reads sample after it
    chk("p9 busy after set", busy_rdata[0] == 1'b1);
    @(negedge clk);
    waddr[0] = preg_t'(9); wdata[0] = 32'd77; wen[0] = 1;
    @(negedge clk);
    wen[0] = 0;
    @(negedge clk);
    chk("p9 clear on write", busy_rdata[0] == 1'b0);
    raddr[0] = preg_t'(9);
    @(negedge clk);
    chk("p9 value landed", rdata[0] == 32'd77);

    @(negedge clk);
    set_preg[0] = preg_t'(9); waddr[0] = preg_t'(9); wdata[0] = 32'd88;
    set_busy[0] = 1; wen[0] = 1;
    @(negedge clk);
    set_busy[0] = 0; wen[0] = 0; busy_raddr[0] = preg_t'(9);
    @(negedge clk);
    chk("set wins over clear", busy_rdata[0] == 1'b1);
    raddr[0] = preg_t'(9);
    @(negedge clk);
    chk("old value still wrote", rdata[0] == 32'd88);

    if (WAKEUP_W >= 2) begin
      @(negedge clk);
      waddr[0] = preg_t'(20); wdata[0] = 32'd111;
      waddr[1] = preg_t'(21); wdata[1] = 32'd222;
      wen[0] = 1; wen[1] = 1;
      @(negedge clk);
      wen[0] = 0; wen[1] = 0;
      raddr[0] = preg_t'(20); raddr[1 % (2*WIDTH)] = preg_t'(21);
      @(negedge clk);
      chk("dual write A", rdata[0] == 32'd111);
      chk("dual write B", rdata[1 % (2*WIDTH)] == 32'd222);
    end

    if (errors == 0) $display("PRF PASS");
    else $display("PRF FAIL: %0d", errors);
    $finish;
  end
endmodule
