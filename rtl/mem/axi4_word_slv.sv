// Slave-side shim between the AXI4 interface and a word port.
module axi4_word_slv
  import rv32i_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  axi4_if.slv        sif,

  output logic       req,
  input  logic       gnt,
  output word_t      addr,
  output logic       we,
  output logic [3:0] wstrb,
  output word_t      wdata,
  input  logic       rvalid,
  input  word_t      rdata
);

  typedef enum logic [2:0] { S_IDLE, S_RD, S_WD, S_WR, S_B } st_e;
  st_e st_q, st_d;

  logic [$bits(sif.rid)-1:0]   id_q;
  word_t                       addr_q, wdata_q;
  logic [3:0]                  strb_q;
  word_t                       rdata_q;
  logic                        we_pend_q;

  assign req   = (st_q == S_RD) || (st_q == S_WR);
  assign addr  = addr_q;
  assign we    = (st_q == S_WR);
  assign wstrb = (st_q == S_WR) ? strb_q : 4'h0;
  assign wdata = wdata_q;

  assign sif.arready = (st_q == S_IDLE);
  assign sif.awready = (st_q == S_IDLE) && !sif.arvalid;   // read wins, fixed
  assign sif.wready  = (st_q == S_WD);

  assign sif.rid     = id_q;
  assign sif.rdata   = rdata_q;
  assign sif.rresp   = 2'b00;
  assign sif.rlast   = 1'b1;
  assign sif.rvalid  = (st_q == S_B) && !we_pend_q;

  assign sif.bid     = id_q;
  assign sif.bresp   = 2'b00;
  assign sif.bvalid  = (st_q == S_B) && we_pend_q;

  always_comb begin
    st_d = st_q;
    case (st_q)
      S_IDLE: begin
        if (sif.arvalid)      st_d = S_RD;
        else if (sif.awvalid) st_d = S_WD;
      end
      S_RD: if (rvalid) st_d = S_B;
      S_WD: if (sif.wvalid && sif.wready) st_d = S_WR;
      S_WR: if (rvalid || gnt) st_d = S_B;   // writes need no read data
      S_B:  if ((sif.rvalid && sif.rready) || (sif.bvalid && sif.bready))
              st_d = S_IDLE;
      default: st_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q <= S_IDLE; id_q <= '0; addr_q <= '0; wdata_q <= '0;
      strb_q <= '0; rdata_q <= '0; we_pend_q <= 1'b0;
    end else begin
      st_q <= st_d;
      if ((st_q == S_IDLE) && sif.arvalid) begin
        id_q <= sif.arid; addr_q <= sif.araddr; we_pend_q <= 1'b0;
      end else if ((st_q == S_IDLE) && sif.awvalid) begin
        id_q <= sif.awid; addr_q <= sif.awaddr; we_pend_q <= 1'b1;
      end
      if (sif.wvalid && sif.wready) begin
        wdata_q <= sif.wdata; strb_q <= sif.wstrb[3:0];
      end
      if (rvalid) rdata_q <= rdata;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (sif.arvalid && sif.arready && (sif.arlen != 8'd0))
      $fatal(1, "axi4_word_slv: burst read to a word-granular slave (arlen=%0d)", sif.arlen);
    if (sif.awvalid && sif.awready && (sif.awlen != 8'd0))
      $fatal(1, "axi4_word_slv: burst write to a word-granular slave (awlen=%0d)", sif.awlen);
    if (sif.rvalid && sif.bvalid)
      $fatal(1, "axi4_word_slv: read and write response in the same cycle");
  end
`endif

endmodule
