// Timer and software interrupts: per-hart msip and mtimecmp.
module clint
  import rv32i_pkg::*;
  import mem_pkg::*;
  import platform_cfg_pkg::*;
(
  input  logic  clk,
  input  logic  rst_n,

  input  logic       req,
  output logic       gnt,
  input  word_t      addr,
  input  logic       we,
  input  logic [3:0] wstrb,
  input  word_t      wdata,
  output logic       rvalid,
  output word_t      rdata,

  input  logic       rtc_tick,

  output logic [NUM_HARTS-1:0] msip_o,   // machine software interrupt pending
  output logic [NUM_HARTS-1:0] mtip_o    // machine timer    interrupt pending
);

  localparam logic [15:0] MTIMECMP_BASE = 16'h4000;   // + hart*8, 64 bits each
  localparam logic [15:0] MTIME_LO      = 16'hBFF8;
  localparam logic [15:0] MTIME_HI      = 16'hBFFC;

  logic [63:0]                mtime_q,    mtime_d;
  logic [63:0]                mtimecmp_q  [NUM_HARTS];
  logic [63:0]                mtimecmp_d  [NUM_HARTS];
  logic [NUM_HARTS-1:0]       msip_q,     msip_d;

  assign gnt = req;

  logic  resp_q;
  word_t rdata_q;
  assign rvalid = resp_q;
  assign rdata  = rdata_q;

  logic [15:0] off;
  assign off = 16'(addr - CLINT_BASE);

  logic                  sel_msip, sel_mtimecmp, sel_mtime_lo, sel_mtime_hi;
  logic [31:0]           msip_idx, cmp_idx;
  logic                  cmp_hi;      // 1 = upper word of the 64-bit mtimecmp

  always_comb begin
    msip_idx     = 32'(off[15:2]);                  // /4
    cmp_idx      = {19'd0, off[15:3]} - {19'd0, MTIMECMP_BASE[15:3]};
    cmp_hi       = off[2];
    sel_msip     = (off < 16'(NUM_HARTS*4));
    sel_mtimecmp = (off >= MTIMECMP_BASE) && (off < MTIMECMP_BASE + 16'(NUM_HARTS*8));
    sel_mtime_lo = (off == MTIME_LO);
    sel_mtime_hi = (off == MTIME_HI);
  end

  function automatic word_t merge_w(word_t old_w, word_t new_w, logic [3:0] str);
    word_t r;
    for (int b = 0; b < 4; b++)
      r[8*b +: 8] = str[b] ? new_w[8*b +: 8] : old_w[8*b +: 8];
    return r;
  endfunction

  always_comb begin
    mtime_d    = mtime_q;
    msip_d     = msip_q;
    for (int h = 0; h < NUM_HARTS; h++) mtimecmp_d[h] = mtimecmp_q[h];

    if (rtc_tick) mtime_d = mtime_q + 64'd1;

    if (req && we) begin
      if (sel_msip) begin
        if (wstrb[0] && msip_idx < NUM_HARTS)
          msip_d[msip_idx[HART_W-1:0]] = wdata[0];
      end else if (sel_mtimecmp) begin
        if (cmp_idx < NUM_HARTS) begin
          if (cmp_hi)
            mtimecmp_d[cmp_idx[HART_W-1:0]][63:32] =
              merge_w(mtimecmp_q[cmp_idx[HART_W-1:0]][63:32], wdata, wstrb);
          else
            mtimecmp_d[cmp_idx[HART_W-1:0]][31:0]  =
              merge_w(mtimecmp_q[cmp_idx[HART_W-1:0]][31:0],  wdata, wstrb);
        end
      end else if (sel_mtime_lo) begin
        mtime_d[31:0]  = merge_w(mtime_q[31:0],  wdata, wstrb);
      end else if (sel_mtime_hi) begin
        mtime_d[63:32] = merge_w(mtime_q[63:32], wdata, wstrb);
      end
    end
  end

  word_t rdata_sel;
  always_comb begin
    rdata_sel = 32'd0;                              // unmapped reads return 0
    if (sel_msip && msip_idx < NUM_HARTS)
      rdata_sel = {31'd0, msip_q[msip_idx[HART_W-1:0]]};
    else if (sel_mtimecmp && cmp_idx < NUM_HARTS)
      rdata_sel = cmp_hi ? mtimecmp_q[cmp_idx[HART_W-1:0]][63:32]
                         : mtimecmp_q[cmp_idx[HART_W-1:0]][31:0];
    else if (sel_mtime_lo) rdata_sel = mtime_q[31:0];
    else if (sel_mtime_hi) rdata_sel = mtime_q[63:32];
  end

  always_comb begin
    for (int h = 0; h < NUM_HARTS; h++) begin
      msip_o[h] = msip_q[h];
      mtip_o[h] = (mtime_q >= mtimecmp_q[h]);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mtime_q <= 64'd0;
      msip_q  <= '0;                                 // cva6: msip resets clear
      for (int h = 0; h < NUM_HARTS; h++)
        mtimecmp_q[h] <= {64{1'b1}};                 // see header: never-expired
      resp_q  <= 1'b0;
      rdata_q <= 32'd0;
    end else begin
      mtime_q <= mtime_d;
      msip_q  <= msip_d;
      for (int h = 0; h < NUM_HARTS; h++)
        mtimecmp_q[h] <= mtimecmp_d[h];
      resp_q  <= req;                                // accepted this cycle
      rdata_q <= rdata_sel;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    for (int h = 0; h < NUM_HARTS; h++)
      if (mtimecmp_q[h] == {64{1'b1}} && mtip_o[h])
        $fatal(1, "clint: mtip[%0d] asserted with mtimecmp never-expired", h);
    if (resp_q && req && !gnt)
      $fatal(1, "clint: gnt must be high whenever req is");
  end
`endif

endmodule
