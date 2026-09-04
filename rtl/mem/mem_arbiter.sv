// Shares one memory port between instruction and data traffic.

module mem_arbiter
  import rv32i_pkg::*;
  import mem_pkg::*;
(
  input  logic clk,
  input  logic rst_n,

  input  logic              d_req,
  output logic              d_gnt,
  input  word_t             d_addr,
  input  logic              d_we,
  input  logic [LINE_W-1:0] d_wdata,
  output logic              d_rvalid,
  output logic [LINE_W-1:0] d_rdata,

  input  logic       m_req,
  output logic       m_gnt,
  input  word_t      m_addr,
  input  logic       m_we,
  input  logic [3:0] m_wstrb,
  input  word_t      m_wdata,
  output logic       m_rvalid,
  output word_t      m_rdata,

  input  logic              i_req,
  output logic              i_gnt,
  input  word_t             i_addr,
  output logic              i_rvalid,
  output logic [LINE_W-1:0] i_rdata,

  output logic              out_req,
  input  logic              out_gnt,
  output word_t             out_addr,
  output logic              out_we,
  output logic              out_word,   // 1 = single word (MMIO), 0 = line
  output logic [3:0]        out_wstrb,
  output logic [LINE_W-1:0] out_wdata,
  input  logic              out_rvalid,
  input  logic [LINE_W-1:0] out_rdata,

  output logic ev_starve_i   // I-port asking while another port owns the bus
);

  typedef enum logic [1:0] { OWN_NONE, OWN_D, OWN_M, OWN_I } owner_e;
  owner_e owner_q, owner_d;

  owner_e pick;
  always_comb begin
    if      (d_req) pick = OWN_D;
    else if (m_req) pick = OWN_M;
    else if (i_req) pick = OWN_I;
    else            pick = OWN_NONE;
  end

  always_comb begin
    owner_d = owner_q;
    if (owner_q == OWN_NONE) begin
      if (pick != OWN_NONE && out_gnt) owner_d = pick;
    end else if (out_rvalid) begin
      owner_d = OWN_NONE;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) owner_q <= OWN_NONE;
    else        owner_q <= owner_d;
  end

  owner_e active;
  assign active = (owner_q == OWN_NONE) ? pick : owner_q;

  always_comb begin
    out_req   = 1'b0;
    out_addr  = '0;
    out_we    = 1'b0;
    out_word  = 1'b0;
    out_wstrb = 4'hF;
    out_wdata = '0;
    case (active)
      OWN_D: begin
        out_req   = (owner_q == OWN_NONE) ? d_req : 1'b0;
        out_addr  = d_addr;
        out_we    = d_we;
        out_wdata = d_wdata;
      end
      OWN_M: begin
        out_req   = (owner_q == OWN_NONE) ? m_req : 1'b0;
        out_addr  = m_addr;
        out_we    = m_we;
        out_word  = 1'b1;
        out_wstrb = m_wstrb;
        out_wdata = {(LINE_W/32){m_wdata}};
      end
      OWN_I: begin
        out_req   = (owner_q == OWN_NONE) ? i_req : 1'b0;
        out_addr  = i_addr;
      end
      default: ;
    endcase
  end

  assign d_gnt = (owner_q == OWN_NONE) && (pick == OWN_D) && out_gnt;
  assign m_gnt = (owner_q == OWN_NONE) && (pick == OWN_M) && out_gnt;
  assign i_gnt = (owner_q == OWN_NONE) && (pick == OWN_I) && out_gnt;

  assign d_rvalid = (owner_q == OWN_D) && out_rvalid;
  assign m_rvalid = (owner_q == OWN_M) && out_rvalid;
  assign i_rvalid = (owner_q == OWN_I) && out_rvalid;

  assign d_rdata = out_rdata;
  assign i_rdata = out_rdata;
  assign m_rdata = out_rdata[31:0];

  assign ev_starve_i = i_req && !i_gnt;

endmodule
