// Two-flop reset synchroniser.
module rst_sync (
  input  logic aclk,
  input  logic arst_n,      // raw async reset in
  output logic srst_n       // synchronised release out
);

  (* ASYNC_REG = "TRUE" *) logic ff1, ff2;

  always_ff @(posedge aclk or negedge arst_n) begin
    if (!arst_n) begin
      ff1 <= 1'b0;
      ff2 <= 1'b0;
    end
    else begin
      ff1 <= 1'b1;
      ff2 <= ff1;
    end
  end

  assign srst_n = ff2;

endmodule : rst_sync
