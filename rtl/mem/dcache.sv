// 1 KB two-way write-back data cache, with MESI state per line.

module dcache
  import rv32i_pkg::*;
  import mem_pkg::*;
  import coherence_pkg::*;    // snoop vocabulary + the C1 table
(
  input  logic  clk,
  input  logic  rst_n,

  input  logic       snp_valid,
  input  word_t      snp_addr,
  input  coh_snoop_e snp_type,
  output logic       snp_ack,     // response presented this cycle
  output coh_rsp_e   snp_rsp,     // rocket shrink/report encoding
  output logic       rsv_clear_o, // this snoop kills an LR reservation

  // Permission traffic only; fills and writebacks ride the line port to memory.
  output logic       coh_req_valid,
  output logic       coh_req_atomic,
  output coh_req_e   coh_req_type,
  output word_t      coh_req_addr,
  input  logic       coh_gnt,      // ordered by coherence_mgr
  input  logic       coh_done,     // transaction complete
  input  logic       coh_shared,   // aggregate shared-bit (unused for Upgrade)
  output logic       coh_installed,

  input  logic       req,
  output logic       gnt,
  input  word_t      addr,
  input  logic       we,
  input  logic       is_lr,
  input  logic [3:0] wstrb,
  input  word_t      wdata,
  output logic       rvalid,
  output word_t      rdata,
  output logic       rerr,        // with rvalid: the fill or MMIO access faulted

  input  logic  kill,

  input  logic  flush,
  output logic  flush_done,

  output logic              line_req,
  input  logic              line_gnt,
  output word_t             line_addr,
  output logic              line_we,
  output logic [LINE_W-1:0] line_wdata,
  input  logic              line_rvalid,
  input  logic [LINE_W-1:0] line_rdata,
  input  logic              line_rerr = 1'b0,

  output logic       mmio_req,
  input  logic       mmio_gnt,
  output word_t      mmio_addr,
  output logic       mmio_we,
  output logic [3:0] mmio_wstrb,
  output word_t      mmio_wdata,
  input  logic       mmio_rvalid,
  input  word_t      mmio_rdata,
  input  logic       mmio_rerr = 1'b0,

  output logic  ev_access,
  output logic  ev_miss,
  output logic  ev_wb
);

  localparam int unsigned DATA_DEPTH = SETS * WAYS;
  localparam int unsigned DATA_AW    = $clog2(DATA_DEPTH);

  dtag_t tag_q [SETS][WAYS];
  logic  lru_q [SETS];

  logic [IDX_W-1:0] s0_idx;
  logic [TAG_W-1:0] s0_tag;
  logic             s0_mmio;
  assign s0_idx  = set_idx(addr);
  assign s0_tag  = tag_of(addr);
  assign s0_mmio = is_mmio(addr);

  logic s0_hit0, s0_hit1, s0_hit, s0_way;
  assign s0_hit0 = is_valid(tag_q[s0_idx][0].state) && (tag_q[s0_idx][0].tag == s0_tag)
                   && (!we || can_write(tag_q[s0_idx][0].state));
  assign s0_hit1 = is_valid(tag_q[s0_idx][1].state) && (tag_q[s0_idx][1].tag == s0_tag)
                   && (!we || can_write(tag_q[s0_idx][1].state));
  assign s0_hit  = (s0_hit0 || s0_hit1) && !s0_mmio;
  assign s0_way  = s0_hit1;

  logic s0_tagp0, s0_tagp1, s0_tagp;
  assign s0_tagp0 = is_valid(tag_q[s0_idx][0].state) && (tag_q[s0_idx][0].tag == s0_tag);
  assign s0_tagp1 = is_valid(tag_q[s0_idx][1].state) && (tag_q[s0_idx][1].tag == s0_tag);
  assign s0_tagp  = s0_tagp0 || s0_tagp1;

  logic s0_victim;
  assign s0_victim = s0_tagp0                              ? 1'b0 :
                     s0_tagp1                              ? 1'b1 :
                     !is_valid(tag_q[s0_idx][0].state)     ? 1'b0 :
                     !is_valid(tag_q[s0_idx][1].state)     ? 1'b1 :
                                                             !lru_q[s0_idx];

  logic [IDX_W-1:0] sn_idx;
  logic [TAG_W-1:0] sn_tag;
  logic             sn_hit0, sn_hit1, sn_hit, sn_way;
  line_state_t      sn_state;

  assign sn_idx  = snp_addr[OFF_W +: IDX_W];
  assign sn_tag  = snp_addr[31 -: TAG_W];
  assign sn_hit0 = is_valid(tag_q[sn_idx][0].state) && (tag_q[sn_idx][0].tag == sn_tag);
  assign sn_hit1 = is_valid(tag_q[sn_idx][1].state) && (tag_q[sn_idx][1].tag == sn_tag);
  assign sn_hit  = sn_hit0 || sn_hit1;
  assign sn_way  = sn_hit1;
  assign sn_state = sn_hit ? tag_q[sn_idx][sn_way].state : LINE_I;

  coh_event_e  sn_ev;
  line_state_t sn_ns;
  coh_trans_e  sn_nt;
  coh_act_t    sn_act;
  logic        sn_xv;

  assign sn_ev = (snp_type == SNP_TO_S) ? EV_SNOOP_GETS : EV_SNOOP_GETM;

  mesi_ctrl u_mesi (
    .clk, .rst_n,
    .cur_state(sn_state),
    .cur_trans(TR_NONE),
    .ev_valid(snp_valid),
    .ev(sn_ev),
    .data_shared(1'b0),
    .nxt_state(sn_ns), .nxt_trans(sn_nt), .act(sn_act),
    .mshr_valid(), .mshr_req(), .x_violation(sn_xv)
  );

  logic sn_dirty_hit;
  assign sn_dirty_hit = snp_valid && sn_hit && sn_act.wb;
  assign rsv_clear_o  = snp_valid && sn_act.rsv_clear;

  logic acq_shared_q, acq_shared_d;

  logic             snwb_pend_q, snwb_pend_d;
  logic [IDX_W-1:0] snwb_idx_q,  snwb_idx_d;
  logic             snwb_way_q,  snwb_way_d;
  logic [TAG_W-1:0] snwb_tag_q,  snwb_tag_d;
  coh_rsp_e         snwb_rsp_q,  snwb_rsp_d;
  line_state_t      snwb_ns_q,   snwb_ns_d;

  typedef enum logic [1:0] { SN_IDLE, SN_READ, SN_REQ, SN_WAIT } snstate_e;
  snstate_e snstate_q, snstate_d;

  // Once a snoop has started a writeback it is answered only at completion:
  // the line's state can change under it (this cache evicting the same line),
  // and an early ack would hand the manager the wrong response.
  logic sn_busy;
  assign sn_busy = (snstate_q != SN_IDLE);
  assign snp_ack = (snp_valid && !sn_dirty_hit && !sn_busy)
                 || ((snstate_q == SN_WAIT) && line_rvalid);
  assign snp_rsp = sn_busy ? snwb_rsp_q : sn_act.snp_rsp;

  typedef enum logic [4:0] {
    D_IDLE,
    D_MISS,        // victim chosen; decide writeback or straight to fill
    D_WB_READ,     // array read of the victim line issued in the previous state
    D_WB_REQ,      // present the writeback transaction
    D_WB_WAIT,     // wait for the writeback to complete
    D_FILL_REQ,    // present the fill transaction
    D_FILL_WAIT,   // wait for the line
    D_FILL,        // write the array (merging the store), update tags, respond
    D_MMIO_REQ,
    D_MMIO_WAIT,
    D_FLUSH_SCAN,  // fence: step through sets x ways
    D_FLUSH_DONE,
    D_UPG_REQ,     // present the Upgrade to the ordering point
    D_UPG_WAIT,    // wait for it to complete, then the line is writable
    D_ACQ_REQ,     // present GetS (load miss) or GetM (store miss)
    D_ACQ_WAIT,    // wait for the ordered completion + the shared-bit
    D_UPG_DONE
  } dstate_e;

  dstate_e dstate_q, dstate_d;

  word_t             mshr_addr_q,  mshr_addr_d;
  logic [IDX_W-1:0]  mshr_idx_q,   mshr_idx_d;
  logic [TAG_W-1:0]  mshr_tag_q,   mshr_tag_d;
  logic              mshr_way_q,   mshr_way_d;
  logic              mshr_we_q,    mshr_we_d;
  logic              mshr_wi_q,    mshr_wi_d;   // write intent
  logic              upg_lr_q,     upg_lr_d;    // upgrade is LR-driven
  logic [3:0]        mshr_wstrb_q, mshr_wstrb_d;
  word_t             mshr_wdata_q, mshr_wdata_d;
  logic              mshr_kill_q,  mshr_kill_d;
  logic              upg_lost_q,   upg_lost_d;  // invalidated while the Upgrade waited
  logic              fill_err_q,   fill_err_d;
  logic [3:0]        fill_try_q,   fill_try_d;   // faulted store fills retried so far
  logic              mmio_err_q,   mmio_err_d;
  logic [LINE_W-1:0] fill_line_q,  fill_line_d;
  logic [LINE_W-1:0] wb_line_q,    wb_line_d;
  logic [TAG_W-1:0]  wb_tag_q,     wb_tag_d;
  logic [IDX_W-1:0]  wb_idx_q,     wb_idx_d;
  logic              wb_way_q,     wb_way_d;
  logic              wb_from_flush_q, wb_from_flush_d;
  logic [IDX_W:0]    fl_set_q,     fl_set_d;   // one bit wider: terminal count
  logic              fl_way_q,     fl_way_d;
  word_t             mmio_rdata_q, mmio_rdata_d;
  logic              flush_ack_q,  flush_ack_d;

  logic flush_start;
  assign flush_start = flush && !flush_ack_q;
  logic wintent;
  assign wintent = we || is_lr;
  logic upg_needed;
  assign upg_needed = req && wintent && !s0_mmio && s0_tagp
                      && !can_write(tag_q[s0_idx][s0_tagp1].state);

  logic upg_pending;
  assign upg_pending = (dstate_q == D_UPG_REQ) || (dstate_q == D_UPG_WAIT);

  logic snp_block;
  assign snp_block = (snp_valid && sn_hit) || (snstate_q != SN_IDLE);

  assign gnt = req && (dstate_q == D_IDLE) && !flush_start && !upg_needed
               && !snp_block;

  assign coh_req_valid = (dstate_q == D_UPG_REQ) || (dstate_q == D_ACQ_REQ);
  assign coh_req_type  = (dstate_q == D_UPG_REQ) ? REQ_UPGRADE
                       : (mshr_wi_q ? REQ_GETM : REQ_GETS);
  assign coh_req_addr  = {mshr_addr_q[31:OFF_W], {OFF_W{1'b0}}};
  assign coh_req_atomic = (dstate_q == D_UPG_REQ) ? upg_lr_q
                                                  : (mshr_wi_q && !mshr_we_q);
  assign coh_installed = (dstate_q == D_FILL) || (dstate_q == D_UPG_DONE);

  logic       s1_valid_q, s1_hit_q, s1_we_q;
  logic [1:0] s1_woff_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s1_valid_q <= 1'b0; s1_hit_q <= 1'b0; s1_we_q <= 1'b0; s1_woff_q <= '0;
    end else begin
      s1_valid_q <= gnt;
      s1_hit_q   <= s0_hit;
      s1_we_q    <= we;
      s1_woff_q  <= word_off(addr);
    end
  end

  logic               dat_en, dat_we_i;
  logic [DATA_AW-1:0] dat_addr;
  logic [LINE_W-1:0]  dat_wdata, dat_rdata;
  logic [LINE_W/8-1:0] dat_be;

  logic [LINE_W/8-1:0] hit_be;
  always_comb begin
    hit_be = '0;
    hit_be[word_off(addr)*4 +: 4] = wstrb;
  end

  logic [LINE_W-1:0] fill_merged;
  always_comb begin
    fill_merged = fill_line_q;
    if (mshr_we_q && !mshr_kill_q)
      for (int b = 0; b < 4; b++)
        if (mshr_wstrb_q[b])
          fill_merged[(word_off(mshr_addr_q)*4 + b)*8 +: 8] =
              mshr_wdata_q[b*8 +: 8];
  end

  logic store_hit, fill_write, wb_read;
  assign store_hit  = gnt && s0_hit && we;
  assign fill_write = (dstate_q == D_FILL) && !fill_err_q;
  logic snwb_read, sn_start;
  assign sn_start  = (snstate_q == SN_IDLE) && sn_dirty_hit && !fill_write;
  assign snwb_read = sn_start;

  assign wb_read    = ((dstate_q == D_MISS) && needs_wb(tag_q[mshr_idx_q][mshr_way_q].state))
                   || ((dstate_q == D_FLUSH_SCAN) && needs_wb(tag_q[fl_set_q[IDX_W-1:0]][fl_way_q].state));

  always_comb begin
    dat_en    = 1'b0;
    dat_we_i  = 1'b0;
    dat_addr  = {s0_idx, s0_way};
    dat_wdata = '0;
    dat_be    = '1;
    if (fill_write) begin
      dat_en = 1'b1; dat_we_i = 1'b1;
      dat_addr = {mshr_idx_q, mshr_way_q};
      dat_wdata = fill_merged;
      dat_be = '1;
    end else if (snwb_read) begin
      dat_en   = 1'b1;
      dat_addr = {sn_idx, sn_way};
    end else if (wb_read) begin
      dat_en = 1'b1;
      dat_addr = (dstate_q == D_MISS) ? {mshr_idx_q, mshr_way_q}
                                      : {fl_set_q[IDX_W-1:0], fl_way_q};
    end else if (store_hit) begin
      dat_en = 1'b1; dat_we_i = 1'b1;
      dat_addr = {s0_idx, s0_way};
      dat_wdata = {(LINE_W/32){wdata}};   // every word lane; be picks one
      dat_be = hit_be;
    end else if (gnt && s0_hit) begin
      dat_en = 1'b1;                       // load hit: read
      dat_addr = {s0_idx, s0_way};
    end
  end

  sram_1rw #(.WIDTH(LINE_W), .DEPTH(DATA_DEPTH)) u_data (
    .clk,
    .en    (dat_en),
    .we    (dat_we_i),
    .addr  (dat_addr),
    .wdata (dat_wdata),
    .be    (dat_be),
    .rdata (dat_rdata)
  );

  logic main_line_busy;
  assign main_line_busy = (dstate_q == D_WB_REQ)   || (dstate_q == D_WB_WAIT)
                       || (dstate_q == D_FILL_REQ) || (dstate_q == D_FILL_WAIT);

  always_comb begin
    snstate_d = snstate_q;
    case (snstate_q)
      SN_IDLE:  if (sn_start)                     snstate_d = SN_READ;
      SN_READ:                                    snstate_d = SN_REQ;
      SN_REQ:   if (line_gnt && !main_line_busy)  snstate_d = SN_WAIT;
      SN_WAIT:  if (line_rvalid)                  snstate_d = SN_IDLE;
      default:                                    snstate_d = SN_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) snstate_q <= SN_IDLE;
    else        snstate_q <= snstate_d;
  end

  logic [LINE_W-1:0] snwb_line_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)                    snwb_line_q <= '0;
    else if (snstate_q == SN_READ) snwb_line_q <= dat_rdata;
  end

  always_comb begin
    dstate_d        = dstate_q;
    acq_shared_d    = acq_shared_q;
    snwb_pend_d     = sn_start ? 1'b1          : snwb_pend_q;
    snwb_idx_d      = sn_start ? sn_idx        : snwb_idx_q;
    snwb_way_d      = sn_start ? sn_way        : snwb_way_q;
    snwb_tag_d      = sn_start ? sn_tag        : snwb_tag_q;
    snwb_rsp_d      = sn_start ? sn_act.snp_rsp: snwb_rsp_q;
    snwb_ns_d       = sn_start ? sn_ns         : snwb_ns_q;
    mshr_addr_d     = mshr_addr_q;  mshr_idx_d   = mshr_idx_q;
    mshr_tag_d      = mshr_tag_q;   mshr_way_d   = mshr_way_q;
    mshr_we_d       = mshr_we_q;    mshr_wstrb_d = mshr_wstrb_q;
    mshr_wi_d       = mshr_wi_q;
    upg_lr_d        = upg_lr_q;
    mshr_wdata_d    = mshr_wdata_q;
    fill_line_d     = fill_line_q;
    wb_line_d       = wb_line_q;    wb_tag_d     = wb_tag_q;
    wb_idx_d        = wb_idx_q;     wb_way_d     = wb_way_q;
    wb_from_flush_d = wb_from_flush_q;
    fl_set_d        = fl_set_q;     fl_way_d     = fl_way_q;
    mmio_rdata_d    = mmio_rdata_q;
    flush_ack_d     = flush_ack_q && flush;   // clears when the core drops it
    mshr_kill_d     = mshr_kill_q || kill;
    upg_lost_d      = upg_lost_q;
    fill_err_d      = fill_err_q;
    fill_try_d      = fill_try_q;
    mmio_err_d      = mmio_err_q;
    if (upg_pending && snp_valid && sn_hit && sn_act.inv
        && (sn_idx == mshr_idx_q) && (sn_way == mshr_way_q))
      upg_lost_d = 1'b1;

    case (dstate_q)
      D_UPG_REQ:  if (coh_gnt)  dstate_d = D_UPG_WAIT;
      D_UPG_WAIT: if (coh_done) begin
        acq_shared_d = coh_shared;
        dstate_d     = upg_lost_d ? D_MISS : D_UPG_DONE;
      end
      D_UPG_DONE: dstate_d = D_IDLE;

      D_IDLE: begin
        if (upg_needed) begin
          mshr_addr_d  = addr;
          mshr_idx_d   = s0_idx;
          mshr_tag_d   = s0_tag;
          mshr_way_d   = s0_tagp1;
          mshr_we_d    = we;
          mshr_wi_d    = wintent;
          mshr_wstrb_d = wstrb;
          mshr_wdata_d = wdata;
          mshr_kill_d  = kill;
          upg_lr_d     = is_lr && !we;
          upg_lost_d   = 1'b0;
          dstate_d     = D_UPG_REQ;
        end else
        if (flush_start) begin
          fl_set_d = '0; fl_way_d = 1'b0;
          dstate_d = D_FLUSH_SCAN;
        end else if (gnt && s0_mmio) begin
          mshr_addr_d  = addr;
          mshr_we_d    = we;
          mshr_wi_d    = wintent;
          mshr_wstrb_d = wstrb;
          mshr_wdata_d = wdata;
          mshr_kill_d  = kill;
          dstate_d     = D_MMIO_REQ;
        end else if (gnt && !s0_hit) begin
          mshr_addr_d  = addr;
          mshr_idx_d   = s0_idx;
          mshr_tag_d   = s0_tag;
          mshr_way_d   = s0_victim;
          mshr_we_d    = we;
          mshr_wi_d    = wintent;
          mshr_wstrb_d = wstrb;
          mshr_wdata_d = wdata;
          mshr_kill_d  = kill;
          fill_try_d   = '0;
          dstate_d     = D_ACQ_REQ;
        end
      end

      D_ACQ_REQ:  if (coh_gnt) dstate_d = D_ACQ_WAIT;
      D_ACQ_WAIT: if (coh_done) begin
        acq_shared_d = coh_shared;      // latch: valid only this cycle
        dstate_d     = D_MISS;
      end

      D_MISS: begin
        wb_from_flush_d = 1'b0;
        // a dirty snoop starting this cycle owns the data-array read: retry next cycle
        if (sn_start) begin
          dstate_d = D_MISS;
        end else if (needs_wb(tag_q[mshr_idx_q][mshr_way_q].state)) begin
          wb_tag_d = tag_q[mshr_idx_q][mshr_way_q].tag;
          wb_idx_d = mshr_idx_q;
          wb_way_d = mshr_way_q;
          dstate_d = D_WB_READ;
        end else begin
          dstate_d = D_FILL_REQ;
        end
      end

      D_WB_READ: begin
        wb_line_d = dat_rdata;          // synchronous read lands here
        dstate_d  = D_WB_REQ;
      end

      D_WB_REQ:  if (line_gnt)    dstate_d = D_WB_WAIT;
      D_WB_WAIT: if (line_rvalid) dstate_d = wb_from_flush_q ? D_FLUSH_SCAN
                                                             : D_FILL_REQ;

      D_FILL_REQ:  if (line_gnt)    dstate_d = D_FILL_WAIT;
      D_FILL_WAIT: if (line_rvalid) begin
        fill_line_d = line_rdata;
        fill_err_d  = line_rerr;
        // a retired store cannot fault: retry its fill a bounded number of times, then drop it
        if (line_rerr && mshr_we_q && !(&fill_try_q)) begin
          fill_try_d = fill_try_q + 4'd1;
          dstate_d   = D_FILL_REQ;
        end else begin
          dstate_d   = D_FILL;
        end
      end
      D_FILL: dstate_d = D_IDLE;

      D_MMIO_REQ:  if (mmio_gnt)    dstate_d = D_MMIO_WAIT;
      D_MMIO_WAIT: if (mmio_rvalid) begin
        mmio_rdata_d = mmio_rdata;
        mmio_err_d   = mmio_rerr;
        dstate_d     = D_IDLE;
      end

      D_FLUSH_SCAN: begin
        wb_from_flush_d = 1'b1;
        if (fl_set_q[IDX_W]) begin
          dstate_d = D_FLUSH_DONE;
        end else if (sn_start) begin
          dstate_d = D_FLUSH_SCAN;   // the snoop owns the data-array read this cycle
        end else if (needs_wb(tag_q[fl_set_q[IDX_W-1:0]][fl_way_q].state)) begin
          wb_tag_d = tag_q[fl_set_q[IDX_W-1:0]][fl_way_q].tag;
          wb_idx_d = fl_set_q[IDX_W-1:0];
          wb_way_d = fl_way_q;
          if (fl_way_q) begin fl_way_d = 1'b0; fl_set_d = fl_set_q + 1'b1; end
          else               fl_way_d = 1'b1;
          dstate_d = D_WB_READ;
        end else begin
          if (fl_way_q) begin fl_way_d = 1'b0; fl_set_d = fl_set_q + 1'b1; end
          else               fl_way_d = 1'b1;
        end
      end
      D_FLUSH_DONE: begin
        flush_ack_d = 1'b1;
        dstate_d    = D_IDLE;
      end

      default: dstate_d = D_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acq_shared_q <= 1'b0;
      snwb_pend_q <= 1'b0; snwb_idx_q <= '0; snwb_way_q <= 1'b0;
      snwb_tag_q  <= '0;   snwb_rsp_q <= RSP_NtoN; snwb_ns_q <= LINE_I;
    end else begin
      acq_shared_q <= acq_shared_d;
      snwb_pend_q <= snwb_pend_d; snwb_idx_q <= snwb_idx_d;
      snwb_way_q  <= snwb_way_d;  snwb_tag_q <= snwb_tag_d;
      snwb_rsp_q  <= snwb_rsp_d;  snwb_ns_q  <= snwb_ns_d;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dstate_q        <= D_IDLE;
      mshr_addr_q     <= '0; mshr_idx_q   <= '0; mshr_tag_q <= '0;
      mshr_way_q      <= 1'b0; mshr_we_q  <= 1'b0; mshr_wstrb_q <= '0;
      mshr_wi_q       <= 1'b0; upg_lr_q <= 1'b0;
      mshr_wdata_q    <= '0; mshr_kill_q  <= 1'b0;
      fill_line_q     <= '0; wb_line_q    <= '0;
      wb_tag_q        <= '0; wb_idx_q     <= '0; wb_way_q <= 1'b0;
      wb_from_flush_q <= 1'b0;
      fl_set_q        <= '0; fl_way_q     <= 1'b0;
      mmio_rdata_q    <= '0;
      flush_ack_q     <= 1'b0;
      upg_lost_q      <= 1'b0; fill_err_q <= 1'b0; mmio_err_q <= 1'b0;
      fill_try_q      <= '0;
    end else begin
      dstate_q        <= dstate_d;
      mshr_addr_q     <= mshr_addr_d;  mshr_idx_q   <= mshr_idx_d;
      mshr_tag_q      <= mshr_tag_d;   mshr_way_q   <= mshr_way_d;
      mshr_we_q       <= mshr_we_d;    mshr_wstrb_q <= mshr_wstrb_d;
      mshr_wi_q       <= mshr_wi_d;
      upg_lr_q        <= upg_lr_d;
      mshr_wdata_q    <= mshr_wdata_d; mshr_kill_q  <= mshr_kill_d;
      fill_line_q     <= fill_line_d;  wb_line_q    <= wb_line_d;
      wb_tag_q        <= wb_tag_d;     wb_idx_q     <= wb_idx_d;
      wb_way_q        <= wb_way_d;     wb_from_flush_q <= wb_from_flush_d;
      fl_set_q        <= fl_set_d;     fl_way_q     <= fl_way_d;
      mmio_rdata_q    <= mmio_rdata_d;
      flush_ack_q     <= flush_ack_d;
      upg_lost_q      <= upg_lost_d;
      fill_err_q      <= fill_err_d;
      fill_try_q      <= fill_try_d;
      mmio_err_q      <= mmio_err_d;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < SETS; s++) begin
        tag_q[s][0] <= '{state: LINE_I, tag: '0};
        tag_q[s][1] <= '{state: LINE_I, tag: '0};
        lru_q[s]    <= 1'b0;
      end
    end else begin
      if (gnt && s0_hit) begin
        lru_q[s0_idx] <= s0_way;
        if (we) tag_q[s0_idx][s0_way].state <= LINE_M;
      end
      if (snp_valid && sn_hit && !sn_dirty_hit)
        tag_q[sn_idx][sn_way].state <= sn_ns;
      if ((snstate_q == SN_WAIT) && line_rvalid
          && (tag_q[snwb_idx_q][snwb_way_q].tag == snwb_tag_q))   // the way may have been refilled
        tag_q[snwb_idx_q][snwb_way_q].state <= snwb_ns_q;

      if ((dstate_q == D_UPG_WAIT) && coh_done && !upg_lost_d)
        tag_q[mshr_idx_q][mshr_way_q].state <= install_state(REQ_UPGRADE, coh_shared);

      if ((dstate_q == D_FILL) && !fill_err_q) begin
        tag_q[mshr_idx_q][mshr_way_q].tag   <= mshr_tag_q;
        tag_q[mshr_idx_q][mshr_way_q].state <=
            (mshr_we_q && !mshr_kill_q) ? LINE_M
          : mshr_wi_q                   ? (acq_shared_q ? LINE_S : LINE_E)
                                        : install_state(REQ_GETS, acq_shared_q);
        lru_q[mshr_idx_q] <= mshr_way_q;
      end
      if ((dstate_q == D_WB_WAIT) && line_rvalid
          && (tag_q[wb_idx_q][wb_way_q].state == LINE_M))
        tag_q[wb_idx_q][wb_way_q].state <= LINE_E;
    end
  end

  logic sn_line_req;
  assign sn_line_req = (snstate_q == SN_REQ) && !main_line_busy;

  assign line_req   = (dstate_q == D_WB_REQ) || (dstate_q == D_FILL_REQ)
                    || sn_line_req;
  assign line_we    = (dstate_q == D_WB_REQ) || sn_line_req;
  assign line_wdata = sn_line_req ? snwb_line_q : wb_line_q;
  assign line_addr  = sn_line_req                ? line_addr_of(snwb_tag_q, snwb_idx_q)
                    : (dstate_q == D_WB_REQ)     ? line_addr_of(wb_tag_q, wb_idx_q)
                    : {mshr_addr_q[31:OFF_W], {OFF_W{1'b0}}};

  assign mmio_req   = (dstate_q == D_MMIO_REQ);
  assign mmio_addr  = mshr_addr_q;
  assign mmio_we    = mshr_we_q && !mshr_kill_q;
  assign mmio_wstrb = mshr_wstrb_q;
  assign mmio_wdata = mshr_wdata_q;

  logic       fill_resp, mmio_resp;
  logic [1:0] resp_woff;
  assign fill_resp = (dstate_q == D_FILL);
  assign mmio_resp = (dstate_q == D_MMIO_WAIT) && mmio_rvalid;
  assign resp_woff = fill_resp ? word_off(mshr_addr_q) : s1_woff_q;

  assign rvalid = (s1_valid_q && s1_hit_q) || fill_resp || mmio_resp;
  assign rerr   = (fill_resp && fill_err_q) || (mmio_resp && mmio_rerr);
  assign rdata  = mmio_resp ? mmio_rdata
                : fill_resp ? fill_merged[resp_woff*32 +: 32]
                            : dat_rdata[resp_woff*32 +: 32];

  assign flush_done = (dstate_q == D_FLUSH_DONE);

  assign ev_access = gnt;
  assign ev_miss   = gnt && !s0_hit && !s0_mmio;
  assign ev_wb     = (dstate_q == D_WB_REQ) && line_gnt;

endmodule
