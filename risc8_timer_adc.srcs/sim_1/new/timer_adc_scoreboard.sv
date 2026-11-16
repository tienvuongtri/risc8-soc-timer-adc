// =============================================================================
// File: timer_adc_scoreboard.sv
// Description: UVM Scoreboard with golden FIFO model, SAR ADC code predictor,
//              shadow register file, and automated checker
// =============================================================================

`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_adc)

class timer_adc_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(timer_adc_scoreboard)

    uvm_analysis_imp_apb #(apb_item, timer_adc_scoreboard) apb_imp;
    uvm_analysis_imp_adc #(adc_item, timer_adc_scoreboard) adc_imp;

    typedef struct packed {
        bit [1:0] ch;
        bit [7:0] data;
    } fifo_entry_t;

    fifo_entry_t ref_fifo[$];

    // Shadow registers
    bit [7:0] sh_tmr_ctrl;
    bit [7:0] sh_tmr_presc;
    bit [7:0] sh_tmr_load;
    bit [7:0] sh_tmr_cmp;
    bit [7:0] sh_adc_ctrl;
    bit [7:0] sh_adc_smp;
    bit [7:0] sh_adc_div;
    bit [7:0] sh_thr_lo;
    bit [7:0] sh_thr_hi;
    bit [5:0] sh_irq_en;
    bit [5:0] sh_irq_stat;

    // Statistics counters
    int conv_checked;
    int fifo_reads_checked;
    int reg_reads_checked;
    int tmr_events_checked;
    int err_cnt;

    function new(string name = "timer_adc_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        apb_imp = new("apb_imp", this);
        adc_imp = new("adc_imp", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        reset_model();
        conv_checked       = 0;
        fifo_reads_checked = 0;
        reg_reads_checked  = 0;
        tmr_events_checked = 0;
        err_cnt            = 0;
    endfunction

    // Reset reference model state
    virtual function void reset_model();
        ref_fifo.delete();
        sh_tmr_ctrl  = 8'h00;
        sh_tmr_presc = 8'h00;
        sh_tmr_load  = 8'hFF;
        sh_tmr_cmp   = 8'h80;
        sh_adc_ctrl  = 8'h00;
        sh_adc_smp   = 8'h04;
        sh_adc_div   = 8'h00;
        sh_thr_lo    = 8'h00;
        sh_thr_hi    = 8'hFF;
        sh_irq_en    = 6'h00;
        sh_irq_stat  = 6'h00;
    endfunction

    // Compute ideal 8-bit SAR ADC code from held voltage
    virtual function bit [7:0] calc_sar_code(real v, real vref);
        int code;
        real ratio;
        if (vref <= 0.0) vref = 3.3;
        ratio = (v / vref) * 256.0;
        if (ratio < 0.0) ratio = 0.0;
        // Add tiny epsilon to guard against floating-point truncation on exact steps
        code  = $rtoi(ratio + 1.0e-9);
        if (code < 0)   code = 0;
        if (code > 255) code = 255;
        return code[7:0];
    endfunction

    // Handle APB transactions from apb_monitor
    virtual function void write_apb(apb_item item);
        fifo_entry_t popped;
        bit [7:0]    exp_rch;
        bit [3:0]    exp_lvl;
        bit          exp_empty;
        bit          exp_full;

        if (item.pwrite) begin
            case (item.paddr)
                4'h0: sh_tmr_ctrl  = item.pwdata & 8'h03;
                4'h1: sh_tmr_presc = item.pwdata;
                4'h2: sh_tmr_load  = item.pwdata;
                4'h3: sh_tmr_cmp   = item.pwdata;
                4'h5: sh_adc_ctrl  = item.pwdata & 8'h3D; // bit 1 (START) self-clears
                4'h6: sh_adc_smp   = item.pwdata;
                4'h7: sh_adc_div   = item.pwdata;
                4'h8: sh_thr_lo    = item.pwdata;
                4'h9: sh_thr_hi    = item.pwdata;
                4'hD: sh_irq_en    = item.pwdata[5:0];
                4'hE: sh_irq_stat  = sh_irq_stat & ~item.pwdata[5:0]; // W1C
                default: begin end
            endcase
        end else begin
            reg_reads_checked++;
            case (item.paddr)
                4'h1: check_byte("TMR_PRESC read", item.prdata, sh_tmr_presc);
                4'h2: check_byte("TMR_LOAD read",  item.prdata, sh_tmr_load);
                4'h3: check_byte("TMR_CMP read",   item.prdata, sh_tmr_cmp);
                4'h5: check_byte("ADC_CTRL read",  item.prdata, sh_adc_ctrl);
                4'h6: check_byte("ADC_SMP read",   item.prdata, sh_adc_smp);
                4'h7: check_byte("ADC_DIV read",   item.prdata, sh_adc_div);
                4'h8: check_byte("ADC_THR_LO read",item.prdata, sh_thr_lo);
                4'h9: check_byte("ADC_THR_HI read",item.prdata, sh_thr_hi);
                4'hA: begin // ADC_DATA (pops FIFO)
                    fifo_reads_checked++;
                    if (ref_fifo.size() > 0) begin
                        popped = ref_fifo.pop_front();
                        check_byte("ADC_DATA FIFO pop", item.prdata, popped.data);
                    end else begin
                        check_byte("ADC_DATA empty read", item.prdata, 8'h00);
                    end
                end
                4'hB: begin // ADC_RCH (non-popping)
                    fifo_reads_checked++;
                    if (ref_fifo.size() > 0) begin
                        exp_rch = {1'b1, 5'b00000, ref_fifo[0].ch};
                    end else begin
                        exp_rch = 8'h00;
                    end
                    check_byte("ADC_RCH read", item.prdata, exp_rch);
                end
                4'hC: begin // ADC_STAT
                    fifo_reads_checked++;
                    exp_lvl   = ref_fifo.size();
                    exp_empty = (ref_fifo.size() == 0);
                    exp_full  = (ref_fifo.size() == 8);
                    check_byte("ADC_STAT[5:0] (FULL/EMPTY/LEVEL)",
                               item.prdata & 8'h3F,
                               {2'b00, exp_full, exp_empty, exp_lvl});
                end
                4'hD: check_byte("IRQ_EN read", item.prdata, {2'b00, sh_irq_en});
                4'hF: check_byte("ID read",     item.prdata, 8'hA8);
                default: begin end
            endcase
        end
    endfunction

    // Handle ADC conversion and Timer events from adc_monitor
    virtual function void write_adc(adc_item item);
        bit [7:0]    exp_code;
        bit [7:0]    nom_code;
        int          diff_code;
        int          max_tol_lsb;
        real         abs_offset_v;
        fifo_entry_t new_entry;

        if (item.kind == ADC_CONV_EVENT) begin
            conv_checked++;

            // 1. Check digital SAR conversion against actual held voltage (vhold)
            exp_code  = calc_sar_code(item.vhold, item.vref);
            diff_code = (item.result > exp_code) ? (item.result - exp_code) : (exp_code - item.result);
            if (diff_code > 1) begin
                err_cnt++;
                `uvm_error("SB_ADC", $sformatf(
                    "SAR code mismatch on CH%0d: actual=0x%02h, expected=0x%02h (vhold=%0.4fV)",
                    item.ch, item.result, exp_code, item.vhold))
            end

            // 2. If analog offset/noise is active, also verify against nominal channel input within tolerance
            if ((item.noise_lsb > 0.0) || (item.offset_v != 0.0)) begin
                abs_offset_v = (item.offset_v < 0.0) ? -item.offset_v : item.offset_v;
                nom_code     = calc_sar_code(item.vin[item.ch], item.vref);
                max_tol_lsb  = $rtoi(item.noise_lsb + (abs_offset_v / (item.vref / 256.0)) + 2.999999);
                diff_code    = (item.result > nom_code) ? (item.result - nom_code) : (nom_code - item.result);
                if (diff_code > max_tol_lsb) begin
                    err_cnt++;
                    `uvm_error("SB_NOISE", $sformatf(
                        "Noisy code out of tolerance on CH%0d: actual=%0d, nominal=%0d, max_tol=%0d LSB",
                        item.ch, item.result, nom_code, max_tol_lsb))
                end
            end

            // 3. Update reference FIFO and sticky flags
            sh_irq_stat[2] = 1'b1; // ADC_EOC
            if ((item.result < sh_thr_lo) || (item.result > sh_thr_hi)) begin
                sh_irq_stat[3] = 1'b1; // ADC_WD
            end

            if (ref_fifo.size() < 8) begin
                new_entry.ch   = item.ch;
                new_entry.data = item.result;
                ref_fifo.push_back(new_entry);
            end else begin
                sh_irq_stat[4] = 1'b1; // FIFO_OVR (sample dropped when full)
            end

        end else if (item.kind == TMR_OVF_EVENT) begin
            tmr_events_checked++;
            sh_irq_stat[0] = 1'b1; // TMR_OVF
            if (sh_tmr_ctrl[1]) begin
                sh_tmr_ctrl[0] = 1'b0; // One-shot clears EN
            end
        end else if (item.kind == TMR_CMP_EVENT) begin
            tmr_events_checked++;
            sh_irq_stat[1] = 1'b1; // TMR_CMP
        end
    endfunction

    virtual function void check_byte(string label, bit [7:0] actual, bit [7:0] expected);
        if (actual !== expected) begin
            err_cnt++;
            `uvm_error("SB_REG", $sformatf("%s mismatch: actual=0x%02h, expected=0x%02h",
                                           label, actual, expected))
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SCOREBOARD", $sformatf(
            "Summary: conversions=%0d, fifo_reads=%0d, reg_reads=%0d, timer_events=%0d, errors=%0d",
            conv_checked, fifo_reads_checked, reg_reads_checked, tmr_events_checked, err_cnt), UVM_LOW)
        if (err_cnt == 0) begin
            `uvm_info("SCOREBOARD", "*** UVM SCOREBOARD PASSED ***", UVM_LOW)
        end else begin
            `uvm_error("SCOREBOARD", $sformatf("*** UVM SCOREBOARD FAILED WITH %0d ERRORS ***", err_cnt))
        end
    endfunction

endclass