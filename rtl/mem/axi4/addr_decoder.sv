// Combinational address to destination select.

module addr_decoder
  import axi4_pkg::*;
(
  input  logic [ADDR_WIDTH-1:0] addr,
  output dest_e                 dest
);

  always_comb begin
    case (addr[DEC_MSB:DEC_LSB])
      S0_PREFIX: dest = DEST_S0;
      S1_PREFIX: dest = DEST_S1;
      default:   dest = DEST_DECERR;
    endcase
  end

endmodule : addr_decoder
