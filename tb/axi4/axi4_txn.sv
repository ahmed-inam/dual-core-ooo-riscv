// One AXI burst, either direction.

class axi4_txn;

  rand dir_e                     dir;
  rand logic [ID_WIDTH-1:0]      id;
  rand logic [ADDR_WIDTH-1:0]    addr;
  rand logic [7:0]               len;
  rand logic [2:0]               size;
  rand logic [1:0]               burst;
  rand int unsigned              delay;

  logic [DATA_WIDTH-1:0]         data[$];
  logic [STRB_WIDTH-1:0]         strb[$];

  logic                          tag;
  logic [1:0]                    resp;
  logic [1:0]                    beat_resp[$];
  int                            beats_seen;

  int                            issue_epoch;
  bit                            poisoned;
  int unsigned                   issued_at;
  int unsigned                   done_at;

  constraint c_burst { burst inside {2'b00, 2'b01, 2'b10}; }
  constraint c_size  { size <= $clog2(STRB_WIDTH); }
  constraint c_delay { delay inside {[0:3]}; }

  constraint c_len {
    (burst == 2'b10) -> len inside {1, 3, 7, 15};
    (burst == 2'b00) -> len <= 15;
  }

  function new();
  endfunction

  function void post_randomize();
    make_legal();
  endfunction

  function void make_legal();
    logic [ADDR_WIDTH-1:0] base;
    int unsigned           maxoff, off;

    if (!(burst inside {2'b00, 2'b01, 2'b10})) burst = 2'b01;
    if ((32'd1 << size) > STRB_WIDTH)          size  = $clog2(STRB_WIDTH);
    if (delay > 3)                             delay = delay % 4;

    case (burst)
      2'b10:   len = (len[1:0] == 0) ? 8'd1 : (len[1:0] == 1) ? 8'd3 :
                     (len[1:0] == 2) ? 8'd7 : 8'd15;
      2'b00:   if (len > 15) len = len[3:0];
      default: ;
    endcase

    base   = addr & ~32'h0000_0FFF;
    maxoff = (n_bytes() >= 4096) ? 0 : (4096 - n_bytes());
    off    = addr[11:0];
    if (off > maxoff) off = maxoff;
    if (burst == 2'b10) off = off & ~((32'd1 << size) - 1);
    addr = base | off;
  endfunction

  function int unsigned n_beats();
    return len + 1;
  endfunction

  function int unsigned n_bytes();
    return n_beats() << size;
  endfunction

  function bit crosses_4k();
    logic [ADDR_WIDTH-1:0] aligned, last;
    aligned = addr & ~((32'd1 << size) - 1);
    last    = aligned + n_bytes() - 1;
    return (addr[ADDR_WIDTH-1:12] != last[ADDR_WIDTH-1:12]);
  endfunction

  function tdest_e dest();
    if      (addr[DEC_MSB:DEC_LSB] == S0_PREFIX) return DEST_S0_T;
    else if (addr[DEC_MSB:DEC_LSB] == S1_PREFIX) return DEST_S1_T;
    else                                         return DEST_BAD;
  endfunction

  function logic [1:0] exp_resp();
    if (dest() == DEST_BAD)          return RESP_DECERR;
    if (slverr_window && addr[26])   return 2'b10;        // SLVERR
    return RESP_OKAY;
  endfunction

  function logic [ADDR_WIDTH-1:0] beat_addr(int unsigned i);
    logic [ADDR_WIDTH-1:0] aligned, base, off;
    case (burst)
      2'b00: return addr;
      2'b10: begin
               aligned = addr & ~((32'd1 << size) - 1);
               base    = aligned & ~(n_bytes() - 1);
               off     = (aligned - base) + (i << size);
               return base + (off % n_bytes());
             end
      default: begin                                        // INCR
                 if (i == 0) return addr;
                 aligned = addr & ~((32'd1 << size) - 1);
                 return aligned + (i << size);
               end
    endcase
  endfunction

  function logic [STRB_WIDTH-1:0] beat_strb(int unsigned i);
    logic [ADDR_WIDTH-1:0] a    = beat_addr(i);
    int unsigned lane           = a[$clog2(STRB_WIDTH)-1:0];
    int unsigned in_size_off    = a & ((32'd1 << size) - 1);
    int unsigned nb             = (32'd1 << size) - in_size_off;
    beat_strb = '0;
    for (int b = 0; b < nb; b++)
      if (lane + b < STRB_WIDTH) beat_strb[lane + b] = 1'b1;
  endfunction

  function void fill_incr_data(logic [DATA_WIDTH-1:0] seed);
    data.delete();
    strb.delete();
    for (int i = 0; i < n_beats(); i++) begin
      data.push_back(seed + (beat_addr(i) & 32'h0000_FFFF));
      strb.push_back(beat_strb(i));
    end
  endfunction

  function axi4_txn copy();
    copy = new();
    copy.dir   = dir;   copy.id    = id;    copy.addr  = addr;
    copy.len   = len;   copy.size  = size;  copy.burst = burst;
    copy.delay = delay; copy.resp  = resp;  copy.tag = tag;
    copy.beats_seen = beats_seen;
    copy.issue_epoch = issue_epoch;
    copy.poisoned    = poisoned;
    copy.issued_at   = issued_at;
    copy.done_at    = done_at;
    copy.data       = data;
    copy.strb       = strb;
    copy.beat_resp  = beat_resp;
  endfunction

  function string convert2str();
    return $sformatf("%-5s id=%0d addr=0x%08h len=%0d(%0d beats) size=%0d burst=%0d resp=%0d",
                     dir.name(), id, addr, len, n_beats(), size, burst, resp);
  endfunction

endclass
