// Drives one master interface.

class axi4_mst_driver;

  virtual axi4_if #(.ID_W(ID_WIDTH)) vif;
  mailbox #(axi4_txn)                drv_mbx;
  string name = "MST_DRV";

  int unsigned bready_pct = 100;
  int unsigned rready_pct = 100;

  protected mailbox #(axi4_txn) w_mbx;
  protected mailbox #(axi4_txn) aw_mbx;
  protected mailbox #(axi4_txn) ar_mbx;

  function new(virtual axi4_if #(.ID_W(ID_WIDTH)) vif,
               mailbox #(axi4_txn) drv_mbx);
    this.vif     = vif;
    this.drv_mbx = drv_mbx;
    this.w_mbx   = new();
    this.aw_mbx  = new();
    this.ar_mbx  = new();
  endfunction

  task reset_watcher();
    forever begin
      @(negedge vif.arst_n);
      while (vif.arst_n !== 1'b1) begin
        vif.awvalid = 1'b0;
        vif.wvalid  = 1'b0;
        vif.wlast   = 1'b0;
        vif.arvalid = 1'b0;
        @(vif.aclk);
      end
    end
  endtask

  task run();
    idle();
    forever begin
      wait (vif.arst_n === 1'b1);
      @(posedge vif.aclk);
      fork
        begin
          fork
            dispatch_thread();
            aw_addr_thread();
            ar_addr_thread();
            data_thread();
            bready_thread();
            rready_thread();
          join
        end
        @(negedge vif.arst_n);
      join_any
      disable fork;
      idle();
      while (w_mbx.try_get(discard))  ;
      while (aw_mbx.try_get(discard)) ;
      while (ar_mbx.try_get(discard)) ;
    end
  endtask

  protected axi4_txn discard;

  task idle();
    vif.awvalid = 1'b0; vif.awid = '0; vif.awaddr = '0;
    vif.awlen   = '0;   vif.awsize = '0; vif.awburst = '0;
    vif.wvalid  = 1'b0; vif.wdata = '0; vif.wstrb = '0; vif.wlast = 1'b0;
    vif.arvalid = 1'b0; vif.arid = '0; vif.araddr = '0;
    vif.arlen   = '0;   vif.arsize = '0; vif.arburst = '0;
    vif.bready  = 1'b1;
    vif.rready  = 1'b1;
  endtask

  task dispatch_thread();
    forever begin
      axi4_txn t;
      drv_mbx.get(t);
      if (t.dir == WRITE) aw_mbx.put(t);
      else                ar_mbx.put(t);
    end
  endtask

  task aw_addr_thread();
    forever begin
      axi4_txn t;
      aw_mbx.get(t);
      repeat (t.delay) @(negedge vif.aclk);
      w_mbx.put(t);
      drive_aw(t);
    end
  endtask

  task ar_addr_thread();
    forever begin
      axi4_txn t;
      ar_mbx.get(t);
      repeat (t.delay) @(negedge vif.aclk);
      drive_ar(t);
    end
  endtask

  task data_thread();
    forever begin
      axi4_txn t;
      w_mbx.get(t);
      drive_w(t);
    end
  endtask

  task drive_aw(axi4_txn t);
    @(negedge vif.aclk);
    vif.awid    = t.id;   vif.awaddr  = t.addr;
    vif.awlen   = t.len;  vif.awsize  = t.size;
    vif.awburst = t.burst;
    vif.awvalid = 1'b1;
    do @(posedge vif.aclk); while (!vif.awready);
    @(negedge vif.aclk);
    vif.awvalid = 1'b0;
    if (verbose) $display("[%0t] [%s] AW %s", $time, name, t.convert2str());
  endtask

  task drive_ar(axi4_txn t);
    @(negedge vif.aclk);
    vif.arid    = t.id;   vif.araddr  = t.addr;
    vif.arlen   = t.len;  vif.arsize  = t.size;
    vif.arburst = t.burst;
    vif.arvalid = 1'b1;
    do @(posedge vif.aclk); while (!vif.arready);
    @(negedge vif.aclk);
    vif.arvalid = 1'b0;
    if (verbose) $display("[%0t] [%s] AR %s", $time, name, t.convert2str());
  endtask

  task drive_w(axi4_txn t);
    for (int i = 0; i < t.n_beats(); i++) begin
      @(negedge vif.aclk);
      vif.wdata  = t.data[i];
      vif.wstrb  = t.strb[i];
      vif.wlast  = (i == t.n_beats() - 1);
      vif.wvalid = 1'b1;
      do @(posedge vif.aclk); while (!vif.wready);
    end
    @(negedge vif.aclk);
    vif.wvalid = 1'b0;
    vif.wlast  = 1'b0;
  endtask

  task bready_thread();
    forever begin
      @(negedge vif.aclk);
      vif.bready = ($urandom_range(1, 100) <= bready_pct);
    end
  endtask

  task rready_thread();
    forever begin
      @(negedge vif.aclk);
      vif.rready = ($urandom_range(1, 100) <= rready_pct);
    end
  endtask

endclass
