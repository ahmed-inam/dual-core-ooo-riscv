// 8-entry return address stack; on overflow it freezes and counts instead.
module ras
  import rv32i_pkg::*;
#(
  parameter bit OVF_COUNT = 1'b1
) (
  input  logic     clk,
  input  logic     rst_n,

  input  logic     push,
  input  word_t    push_addr,
  input  logic     pop,

  input  logic     restore,
  input  ras_ptr_t restore_tos,
  input  ras_ovf_t restore_ovf,

  output word_t    top,
  output logic     top_valid,
  output ras_ptr_t tos_o,
  output ras_ovf_t ovf_o
);


  word_t    stack_q [RAS_DEPTH];
  word_t    stack_d [RAS_DEPTH];
  ras_ptr_t tos_q,   tos_d;
  ras_ovf_t ovf_q,   ovf_d;

  logic empty, full, off_book;
  assign empty    = (tos_q == '0);
  assign full     = (tos_q == RAS_DEPTH[RAS_PTR_W-1:0]);
  assign off_book = (ovf_q != '0);

  logic [RAS_IDX_W-1:0] top_idx;
  assign top_idx   = tos_q[RAS_IDX_W-1:0] - {{(RAS_IDX_W-1){1'b0}}, 1'b1};
  assign top       = stack_q[top_idx];
  assign top_valid = !empty;

  assign tos_o = tos_q;
  assign ovf_o = ovf_q;

  always_comb begin
    if (restore)
      tos_d = restore_tos;
    else if (pop && push)
      tos_d = empty ? tos_q + {{(RAS_PTR_W-1){1'b0}}, 1'b1} : tos_q;
    else if (pop)
      tos_d = ((OVF_COUNT && off_book) || empty)
                ? tos_q : tos_q - {{(RAS_PTR_W-1){1'b0}}, 1'b1};
    else if (push)
      tos_d = full ? tos_q : tos_q + {{(RAS_PTR_W-1){1'b0}}, 1'b1};
    else
      tos_d = tos_q;
  end

  always_comb begin
    if (restore)
      ovf_d = restore_ovf;
    else if (pop && push)
      ovf_d = ovf_q;
    else if (pop)
      ovf_d = off_book ? ovf_q - {{(RAS_OVF_W-1){1'b0}}, 1'b1} : ovf_q;
    else if (push)
      ovf_d = (full && (ovf_q != {RAS_OVF_W{1'b1}}))
                ? ovf_q + {{(RAS_OVF_W-1){1'b0}}, 1'b1} : ovf_q;
    else
      ovf_d = ovf_q;
  end

  always_comb begin
    stack_d = stack_q;
    if (pop && push) begin
      if (off_book)
        ;
      else if (empty)
        stack_d[tos_q[RAS_IDX_W-1:0]] = push_addr;
      else
        stack_d[tos_q[RAS_IDX_W-1:0] - {{(RAS_IDX_W-1){1'b0}}, 1'b1}] = push_addr;
    end
    else if (push && (!full || !OVF_COUNT)) begin
      stack_d[tos_q[RAS_IDX_W-1:0]] = push_addr;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tos_q <= '0;
      ovf_q <= '0;
      for (int i = 0; i < RAS_DEPTH; i++) stack_q[i] <= '0;
    end else begin
      tos_q   <= tos_d;
      ovf_q   <= ovf_d;
      stack_q <= stack_d;
    end
  end

endmodule
