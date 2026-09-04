// Physical register free list.
module freelist
  import core_cfg_pkg::*;
(
  input  logic  clk,
  input  logic  rst_n,

  output logic  [WIDTH-1:0]            can_alloc,
  input  logic  [WIDTH-1:0]            alloc_fire,
  output preg_t [WIDTH-1:0]            alloc_preg,

  input  logic  [WIDTH-1:0]            free_fire,
  input  preg_t [WIDTH-1:0]            free_preg,

  input  logic              snap_take,
  input  logic              snap_restore,
  input  snap_ptr_t         snap_id,

  output logic [PREG_W:0]   count      // free names now (watchdog + asserts)
);

  localparam int unsigned INIT_FREE = PRF_N - 32;

  typedef logic [PREG_W:0] fptr_t;
  fptr_t head_q, head_d, tail_q, tail_d;
  fptr_t snap_head_q [SNAP_N];

  preg_t ram [PRF_N];

  assign count = tail_q - head_q;

  always_comb begin
    for (int i = 0; i < WIDTH; i++) begin
      alloc_preg[i] = ram[PREG_W'(head_q + fptr_t'(i))];
      can_alloc[i]  = (count > (PREG_W+1)'(i));
    end
  end

  logic [$clog2(WIDTH+1)-1:0] n_pop, n_push;
  always_comb begin
    n_pop  = '0;
    n_push = '0;
    for (int i = 0; i < WIDTH; i++) begin
      n_pop  = n_pop  + ($bits(n_pop))'(alloc_fire[i]);
      n_push = n_push + ($bits(n_push))'(free_fire[i]);
    end
  end

  always_comb begin
    head_d = snap_restore ? snap_head_q[snap_id]
                          : head_q + fptr_t'(n_pop);
    tail_d = tail_q + fptr_t'(n_push);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head_q <= '0;
      tail_q <= fptr_t'(INIT_FREE);
      for (int i = 0; i < PRF_N; i++)
        ram[i] <= preg_t'((i < INIT_FREE) ? (32 + i) : 0);
      for (int i = 0; i < SNAP_N; i++)
        snap_head_q[i] <= '0;
    end else begin
      head_q <= head_d;
      tail_q <= tail_d;
      if (snap_take)
        snap_head_q[snap_id] <= head_q + fptr_t'(n_pop);
      begin
        automatic int unsigned k = 0;
        for (int i = 0; i < WIDTH; i++) begin
          if (free_fire[i]) begin
            ram[PREG_W'(tail_q + fptr_t'(k))] <= free_preg[i];
            k = k + 1;
          end
        end
      end
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (count > (PREG_W+1)'(INIT_FREE))
        $fatal(1, "freelist: count=%0d > %0d: DOUBLE FREE", count, INIT_FREE);
      for (int i = 0; i < WIDTH; i++)
        if (alloc_fire[i] && !can_alloc[i])
          $fatal(1, "freelist: alloc_fire[%0d] without can_alloc", i);
    end
  end
`endif

endmodule
