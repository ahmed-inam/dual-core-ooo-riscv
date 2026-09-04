// AXI4 protocol checker, bound into every axi4_if instance.

module axi4_assert #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int ID_W   = 4,
  parameter int STRB_W = DATA_W / 8
) (
  input logic aclk, arst_n,
  input logic ext_rst_n,

  input logic [ID_W-1:0]   awid,
  input logic [ADDR_W-1:0] awaddr,
  input logic [7:0]        awlen,
  input logic [2:0]        awsize,
  input logic [1:0]        awburst,
  input logic              awvalid, awready,

  input logic [DATA_W-1:0] wdata,
  input logic [STRB_W-1:0] wstrb,
  input logic              wlast, wvalid, wready,

  input logic [ID_W-1:0]   bid,
  input logic [1:0]        bresp,
  input logic              bvalid, bready,

  input logic [ID_W-1:0]   arid,
  input logic [ADDR_W-1:0] araddr,
  input logic [7:0]        arlen,
  input logic [2:0]        arsize,
  input logic [1:0]        arburst,
  input logic              arvalid, arready,

  input logic [ID_W-1:0]   rid,
  input logic [DATA_W-1:0] rdata,
  input logic [1:0]        rresp,
  input logic              rlast, rvalid, rready
);

  `define CHK @(posedge aclk) disable iff (!arst_n)

  always @(posedge aclk) begin
    if (!ext_rst_n) begin
      a_rst_awvalid: assert (!awvalid) else $error("AWVALID high during reset");
      a_rst_wvalid:  assert (!wvalid)  else $error("WVALID high during reset");
      a_rst_bvalid:  assert (!bvalid)  else $error("BVALID high during reset");
      a_rst_arvalid: assert (!arvalid) else $error("ARVALID high during reset");
      a_rst_rvalid:  assert (!rvalid)  else $error("RVALID high during reset");
    end
  end

  a_aw_stable: assert property (`CHK
    (awvalid && !awready) |=> (awvalid && $stable({awid,awaddr,awlen,awsize,awburst})))
    else $error("AW payload changed while stalled");

  a_w_stable: assert property (`CHK
    (wvalid && !wready) |=> (wvalid && $stable({wdata,wstrb,wlast})))
    else $error("W payload changed while stalled");

  a_b_stable: assert property (`CHK
    (bvalid && !bready) |=> (bvalid && $stable({bid,bresp})))
    else $error("B payload changed while stalled");

  a_ar_stable: assert property (`CHK
    (arvalid && !arready) |=> (arvalid && $stable({arid,araddr,arlen,arsize,arburst})))
    else $error("AR payload changed while stalled");

  a_r_stable: assert property (`CHK
    (rvalid && !rready) |=> (rvalid && $stable({rid,rdata,rresp,rlast})))
    else $error("R payload changed while stalled");

  a_awburst_legal: assert property (`CHK (awvalid && awready) |-> (awburst != 2'b11))
    else $error("AWBURST = 2'b11 is reserved");
  a_arburst_legal: assert property (`CHK (arvalid && arready) |-> (arburst != 2'b11))
    else $error("ARBURST = 2'b11 is reserved");

  a_aw_fixed_len: assert property (`CHK
    (awvalid && awready && awburst == 2'b00) |-> (awlen <= 8'd15))
    else $error("FIXED write burst longer than 16 beats");
  a_ar_fixed_len: assert property (`CHK
    (arvalid && arready && arburst == 2'b00) |-> (arlen <= 8'd15))
    else $error("FIXED read burst longer than 16 beats");

  a_aw_wrap_len: assert property (`CHK
    (awvalid && awready && awburst == 2'b10) |-> (awlen inside {8'd1,8'd3,8'd7,8'd15}))
    else $error("WRAP write burst length not 2/4/8/16");
  a_ar_wrap_len: assert property (`CHK
    (arvalid && arready && arburst == 2'b10) |-> (arlen inside {8'd1,8'd3,8'd7,8'd15}))
    else $error("WRAP read burst length not 2/4/8/16");

  function automatic logic same_4k_page(input logic [ADDR_W-1:0] addr,
                                        input logic [7:0]        len,
                                        input logic [2:0]        size);
    logic [ADDR_W+8:0] bytes, aligned, last;
    bytes   = ({{(ADDR_W+1){1'b0}}, len} + 1) << size;
    aligned = {9'b0, addr} & ~((({{(ADDR_W+8){1'b0}}, 1'b1}) << size) - 1);
    last    = aligned + bytes - 1;
    return (addr[ADDR_W-1:12] == last[ADDR_W-1:12]);
  endfunction

  a_aw_4k: assert property (`CHK
    (awvalid && awready && awburst == 2'b01) |-> same_4k_page(awaddr, awlen, awsize))
    else $error("INCR write burst crosses a 4KB boundary");
  a_ar_4k: assert property (`CHK
    (arvalid && arready && arburst == 2'b01) |-> same_4k_page(araddr, arlen, arsize))
    else $error("INCR read burst crosses a 4KB boundary");

  a_awsize_fits: assert property (`CHK
    (awvalid && awready) |-> ((8'd1 << awsize) <= STRB_W))
    else $error("AWSIZE exceeds the bus width");
  a_arsize_fits: assert property (`CHK
    (arvalid && arready) |-> ((8'd1 << arsize) <= STRB_W))
    else $error("ARSIZE exceeds the bus width");

  logic [7:0] aw_len_q[$];
  logic [7:0] w_obs_q[$];
  logic [7:0] w_beats;

  always @(posedge aclk) begin
    if (!arst_n) begin
      aw_len_q.delete(); w_obs_q.delete(); w_beats <= 0;
    end
    else begin
      if (awvalid && awready) aw_len_q.push_back(awlen);
      if (wvalid && wready) begin
        if (wlast) begin w_obs_q.push_back(w_beats); w_beats <= 0; end
        else            w_beats <= w_beats + 8'd1;
      end
      while (aw_len_q.size() > 0 && w_obs_q.size() > 0) begin
        a_wlast_count: assert (aw_len_q[0] == w_obs_q[0])
          else $error("WLAST on beat %0d, AWLEN implies %0d",
                      w_obs_q[0] + 8'd1, aw_len_q[0] + 8'd1);
        void'(aw_len_q.pop_front());
        void'(w_obs_q.pop_front());
      end
    end
  end

  logic [7:0] ar_len_q [logic [ID_W-1:0]][$];
  logic [7:0] r_beats  [logic [ID_W-1:0]];

  always @(posedge aclk) begin
    if (!arst_n) begin
      ar_len_q.delete(); r_beats.delete();
    end
    else begin
      if (arvalid && arready) ar_len_q[arid].push_back(arlen);
      if (rvalid && rready) begin
        if (!r_beats.exists(rid)) r_beats[rid] = 0;
        if (rlast) begin
          if (ar_len_q.exists(rid) && ar_len_q[rid].size() > 0) begin
            a_rlast_count: assert (ar_len_q[rid][0] == r_beats[rid])
              else $error("RLAST id %0d on beat %0d, ARLEN implies %0d",
                          rid, r_beats[rid] + 8'd1, ar_len_q[rid][0] + 8'd1);
            void'(ar_len_q[rid].pop_front());
          end
          else begin
            a_r_orphan: assert (0)
              else $error("R burst for id %0d with no matching AR", rid);
          end
          r_beats[rid] = 0;
        end
        else r_beats[rid] = r_beats[rid] + 8'd1;
      end
    end
  end

  logic [31:0] n_aw, n_wlast, n_b;

  always @(posedge aclk) begin
    if (!arst_n) begin
      n_aw <= 0; n_wlast <= 0; n_b <= 0;
    end
    else begin
      if (awvalid && awready)          n_aw    <= n_aw + 32'd1;
      if (wvalid && wready && wlast)   n_wlast <= n_wlast + 32'd1;
      if (bvalid && bready) begin
        a_b_after_aw:    assert (n_b < n_aw)
          else $error("B response with no outstanding AW");
        a_b_after_wlast: assert (n_b < n_wlast)
          else $error("BVALID before WLAST -- A3.3 dependency violation");
        n_b <= n_b + 32'd1;
      end
    end
  end

endmodule : axi4_assert

`undef CHK

`define AXI4_CHK_PORTS(IF)                                                      \
  .aclk(aclk), .arst_n(srst_n), .ext_rst_n(arst_n),   /* synchronised: the DUT's own reset */      \
  .awid(IF.awid), .awaddr(IF.awaddr), .awlen(IF.awlen), .awsize(IF.awsize),     \
  .awburst(IF.awburst), .awvalid(IF.awvalid), .awready(IF.awready),             \
  .wdata(IF.wdata), .wstrb(IF.wstrb), .wlast(IF.wlast),                         \
  .wvalid(IF.wvalid), .wready(IF.wready),                                       \
  .bid(IF.bid), .bresp(IF.bresp), .bvalid(IF.bvalid), .bready(IF.bready),       \
  .arid(IF.arid), .araddr(IF.araddr), .arlen(IF.arlen), .arsize(IF.arsize),     \
  .arburst(IF.arburst), .arvalid(IF.arvalid), .arready(IF.arready),             \
  .rid(IF.rid), .rdata(IF.rdata), .rresp(IF.rresp), .rlast(IF.rlast),           \
  .rvalid(IF.rvalid), .rready(IF.rready)

`ifndef AXI4_ASSERT_NO_BIND
bind axi4_xbar_top axi4_assert #(.ID_W(axi4_pkg::ID_WIDTH))
  u_chk_m0 (`AXI4_CHK_PORTS(m0));
bind axi4_xbar_top axi4_assert #(.ID_W(axi4_pkg::ID_WIDTH))
  u_chk_m1 (`AXI4_CHK_PORTS(m1));
bind axi4_xbar_top axi4_assert #(.ID_W(axi4_pkg::M_ID_W))
  u_chk_s0 (`AXI4_CHK_PORTS(s0));
bind axi4_xbar_top axi4_assert #(.ID_W(axi4_pkg::M_ID_W))
  u_chk_s1 (`AXI4_CHK_PORTS(s1));
`endif
