// =============================================================================
// File: adc_agent.sv
// Description: Analog stimulus item, sequencer, driver, monitor, and agent
// =============================================================================

typedef enum int {
    ADC_SET_VOLT   = 0,
    ADC_SET_IMPAIR = 1,
    ADC_CONV_EVENT = 2,
    TMR_OVF_EVENT  = 3,
    TMR_CMP_EVENT  = 4
} adc_ev_e;

class adc_item extends uvm_sequence_item;

    adc_ev_e   kind;
    int        target_ch; // -1 means update all 4 channels
    real       vin [4];
    real       vref;
    real       vhold;
    real       offset_v;
    real       noise_lsb;
    bit  [1:0] ch;
    bit  [7:0] result;
    bit        pwm_out;
    bit        irq;

    `uvm_object_utils_begin(adc_item)
        `uvm_field_enum(adc_ev_e, kind, UVM_ALL_ON)
        `uvm_field_int(target_ch,       UVM_ALL_ON)
        `uvm_field_int(ch,              UVM_ALL_ON)
        `uvm_field_int(result,          UVM_ALL_ON)
        `uvm_field_int(pwm_out,         UVM_ALL_ON)
        `uvm_field_int(irq,             UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adc_item");
        super.new(name);
        kind      = ADC_SET_VOLT;
        target_ch = -1;
        vin[0]    = 0.400;
        vin[1]    = 1.111;
        vin[2]    = 2.000;
        vin[3]    = 3.000;
        vref      = 3.300;
        vhold     = 0.000;
        offset_v  = 0.000;
        noise_lsb = 0.000;
    endfunction

    virtual function string convert2string();
        return $sformatf("ADC_ITEM kind=%s ch=%0d result=0x%02h vhold=%0.4fV",
                         kind.name(), ch, result, vhold);
    endfunction

endclass

// -----------------------------------------------------------------------------
// ADC Sequencer
// -----------------------------------------------------------------------------
typedef uvm_sequencer #(adc_item) adc_sequencer;

// -----------------------------------------------------------------------------
// ADC Driver (drives analog channel voltages and impairments on adc_if)
// -----------------------------------------------------------------------------
class adc_driver extends uvm_driver #(adc_item);

    `uvm_component_utils(adc_driver)

    virtual adc_if vif;

    function new(string name = "adc_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("ADC_DRV", "Virtual interface adc_if not found in uvm_config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        adc_item req;
        forever begin
            seq_item_port.get_next_item(req);
            if (req.kind == ADC_SET_VOLT) begin
                if (req.target_ch >= 0 && req.target_ch < 4) begin
                    vif.set_ch_voltage(req.target_ch, req.vin[req.target_ch]);
                end else begin
                    vif.set_all_voltages(req.vin[0], req.vin[1], req.vin[2], req.vin[3]);
                end
            end else if (req.kind == ADC_SET_IMPAIR) begin
                vif.set_analog_impairments(req.offset_v, req.noise_lsb);
            end
            seq_item_port.item_done();
        end
    endtask

endclass

// -----------------------------------------------------------------------------
// ADC & Timer Event Monitor
// -----------------------------------------------------------------------------
class adc_monitor extends uvm_monitor;

    `uvm_component_utils(adc_monitor)

    virtual adc_if                vif;
    uvm_analysis_port #(adc_item) ap;

    function new(string name = "adc_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("ADC_MON", "Virtual interface adc_if not found in uvm_config_db")
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        adc_item    ev;
        logic       eoc_s, ovf_s, cmp_s, pwm_s, irq_s;
        logic [7:0] res_s;
        logic [1:0] ch_s;
        real        vhold_s, vref_s, off_s, noise_s;
        real        vin_s [4];

        forever begin
            @(posedge vif.clk);
            if (vif.rst_n === 1'b1) begin
                // Sample hardware events in the Active region of posedge clk
                // (same clock edge where sync_fifo and apb_regs8 latch them)
                eoc_s    = vif.eoc;
                res_s    = vif.conv_result;
                ch_s     = vif.conv_ch;
                vhold_s  = vif.vhold;
                vref_s   = vif.vref;
                vin_s[0] = vif.vin[0];
                vin_s[1] = vif.vin[1];
                vin_s[2] = vif.vin[2];
                vin_s[3] = vif.vin[3];
                off_s    = vif.offset_v;
                noise_s  = vif.noise_lsb;
                ovf_s    = vif.tmr_ovf;
                cmp_s    = vif.tmr_cmp;
                pwm_s    = vif.pwm_out;
                irq_s    = vif.irq;

                // Small delay (#1ps) so same-cycle APB reads are evaluated before
                // new hardware events update the scoreboard shadow state
                #1ps;

                if (eoc_s === 1'b1) begin
                    ev           = adc_item::type_id::create("conv_ev", this);
                    ev.kind      = ADC_CONV_EVENT;
                    ev.ch        = ch_s;
                    ev.result    = res_s;
                    ev.vhold     = vhold_s;
                    ev.vref      = vref_s;
                    ev.vin[0]    = vin_s[0];
                    ev.vin[1]    = vin_s[1];
                    ev.vin[2]    = vin_s[2];
                    ev.vin[3]    = vin_s[3];
                    ev.offset_v  = off_s;
                    ev.noise_lsb = noise_s;
                    ev.pwm_out   = pwm_s;
                    ev.irq       = irq_s;
                    ap.write(ev);
                end

                if (ovf_s === 1'b1) begin
                    ev         = adc_item::type_id::create("ovf_ev", this);
                    ev.kind    = TMR_OVF_EVENT;
                    ev.pwm_out = pwm_s;
                    ev.irq     = irq_s;
                    ap.write(ev);
                end

                if (cmp_s === 1'b1) begin
                    ev         = adc_item::type_id::create("cmp_ev", this);
                    ev.kind    = TMR_CMP_EVENT;
                    ev.pwm_out = pwm_s;
                    ev.irq     = irq_s;
                    ap.write(ev);
                end
            end
        end
    endtask

endclass

// -----------------------------------------------------------------------------
// ADC Agent
// -----------------------------------------------------------------------------
class adc_agent extends uvm_agent;

    `uvm_component_utils(adc_agent)

    adc_sequencer                 sqr;
    adc_driver                    drv;
    adc_monitor                   mon;
    uvm_analysis_port #(adc_item) ap;

    function new(string name = "adc_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = adc_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = adc_sequencer::type_id::create("sqr", this);
            drv = adc_driver::type_id::create("drv", this);
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