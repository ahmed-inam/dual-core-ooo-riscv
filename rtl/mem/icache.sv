// 1 KB two-way instruction cache.

module icache
  import rv32i_pkg::*;
  import mem_pkg::*;
(
  input  logic  clk,
  input  logic  rst_n,

  input  logic  req,
  output logic  gnt,
  input  word_t addr,
  output logic  rvalid,
  output word_t rdata,
  output logic  rerr,          // with rvalid: the fill faulted, nothing installed
  output logic [3:0][31:0] rdata_line,
  output logic [1:0]       rdata_woff,
  output logic [3:0]       rdata_wmask,

  input  logic  flush,

  output logic              line_req,
  input  logic              line_gnt,
  output word_t             line_addr,
  input  logic              line_rvalid,
  input  logic [LINE_W-1:0] line_rdata,
  input  logic              line_rerr = 1'b0,

  output logic  ev_access,
  output logic  ev_miss
);

  localparam int unsigned DATA_DEPTH = SETS * WAYS;
  localparam int unsigned DATA_AW    = $clog2(DATA_DEPTH);

  logic [TAG_W-1:0] tag_q   [SETS][WAYS];
  logic             valid_q [SETS][WAYS];
  logic             lru_q   [SETS];          // index of the MRU way

  logic [IDX_W-1:0] s0_idx;
  logic [TAG_W-1:0] s0_tag;
  assign s0_idx = set_idx(addr);
  assign s0_tag = tag_of(addr);

  logic s0_hit0, s0_hit1, s0_hit;
  logic s0_way;
  assign s0_hit0 = valid_q[s0_idx][0] && (tag_q[s0_idx][0] == s0_tag);
  assign s0_hit1 = valid_q[s0_idx][1] && (tag_q[s0_idx][1] == s0_tag);
  assign s0_hit  = s0_hit0 || s0_hit1;
  assign s0_way  = s0_hit1;                  // hit0 and hit1 cannot both be set

  logic s0_victim;
  assign s0_victim = !valid_q[s0_idx][0] ? 1'b0 :
                     !valid_q[s0_idx][1] ? 1'b1 :
                                           !lru_q[s0_idx];

  typedef enum logic [1:0] { M_IDLE, M_REQ, M_WAIT, M_FILL } mstate_e;
  mstate_e mstate_q;

  mstate_e          mstate_d;
  logic             miss_pend_q,  miss_pend_d;   // FSM owns the request
  logic             fill_alloc_q, fill_alloc_d;
  word_t            miss_addr_q,  miss_addr_d;
  logic [IDX_W-1:0] miss_idx_q,   miss_idx_d;
  logic [TAG_W-1:0] miss_tag_q,   miss_tag_d;
  logic             miss_way_q,   miss_way_d;
  logic [LINE_W-1:0] fill_line_q, fill_line_d;
  logic              fill_err_q,  fill_err_d;

  assign gnt = req && (mstate_q == M_IDLE) && !miss_pend_q;

  logic             s1_valid_q;
  logic             s1_hit_q;
  logic [1:0]       s1_woff_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_valid_q <= 1'b0;
      s1_hit_q   <= 1'b0;
      s1_woff_q  <= '0;
    end else begin
      s1_valid_q <= gnt;
      s1_hit_q   <= s0_hit;
      s1_woff_q  <= word_off(addr);
    end
  end

  logic                 dat_en, dat_we;
  logic [DATA_AW-1:0]   dat_addr;
  logic [LINE_W-1:0]    dat_wdata, dat_rdata;

  logic fill_write;
  assign fill_write = (mstate_q == M_FILL) && fill_alloc_q && !fill_err_q;

  assign dat_en    = gnt || fill_write;
  assign dat_we    = fill_write;
  assign dat_addr  = fill_write ? {miss_idx_q, miss_way_q} : {s0_idx, s0_way};
  assign dat_wdata = fill_line_q;

  sram_1rw #(.WIDTH(LINE_W), .DEPTH(DATA_DEPTH)) u_data (
    .clk,
    .en    (dat_en),
    .we    (dat_we),
    .addr  (dat_addr),
    .wdata (dat_wdata),
    .be    ({(LINE_W/8){1'b1}}),
    .rdata (dat_rdata)
  );

  always_comb begin
    mstate_d    = mstate_q;
    miss_pend_d = miss_pend_q;
    miss_addr_d = miss_addr_q;
    miss_idx_d  = miss_idx_q;
    miss_tag_d  = miss_tag_q;
    miss_way_d  = miss_way_q;
    fill_line_d = fill_line_q;
    fill_err_d  = fill_err_q;
    fill_alloc_d = fill_alloc_q && !flush;   // a fence.i anywhere in the fill
    case (mstate_q)
      M_IDLE: begin
        if (gnt && !s0_hit) begin
          miss_pend_d  = 1'b1;
          fill_alloc_d = !flush;
          miss_addr_d = addr;
          miss_idx_d  = s0_idx;
          miss_tag_d  = s0_tag;
          miss_way_d  = s0_victim;
          mstate_d    = M_REQ;
        end
      end
      M_REQ:  if (line_gnt)    mstate_d = M_WAIT;
      M_WAIT: if (line_rvalid) begin
        fill_line_d = line_rdata;
        fill_err_d  = line_rerr;
        mstate_d    = M_FILL;
      end
      M_FILL: begin
        miss_pend_d = 1'b0;
        mstate_d    = M_IDLE;
      end
      default: mstate_d = M_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstate_q    <= M_IDLE;
      miss_pend_q <= 1'b0;
      miss_addr_q <= '0; miss_idx_q <= '0; miss_tag_q <= '0; miss_way_q <= 1'b0;
      fill_line_q <= '0;
      fill_err_q  <= 1'b0;
      fill_alloc_q <= 1'b0;
    end else begin
      mstate_q    <= mstate_d;
      fill_err_q  <= fill_err_d;
      fill_alloc_q <= fill_alloc_d;
      miss_pend_q <= miss_pend_d;
      miss_addr_q <= miss_addr_d;
      miss_idx_q  <= miss_idx_d;
      miss_tag_q  <= miss_tag_d;
      miss_way_q  <= miss_way_d;
      fill_line_q <= fill_line_d;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < SETS; s++) begin
        valid_q[s][0] <= 1'b0;
        valid_q[s][1] <= 1'b0;
        lru_q[s]      <= 1'b0;
      end
    end else if (flush) begin
      for (int s = 0; s < SETS; s++) begin
        valid_q[s][0] <= 1'b0;
        valid_q[s][1] <= 1'b0;
      end
    end else begin
      if (gnt && s0_hit)  lru_q[s0_idx] <= s0_way;          // update on hit
      if ((mstate_q == M_FILL) && fill_alloc_q && !fill_err_q) begin
        valid_q[miss_idx_q][miss_way_q] <= 1'b1;
        tag_q  [miss_idx_q][miss_way_q] <= miss_tag_q;
        lru_q  [miss_idx_q]             <= miss_way_q;      // update on fill
      end
    end
  end

  assign line_req  = (mstate_q == M_REQ);
  assign line_addr = {miss_addr_q[31:OFF_W], {OFF_W{1'b0}}};

  logic [LINE_W-1:0] resp_line;
  logic [1:0]        resp_woff;
  logic              fill_resp;

  assign fill_resp = (mstate_q == M_FILL);
  assign resp_line = fill_resp ? fill_line_q : dat_rdata;
  assign resp_woff = fill_resp ? word_off(miss_addr_q) : s1_woff_q;

  assign rvalid = (s1_valid_q && s1_hit_q) || fill_resp;
  assign rerr   = fill_resp && fill_err_q;
  assign rdata  = resp_line[resp_woff*32 +: 32];

  always_comb begin
    for (int w = 0; w < 4; w++) begin
      rdata_line[w]  = resp_line[w*32 +: 32];
      rdata_wmask[w] = (2'(w) >= resp_woff);   // words at/after the PC offset
    end
  end
  assign rdata_woff = resp_woff;

  assign ev_access = gnt;
  assign ev_miss   = gnt && !s0_hit;

endmodule
