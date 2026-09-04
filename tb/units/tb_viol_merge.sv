// Gate for the violation merge in core.sv.
module tb_viol_merge
  import rv32i_pkg::*;
  import core_cfg_pkg::*;
  import ooo_pkg::*;
();

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  int errors = 0, checked = 0;
  task automatic ck(input string what, input logic cond);
    checked++;
    if (!cond) begin errors++; $display("  [BAD ] %s", what); end
    else                       $display("  [ok  ] %s", what);
  endtask

  logic     viol_v, snoop_v;
  rob_ptr_t viol_id, snoop_id;

  logic     viol_any;
  rob_ptr_t viol_any_id;
  logic     pend_q;
  rob_ptr_t pend_id_q;

  always_comb begin
    if (pend_q)        begin viol_any = 1'b1; viol_any_id = pend_id_q; end
    else if (viol_v)   begin viol_any = 1'b1; viol_any_id = viol_id;   end
    else if (snoop_v)  begin viol_any = 1'b1; viol_any_id = snoop_id;  end
    else               begin viol_any = 1'b0; viol_any_id = '0;        end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin pend_q <= 1'b0; pend_id_q <= '0; end
    else begin
      if (pend_q)                    pend_q <= 1'b0;
      else if (viol_v && snoop_v) begin
        pend_q    <= 1'b1;
        pend_id_q <= snoop_id;
      end
    end
  end

  int raised [int];
  int issued [int];
  int n_raised = 0, n_issued = 0;

  task automatic drive(input logic v, input rob_ptr_t vid,
                       input logic sn, input rob_ptr_t sid);
    @(negedge clk);
    viol_v = v; viol_id = vid; snoop_v = sn; snoop_id = sid;
    if (v)  begin raised[int'(vid)] += 1; n_raised++; end
    if (sn) begin raised[int'(sid)] += 1; n_raised++; end
    @(posedge clk); #1;
  endtask

  always_ff @(posedge clk) if (rst_n && viol_any) begin
    issued[int'(viol_any_id)] += 1;
    n_issued++;
  end

  int i;
  int missing;

  initial begin
    viol_v=0; snoop_v=0; viol_id='0; snoop_id='0;
    repeat (3) @(negedge clk); rst_n=1'b1; repeat (2) @(negedge clk);

    $display("=== tb_viol_merge ===");

    drive(1'b1, rob_ptr_t'(4), 1'b0, '0);
    ck("store-fill violation alone is issued", issued.exists(4) && issued[4] == 1);
    drive(1'b0, '0, 1'b0, '0);

    drive(1'b0, '0, 1'b1, rob_ptr_t'(7));
    ck("snoop hit alone is issued", issued.exists(7) && issued[7] == 1);
    drive(1'b0, '0, 1'b0, '0);

    drive(1'b1, rob_ptr_t'(11), 1'b1, rob_ptr_t'(12));
    ck("collision: the store-fill id goes out first",
       issued.exists(11) && issued[11] == 1);
    ck("collision: the snoop id is NOT issued in the same cycle",
       !issued.exists(12) || issued[12] == 0);
    drive(1'b0, '0, 1'b0, '0);           // idle cycle: the held one drains
    ck("collision: the snoop id IS issued the next cycle (not dropped)",
       issued.exists(12) && issued[12] == 1);
    drive(1'b0, '0, 1'b0, '0);

    for (i = 0; i < 300; i++) begin
      automatic logic v  = ($urandom_range(0,3) == 0);
      automatic logic sn = ($urandom_range(0,3) == 0);
      drive(v, rob_ptr_t'(20 + (i % 8)), sn, rob_ptr_t'(40 + (i % 8)));
      if (pend_q) drive(1'b0, '0, 1'b0, '0);
    end
    drive(1'b0, '0, 1'b0, '0);
    drive(1'b0, '0, 1'b0, '0);

    missing = 0;
    foreach (raised[id])
      if (!issued.exists(id) || issued[id] != raised[id]) missing++;
    $display("  [info] raised=%0d issued=%0d distinct-ids-mismatched=%0d",
             n_raised, n_issued, missing);
    ck("LIVENESS: violations were actually raised", n_raised > 20);
    ck("NO SQUASH IS EVER DROPPED (issued count == raised count per id)",
       missing == 0);
    ck("no phantom issues (total issued == total raised)", n_issued == n_raised);

    $display("=== tb_viol_merge: %0d checks, %0d error(s) ===", checked, errors);
    if (errors == 0) $display("TB_VIOL_MERGE PASS");
    else             $display("TB_VIOL_MERGE BROKEN");
    $finish;
  end

  initial begin
    #200000; $display("TB_VIOL_MERGE BROKEN (timeout)"); $finish;
  end

endmodule
