module uvm_smoke;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class my_item extends uvm_sequence_item;
    `uvm_object_utils(my_item)
    rand int unsigned val;
    function new(string name = "my_item"); super.new(name); endfunction
  endclass

  class my_test extends uvm_test;
    `uvm_component_utils(my_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
      my_item it;
      phase.raise_objection(this);
      `uvm_info("SMOKE", "UVM is alive on Verilator", UVM_LOW)

      it = my_item::type_id::create("it");
      if (it == null) `uvm_error("SMOKE", "factory create returned null")
      else            `uvm_info("SMOKE", "factory create OK", UVM_LOW)

      if (!it.randomize()) `uvm_error("SMOKE", "randomize() failed")
      else                 `uvm_info("SMOKE", $sformatf("randomize OK val=%0d", it.val), UVM_LOW)

      uvm_config_db#(int)::set(null, "*", "probe_key", 42);
      begin
        int got;
        if (!uvm_config_db#(int)::get(null, "*", "probe_key", got))
          `uvm_error("SMOKE", "config_db get failed")
        else if (got != 42)
          `uvm_error("SMOKE", $sformatf("config_db mismatch got=%0d exp=42", got))
        else
          `uvm_info("SMOKE", "config_db OK", UVM_LOW)
      end

      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server svr = uvm_report_server::get_server();
      int n_err = svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL);
      if (n_err == 0) $display("GATE_A_RESULT: PASS");
      else            $display("GATE_A_RESULT: FAIL (%0d errors)", n_err);
    endfunction
  endclass

  initial run_test("my_test");
endmodule
