// ONE AXI4 BURST, captured per beat.

typedef enum bit { MEM_READ = 1'b0, MEM_WRITE = 1'b1 } mem_dir_e;

class mem_txn extends uvm_sequence_item;
  `uvm_object_utils(mem_txn)

  mem_dir_e                          dir;
  logic [axi4_pkg::M_ID_W-1:0]       id;     // slave-facing width: ID + master tag bit
  word_t                             addr;
  logic [7:0]                        len;    // AXI encoding: beats - 1
  logic [2:0]                        size;   // log2(bytes per beat)
  logic [1:0]                        burst;  // FIXED/INCR/WRAP

  word_t                             beats [];
  logic [axi4_pkg::STRB_WIDTH-1:0]   strb  [];  // writes only; empty for reads

  rand logic [1:0]     resp;        // OKAY / EXOKAY / SLVERR / DECERR
  rand int unsigned    latency;     // cycles from request accepted to first beat
  rand int unsigned    beat_gap;    // idle cycles between beats

  constraint c_resp    { soft resp == 2'b00; }
  constraint c_latency { soft latency  inside {[0:32]}; }
  constraint c_gap     { soft beat_gap inside {[0:4]};  }

  longint unsigned t_req;    // cycle the request was accepted
  longint unsigned t_first;  // cycle of the first response beat
  longint unsigned t_last;   // cycle of the last  response beat

  function new(string name = "mem_txn");
    super.new(name);
  endfunction

  function int unsigned nbeats();
    return int'(len) + 1;
  endfunction

  function longint unsigned observed_latency();
    return (t_first >= t_req) ? (t_first - t_req) : 0;
  endfunction

  virtual function void do_copy(uvm_object rhs);
    mem_txn r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) `uvm_fatal("MEM_TXN", "do_copy: type mismatch")
    dir = r.dir; id = r.id; addr = r.addr; len = r.len;
    size = r.size; burst = r.burst;
    beats = new[r.beats.size()]; foreach (r.beats[i]) beats[i] = r.beats[i];
    strb  = new[r.strb.size()];  foreach (r.strb[i])  strb[i]  = r.strb[i];
    resp = r.resp; latency = r.latency; beat_gap = r.beat_gap;
    t_req = r.t_req; t_first = r.t_first; t_last = r.t_last;
  endfunction

  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    mem_txn r;
    if (!$cast(r, rhs)) return 0;
    if (dir !== r.dir || id !== r.id || addr !== r.addr) return 0;
    if (len !== r.len || size !== r.size || burst !== r.burst) return 0;
    if (beats.size() != r.beats.size()) return 0;
    foreach (beats[i]) if (beats[i] !== r.beats[i]) return 0;
    if (resp !== r.resp) return 0;
    return 1;
  endfunction

  virtual function string convert2string();
    string s;
    s = $sformatf("%s id=%0h addr=%08h len=%0d(%0d beats) size=%0d resp=%0d lat=%0d",
                  dir == MEM_WRITE ? "WR" : "RD", id, addr, len, nbeats(), size, resp,
                  observed_latency());
    foreach (beats[i]) s = {s, $sformatf("\n    beat[%0d]=%08h", i, beats[i])};
    return s;
  endfunction

endclass
