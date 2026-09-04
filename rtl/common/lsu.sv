// Load and store alignment, sign extension, and byte masks.

module lsu
  import rv32i_pkg::*;
(
  input  logic       mem_re,            // load
  input  logic       mem_we,            // store

  input  logic       is_lr,
  input  logic       is_sc,
  input  logic       sc_success,
  input  mem_size_e  mem_size,          // B / H / W / BU / HU
  input  word_t      addr,              // from ALU: rs1 + imm
  input  word_t      rs2_data,          // value to store

  output word_t      mem_wdata,         // rs2_data positioned into its lane(s)
  output logic [3:0] mem_wstrb,         // which byte lanes to actually write
  input  word_t      mem_rdata,         // the 32-bit word memory returned

  output word_t      load_data,         // extracted + extended

  output logic       load_misaligned,
  output logic       store_misaligned
);


  logic [7:0]  sel_byte;
  logic [15:0] sel_half;

  always_comb begin
    case (addr[1:0])
      2'd0:    sel_byte = mem_rdata[7:0];
      2'd1:    sel_byte = mem_rdata[15:8];
      2'd2:    sel_byte = mem_rdata[23:16];
      default: sel_byte = mem_rdata[31:24];
    endcase

    sel_half = addr[1] ? mem_rdata[31:16] : mem_rdata[15:0];
  end

  always_comb begin
    case (mem_size)
      MEM_B:   load_data = {{24{sel_byte[7]}},  sel_byte};   // sign-extend
      MEM_BU:  load_data = { 24'b0,             sel_byte};   // zero-extend
      MEM_H:   load_data = {{16{sel_half[15]}}, sel_half};   // sign-extend
      MEM_HU:  load_data = { 16'b0,             sel_half};   // zero-extend
      MEM_W:   load_data = mem_rdata;                        // no extension
      default: load_data = '0;                               // MEM_NONE
    endcase
    if (is_sc) load_data = sc_success ? 32'd0 : 32'd1;
  end

  always_comb begin
    case (mem_size)
      MEM_B, MEM_BU: mem_wdata = {4{rs2_data[7:0]}};
      MEM_H, MEM_HU: mem_wdata = {2{rs2_data[15:0]}};
      MEM_W:         mem_wdata = rs2_data;
      default:       mem_wdata = rs2_data;
    endcase
  end

  logic [3:0] strb;

  always_comb begin
    case (mem_size)
      MEM_B, MEM_BU: case (addr[1:0])
                       2'd0:    strb = 4'b0001;
                       2'd1:    strb = 4'b0010;
                       2'd2:    strb = 4'b0100;
                       default: strb = 4'b1000;
                     endcase
      MEM_H, MEM_HU: strb = addr[1] ? 4'b1100 : 4'b0011;
      MEM_W:         strb = 4'b1111;
      default:       strb = 4'b0000;
    endcase
  end

  assign mem_wstrb = (mem_we && !(is_sc && !sc_success)) ? strb : 4'b0000;

  logic misaligned;

  always_comb begin
    case (mem_size)
      MEM_W:         misaligned = (addr[1:0] != 2'b00);
      MEM_H, MEM_HU: misaligned = (addr[0]   != 1'b0);
      MEM_B, MEM_BU: misaligned = 1'b0;              // byte access always legal
      default:       misaligned = 1'b0;
    endcase
  end

  assign load_misaligned  = mem_re && misaligned;
  assign store_misaligned = mem_we && misaligned;

endmodule
