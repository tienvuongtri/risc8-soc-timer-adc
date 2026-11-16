// =============================================================================
// File: apb_agent.sv
// Description: APB sequence item, sequencer, driver, monitor, and agent
// =============================================================================

class apb_item extends uvm_sequence_item;

    rand bit       pwrite;
    rand bit [3:0] paddr;
    rand bit [7:0] pwdata;
    bit      [7:0] prdata;
    bit            pready;
    bit            pslverr;
    bit            irq;
    bit            pwm_out;

    `uvm_object_utils_begin(apb_item)
        `uvm_field_int(pwrite,  UVM_ALL_ON)
        `uvm_field_int(paddr,   UVM_ALL_ON)
        `uvm_field_int(pwdata,  UVM_ALL_ON)
        `uvm_field_int(prdata,  UVM_ALL_ON)
        `uvm_field_int(pready,  UVM_ALL_ON)
        `uvm_field_int(pslverr, UVM_ALL_ON)
        `uvm_field_int(irq,     UVM_ALL_ON)
        `uvm_field_int(pwm_out, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "apb_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("APB %s addr=0x%01h wdata=0x%02h rdata=0x%02h irq=%0b pwm=%0b",
                         pwrite ? "WR" : "RD", paddr, pwdata, prdata, irq, pwm_out);
    endfunction

endclass

// -----------------------------------------------------------------------------
// APB Sequencer
// -----------------------------------------------------------------------------
typedef uvm_sequencer #(apb_item) apb_sequencer;

// -----------------------------------------------------------------------------
// APB Driver
// -----------------------------------------------------------------------------
class apb_driver extends uvm_driver #(apb_item);

    `uvm_component_utils(apb_driver)

    virtual apb_if vif;

    function new(string name = "apb_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("APB_DRV", "Virtual interface apb_if not found in uvm_config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_item req;

        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        vif.pwrite  <= 1'b0;
        vif.paddr   <= 4'h0;
        vif.pwdata  <= 8'h00;

        wait (vif.rst_n === 1'b1);
        @(posedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    virtual task drive_item(apb_item item);
        // Wait if reset is active
        while (vif.rst_n !== 1'b1) begin
            vif.psel    <= 1'b0;
            vif.penable <= 1'b0;
            @(posedge vif.clk);
        end

        // APB Setup phase
        @(posedge vif.clk);
        vif.psel    <= 1'b1;
        vif.penable <= 1'b0;
        vif.pwrite  <= item.pwrite;
        vif.paddr   <= item.paddr;
        vif.pwdata  <= item.pwdata;

        // APB Access phase
        @(posedge vif.clk);
        vif.penable <= 1'b1;

        // Wait for slave ready at end of Access phase
        @(posedge vif.clk);
        while (vif.pready !== 1'b1) begin
            @(posedge vif.clk);
        end

        item.prdata  = vif.prdata;
        item.pready  = vif.pready;
        item.pslverr = vif.pslverr;
        item.irq     = vif.irq;
        item.pwm_out = vif.pwm_out;

        vif.psel    <= 1'b0;
        vif.penable <= 1'b0;
        vif.pwrite  <= 1'b0;
    endtask

endclass

// -----------------------------------------------------------------------------
// APB Monitor
// -----------------------------------------------------------------------------
class apb_monitor extends uvm_monitor;

    `uvm_component_utils(apb_monitor)

    virtual apb_if               vif;
    uvm_analysis_port #(apb_item) ap;

    function new(string name = "apb_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("APB_MON", "Virtual interface apb_if not found in uvm_config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        apb_item item;

        forever begin
            @(posedge vif.clk);
            if ((vif.rst_n === 1'b1) && vif.psel && vif.penable && vif.pready) begin
                item         = apb_item::type_id::create("item", this);
                item.pwrite  = vif.pwrite;
                item.paddr   = vif.paddr;
                item.pwdata  = vif.pwdata;
                item.prdata  = vif.prdata;
                item.pready  = vif.pready;
                item.pslverr = vif.pslverr;
                item.irq     = vif.irq;
                item.pwm_out = vif.pwm_out;
                ap.write(item);
            end
        end
    endtask

endclass

// -----------------------------------------------------------------------------
// APB Agent
// -----------------------------------------------------------------------------
class apb_agent extends uvm_agent;

    `uvm_component_utils(apb_agent)

    apb_sequencer                 sqr;
    apb_driver                    drv;
    apb_monitor                   mon;
    uvm_analysis_port #(apb_item) ap;

    function new(string name = "apb_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = apb_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = apb_sequencer::type_id::create("sqr", this);
            drv = apb_driver::type_id::create("drv", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ap = mon.ap;
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction

endclass