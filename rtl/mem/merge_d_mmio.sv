// Merges the coherent data line and the uncached MMIO word onto one master.
module merge_d_mmio
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
  output logic              d_rerr,

  input  logic       m_req,
  output logic       m_gnt,
  input  word_t      m_addr,
  input  logic       m_we,
  input  logic [3:0] m_wstrb,
  input  word_t      m_wdata,
  output logic       m_rvalid,
  output word_t      m_rdata,
  output logic       m_rerr,

  output logic              out_req,
  input  logic              out_gnt,
  output word_t             out_addr,
  output logic              out_we,
  output logic              out_word,     // 1 = single word (MMIO), 0 = line
  output logic [3:0]        out_wstrb,
  output logic [LINE_W-1:0] out_wdata,
  input  logic              out_rvalid,
  input  logic [LINE_W-1:0] out_rdata,
  input  logic              out_rerr = 1'b0,

  output logic ev_starve_m        // MMIO asking while D owns the channel
);

  typedef enum logic [1:0] { FREE, OWN_D, OWN_M } own_e;
  own_e own_q, own_d_next;

  logic pick_d, pick_m;

  assign pick_d = (own_q == FREE) && d_req;
  assign pick_m = (own_q == FREE) && m_req && !d_req;

  assign ev_starve_m = m_req && ((own_q == OWN_D) || pick_d);

  always_comb begin
    out_req   = 1'b0;
    out_addr  = '0;
    out_we    = 1'b0;
    out_word  = 1'b0;
    out_wstrb = 4'b0000;
    out_wdata = '0;
    if (pick_d || (own_q == OWN_D)) begin
      out_req   = (own_q == FREE) ? d_req : 1'b0;
      out_addr  = d_addr;
      out_we    = d_we;
      out_word  = 1'b0;                    // line
      out_wstrb = 4'b1111;
      out_wdata = d_wdata;
    end else if (pick_m || (own_q == OWN_M)) begin
      out_req   = (own_q == FREE) ? m_req : 1'b0;
      out_addr  = m_addr;
      out_we    = m_we;
      out_word  = 1'b1;                    // single word
      out_wstrb = m_wstrb;
      out_wdata = {{(LINE_W-32){1'b0}}, m_wdata};
    end
  end

  assign d_gnt = pick_d && out_gnt;
  assign m_gnt = pick_m && out_gnt;

  assign d_rvalid = out_rvalid && (own_q == OWN_D);
  assign d_rdata  = out_rdata;
  assign m_rvalid = out_rvalid && (own_q == OWN_M);
  assign m_rdata  = out_rdata[31:0];
  assign d_rerr   = out_rerr;
  assign m_rerr   = out_rerr;

  always_comb begin
    own_d_next = own_q;
    unique case (own_q)
      FREE:  if      (pick_d && out_gnt) own_d_next = OWN_D;
             else if (pick_m && out_gnt) own_d_next = OWN_M;
      OWN_D: if (out_rvalid)             own_d_next = FREE;
      OWN_M: if (out_rvalid)             own_d_next = FREE;
      default:                           own_d_next = FREE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) own_q <= FREE;
    else        own_q <= own_d_next;
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) if (rst_n) begin
    if (d_gnt && m_gnt)
      $fatal(1, "merge_d_mmio: both ports granted in one cycle");
    if (out_rvalid && (own_q == FREE))
      $fatal(1, "merge_d_mmio: response with no owner -- transaction lost");
    if (d_rvalid && m_rvalid)
      $fatal(1, "merge_d_mmio: response delivered to both ports");
  end
`endif

endmodule
