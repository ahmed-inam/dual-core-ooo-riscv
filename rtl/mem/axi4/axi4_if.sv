// The five AXI4 channels. Lock, cache, prot and QoS are deliberately absent.

interface axi4_if #(
  parameter int ADDR_W = axi4_pkg::ADDR_WIDTH,
  parameter int DATA_W = axi4_pkg::DATA_WIDTH,
  parameter int ID_W   = axi4_pkg::ID_WIDTH,   // 4 master-facing, 5 slave-facing
  parameter int STRB_W = DATA_W / 8
) (
  input logic aclk,
  input logic arst_n
);

  logic [ID_W-1:0]   awid;
  logic [ADDR_W-1:0] awaddr;
  logic [7:0]        awlen;      // beats - 1
  logic [2:0]        awsize;     // log2(bytes per beat)
  logic [1:0]        awburst;    // plain logic, not burst_e: 2'b11 must be representable
  logic              awvalid;
  logic              awready;

  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wlast;
  logic              wvalid;
  logic              wready;

  logic [ID_W-1:0]   bid;
  logic [1:0]        bresp;
  logic              bvalid;
  logic              bready;

  logic [ID_W-1:0]   arid;
  logic [ADDR_W-1:0] araddr;
  logic [7:0]        arlen;
  logic [2:0]        arsize;
  logic [1:0]        arburst;
  logic              arvalid;
  logic              arready;

  logic [ID_W-1:0]   rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic              rlast;
  logic              rvalid;
  logic              rready;

  modport mst (
    input  aclk, arst_n,
    output awid, awaddr, awlen, awsize, awburst, awvalid,
    input  awready,
    output wdata, wstrb, wlast, wvalid,
    input  wready,
    input  bid, bresp, bvalid,
    output bready,
    output arid, araddr, arlen, arsize, arburst, arvalid,
    input  arready,
    input  rid, rdata, rresp, rlast, rvalid,
    output rready
  );

  modport slv (
    input  aclk, arst_n,
    input  awid, awaddr, awlen, awsize, awburst, awvalid,
    output awready,
    input  wdata, wstrb, wlast, wvalid,
    output wready,
    output bid, bresp, bvalid,
    input  bready,
    input  arid, araddr, arlen, arsize, arburst, arvalid,
    output arready,
    output rid, rdata, rresp, rlast, rvalid,
    input  rready
  );

  modport mon (
    input aclk, arst_n,
    input awid, awaddr, awlen, awsize, awburst, awvalid, awready,
    input wdata, wstrb, wlast, wvalid, wready,
    input bid, bresp, bvalid, bready,
    input arid, araddr, arlen, arsize, arburst, arvalid, arready,
    input rid, rdata, rresp, rlast, rvalid, rready
  );

endinterface : axi4_if
