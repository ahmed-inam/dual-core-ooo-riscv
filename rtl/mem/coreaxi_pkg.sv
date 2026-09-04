// Channel types for the core's own bus.

package coreaxi_pkg;

  localparam int unsigned AXI_ADDR_W = 32;
  localparam int unsigned AXI_DATA_W = 32;
  localparam int unsigned AXI_STRB_W = AXI_DATA_W / 8;
  localparam int unsigned AXI_ID_W   = 4;
  localparam int unsigned AXI_LEN_W  = 8;

  typedef enum logic [1:0] {
    BURST_FIXED = 2'b00,
    BURST_INCR  = 2'b01,
    BURST_WRAP  = 2'b10
  } axi_burst_e;

  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi_resp_e;

  localparam logic [2:0] AXI_SIZE_4B = 3'd2;

  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_ADDR_W-1:0] addr;
    logic [AXI_LEN_W-1:0]  len;    // beats - 1
    logic [2:0]            size;
    axi_burst_e            burst;
  } axi_ax_t;

  typedef struct packed {
    logic [AXI_DATA_W-1:0] data;
    logic [AXI_STRB_W-1:0] strb;
    logic                  last;
  } axi_w_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0] id;
    axi_resp_e           resp;
  } axi_b_t;

  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_DATA_W-1:0] data;
    axi_resp_e             resp;
    logic                  last;
  } axi_r_t;

  typedef struct packed {
    axi_ax_t aw;
    logic    aw_valid;
    axi_w_t  w;
    logic    w_valid;
    logic    b_ready;
    axi_ax_t ar;
    logic    ar_valid;
    logic    r_ready;
  } axi_req_t;

  typedef struct packed {
    logic    aw_ready;
    logic    w_ready;
    axi_b_t  b;
    logic    b_valid;
    logic    ar_ready;
    axi_r_t  r;
    logic    r_valid;
  } axi_resp_t;

  localparam axi_req_t AXI_REQ_NONE = '{
    aw: '0, aw_valid: 1'b0,
    w:  '0, w_valid:  1'b0,
    b_ready: 1'b0,
    ar: '0, ar_valid: 1'b0,
    r_ready: 1'b0
  };

endpackage
