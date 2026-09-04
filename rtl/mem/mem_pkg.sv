// Core-to-cache request, grant and response types.
`timescale 1ns/1ps
package mem_pkg;

`ifndef CACHE_BYTES_CFG
  `define CACHE_BYTES_CFG 1024
`endif
  localparam int unsigned CACHE_BYTES    = `CACHE_BYTES_CFG;
  localparam int unsigned LINE_BYTES     = 16;
  localparam int unsigned WAYS           = 2;
  localparam int unsigned SETS           = CACHE_BYTES / (LINE_BYTES * WAYS);
  localparam int unsigned OFF_W          = $clog2(LINE_BYTES);
  localparam int unsigned IDX_W          = $clog2(SETS);
`ifdef XOR_INDEX
  localparam int unsigned TAG_W          = 32 - OFF_W;
`else
  localparam int unsigned TAG_W          = 32 - IDX_W - OFF_W;
`endif
  localparam int unsigned BEATS_PER_LINE = LINE_BYTES / 4;
  localparam int unsigned LINE_W         = LINE_BYTES * 8;

  localparam logic [31:0] RAM_BASE   = 32'h8000_0000;
  localparam logic [31:0] CLINT_BASE = 32'h0200_0000;
  localparam logic [31:0] CLINT_MASK = 32'hFFFF_0000;

  typedef struct packed {
    logic             valid;
    logic [TAG_W-1:0] tag;
  } itag_t;

  typedef enum logic [2:0] {
    LINE_I = 3'd0,
    LINE_S = 3'd1,
    LINE_E = 3'd2,
    LINE_O = 3'd3,
    LINE_M = 3'd4
  } line_state_t;

  typedef struct packed {
    line_state_t      state;
    logic [TAG_W-1:0] tag;
  } dtag_t;

  function automatic logic is_valid(input line_state_t s);
    return s != LINE_I;
  endfunction

  function automatic logic can_write(input line_state_t s);
    return (s == LINE_E) || (s == LINE_M);
  endfunction

  function automatic logic needs_wb(input line_state_t s);
    return (s == LINE_M) || (s == LINE_O);
  endfunction

  typedef struct packed {
    logic [31:0] addr;
    logic        we;
    logic [3:0]  wstrb;
    logic [31:0] wdata;
  } mem_req_t;

  typedef struct packed {
    logic [31:0]       addr;
    logic              we;
    logic [LINE_W-1:0] wdata;
  } line_req_t;

`ifdef XOR_INDEX
  function automatic logic [IDX_W-1:0] set_idx(input logic [31:0] addr);
    return addr[OFF_W+IDX_W-1:OFF_W] ^ addr[OFF_W+2*IDX_W-1:OFF_W+IDX_W];
  endfunction
`else
  function automatic logic [IDX_W-1:0] set_idx(input logic [31:0] addr);
    return addr[OFF_W+IDX_W-1:OFF_W];
  endfunction
`endif

`ifdef XOR_INDEX
  function automatic logic [TAG_W-1:0] tag_of(input logic [31:0] addr);
    return addr[31:OFF_W];
  endfunction
  function automatic logic [31:0] line_addr_of(input logic [TAG_W-1:0] t,
                                               input logic [IDX_W-1:0] i);
    return {t, {OFF_W{1'b0}}};
  endfunction
`else
  function automatic logic [TAG_W-1:0] tag_of(input logic [31:0] addr);
    return addr[31:OFF_W+IDX_W];
  endfunction
  function automatic logic [31:0] line_addr_of(input logic [TAG_W-1:0] t,
                                               input logic [IDX_W-1:0] i);
    return {t, i, {OFF_W{1'b0}}};
  endfunction
`endif

  function automatic logic [1:0] word_off(input logic [31:0] addr);
    return addr[3:2];
  endfunction

  function automatic logic is_mmio(input logic [31:0] addr);
    return (addr & CLINT_MASK) == CLINT_BASE;
  endfunction

  function automatic logic is_ram(input logic [31:0] addr);   // the only region a line fill may target
    return addr[31:28] == RAM_BASE[31:28];
  endfunction

endpackage
