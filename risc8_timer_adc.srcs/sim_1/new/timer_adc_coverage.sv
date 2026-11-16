// =============================================================================
// File: timer_adc_coverage.sv
// Description: Functional coverage collector with 5 covergroups:
//              1. cg_adc_settings
//              2. cg_adc_results
//              3. cg_fifo
//              4. cg_timer
//              5. cg_interrupts
// =============================================================================

class timer_adc_coverage extends uvm_component;

    `uvm_component_utils(timer_adc_coverage)

    uvm_analysis_imp_apb #(apb_item, timer_adc_coverage) apb_imp;
    uvm_analysis_imp_adc #(adc_item, timer_adc_coverage) adc_imp;

    // Sampled variables for covergroups
    bit       tmr_en;
    bit       tmr_oneshot;
    bit [7:0] tmr_presc;
    bit [7:0] tmr_load;
    bit [7:0] tmr_cmp;

    bit       adc_en;
    bit [1:0] adc_trig_sel;
    bit [1:0] adc_ch_sel;
    bit [7:0] adc_smp;
    bit [7:0] adc_div;
    bit [7:0] adc_thr_lo;
    bit [7:0] adc_thr_hi;

    bit [1:0] conv_ch;
    bit [7:0] conv_code;
    int       win_zone; // 0: below THR_LO, 1: inside window, 2: above THR_HI

    bit [3:0] fifo_level;
    bit       fifo_empty;
    bit       fifo_full;
    bit       fifo_ovr_seen;

    bit [5:0] irq_en_val;
    bit [5:0] irq_stat_val;
    bit [5:0] irq_w1c_val;
    bit       irq_pin_val;

    // -------------------------------------------------------------------------
    // 1. ADC Settings Covergroup
    // -------------------------------------------------------------------------
    covergroup cg_adc_settings;
        option.per_instance = 1;
        cp_ch_sel: coverpoint adc_ch_sel {
            bins ch[] = {[0:3]};
        }
        cp_trig_sel: coverpoint adc_trig_sel {
            bins sw_trig  = {0};
            bins tmr_ovf  = {1};
            bins tmr_cmp  = {2};
            bins cont     = {3};
        }
        cp_smp: coverpoint adc_smp {
            bins fast = {[0:2]};
            bins med  = {[3:7]};
            bins slow = {[8:255]};
        }
        cp_div: coverpoint adc_div {
            bins div1   = {0};
            bins div2_4 = {[1:3]};
            bins div_hi = {[4:255]};
        }
        cx_ch_trig: cross cp_ch_sel, cp_trig_sel;
    endgroup

    // -------------------------------------------------------------------------
    // 2. ADC Results & Window Comparator Covergroup
    // -------------------------------------------------------------------------
    covergroup cg_adc_results;
        option.per_instance = 1;
        cp_conv_ch: coverpoint conv_ch {
            bins ch[] = {[0:3]};
        }
        cp_code_range: coverpoint conv_code {
            bins zero   = {8'h00};
            bins low    = {[8'h01:8'h3F]};
            bins mid_lo = {[8'h40:8'h7F]};
            bins mid_hi = {[8'h80:8'hBF]};
            bins high   = {[8'hC0:8'hFE]};
            bins max    = {8'hFF};
        }
        cp_window_zone: coverpoint win_zone {
            bins below_lo  = {0};
            bins in_window = {1};
            bins above_hi  = {2};
        }
        cx_ch_zone: cross cp_conv_ch, cp_window_zone;
    endgroup

    // -------------------------------------------------------------------------
    // 3. FIFO Status & Depth Covergroup
    // -------------------------------------------------------------------------
    covergroup cg_fifo;
        option.per_instance = 1;
        cp_level: coverpoint fifo_level {
            bins empty_lvl = {0};
            bins low_lvl   = {[1:3]};
            bins high_lvl  = {[4:7]};
            bins full_lvl  = {8};
        }
        cp_empty: coverpoint fifo_empty {
            bins not_empty = {0};
            bins is_empty  = {1};
        }
        cp_full: coverpoint fifo_full {
            bins not_full = {0};
            bins is_full  = {1};
        }
        cp_ovr: coverpoint fifo_ovr_seen {
            bins no_ovr  = {0};
            bins has_ovr = {1};
        }
    endgroup

    // -------------------------------------------------------------------------
    // 4. Timer Configuration & Modes Covergroup
    // -------------------------------------------------------------------------
    covergroup cg_timer;
        option.per_instance = 1;
        cp_en: coverpoint tmr_en {
            bins off = {0};
            bins on  = {1};
        }
        cp_oneshot: coverpoint tmr_oneshot {
            bins periodic = {0};
            bins oneshot  = {1};
        }
        cp_presc: coverpoint tmr_presc {
            bins div1  = {0};
            bins small_p = {[1:7]};
            bins large_p = {[8:255]};
        }
        cp_load: coverpoint tmr_load {
            bins zero_load = {0};
            bins short_prd = {[1:15]};
            bins med_prd   = {[16:254]};
            bins max_prd   = {255};
        }
        cp_cmp: coverpoint tmr_cmp {
            bins zero_duty = {0};
            bins low_duty  = {[1:127]};
            bins high_duty = {[128:255]};
        }
        cx_mode_presc: cross cp_oneshot, cp_presc;
    endgroup

    // -------------------------------------------------------------------------
    // 5. Interrupt Flags, Enables & W1C Covergroup
    // -------------------------------------------------------------------------
    covergroup cg_interrupts;
        option.per_instance = 1;
        cp_tmr_ovf:   coverpoint irq_stat_val[0] { bins seen = {1}; }
        cp_tmr_cmp:   coverpoint irq_stat_val[1] { bins seen = {1}; }
        cp_adc_eoc:   coverpoint irq_stat_val[2] { bins seen = {1}; }
        cp_adc_wd:    coverpoint irq_stat_val[3] { bins seen = {1}; }
        cp_fifo_ovr:  coverpoint irq_stat_val[4] { bins seen = {1}; }
        cp_trig_miss: coverpoint irq_stat_val[5] { bins seen = {1}; }
        cp_irq_pin:   coverpoint irq_pin_val     { bins low = {0}; bins high = {1}; }
        cp_w1c_clear: coverpoint irq_w1c_val {
            bins clr_any = {[6'h01:6'h3F]};
        }
    endgroup

    function new(string name = "timer_adc_coverage", uvm_component parent = null);
        super.new(name, parent);
        apb_imp         = new("apb_imp", this);
        adc_imp         = new("adc_imp", this);
        cg_adc_settings = new();
        cg_adc_results  = new();
        cg_fifo         = new();
        cg_timer        = new();
        cg_interrupts   = new();
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        tmr_load   = 8'hFF;
        tmr_cmp    = 8'h80;
        adc_smp    = 8'h04;
        adc_thr_hi = 8'hFF;
    endfunction

    virtual function void write_apb(apb_item item);
        irq_pin_val = item.irq;
        if (item.pwrite) begin
            case (item.paddr)
                4'h0: begin
                    tmr_en      = item.pwdata[0];
                    tmr_oneshot = item.pwdata[1];
                    cg_timer.sample();
                end
                4'h1: begin tmr_presc = item.pwdata; cg_timer.sample(); end
                4'h2: begin tmr_load  = item.pwdata; cg_timer.sample(); end
                4'h3: begin tmr_cmp   = item.pwdata; cg_timer.sample(); end
                4'h5: begin
                    adc_en       = item.pwdata[0];
                    adc_trig_sel = item.pwdata[3:2];
                    adc_ch_sel   = item.pwdata[5:4];
                    cg_adc_settings.sample();
                end
                4'h6: begin adc_smp    = item.pwdata; cg_adc_settings.sample(); end
                4'h7: begin adc_div    = item.pwdata; cg_adc_settings.sample(); end
                4'h8: begin adc_thr_lo = item.pwdata; end
                4'h9: begin adc_thr_hi = item.pwdata; end
                4'hD: begin
                    irq_en_val = item.pwdata[5:0];
                    cg_interrupts.sample();
                end
                4'hE: begin
                    irq_w1c_val = item.pwdata[5:0];
                    cg_interrupts.sample();
                end
                default: begin end
            endcase
        end else begin
            case (item.paddr)
                4'hC: begin
                    fifo_level = item.prdata[3:0];
                    fifo_empty = item.prdata[4];
                    fifo_full  = item.prdata[5];
                    cg_fifo.sample();
                end
                4'hE: begin
                    irq_stat_val  = item.prdata[5:0];
                    fifo_ovr_seen = item.prdata[4];
                    cg_fifo.sample();
                    cg_interrupts.sample();
                end
                default: begin end
            endcase
        end
    endfunction

    virtual function void write_adc(adc_item item);
        if (item.kind == ADC_CONV_EVENT) begin
            conv_ch   = item.ch;
            conv_code = item.result;
            if (item.result < adc_thr_lo)      win_zone = 0;
            else if (item.result > adc_thr_hi) win_zone = 2;
            else                               win_zone = 1;
            cg_adc_results.sample();
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COVERAGE", $sformatf(
            "Functional Coverage Summary:\n  ADC Settings : %0.1f%%\n  ADC Results  : %0.1f%%\n  FIFO         : %0.1f%%\n  Timer        : %0.1f%%\n  Interrupts   : %0.1f%%",
            cg_adc_settings.get_inst_coverage(),
            cg_adc_results.get_inst_coverage(),
            cg_fifo.get_inst_coverage(),
            cg_timer.get_inst_coverage(),
            cg_interrupts.get_inst_coverage()), UVM_LOW)
    endfunction

endclass