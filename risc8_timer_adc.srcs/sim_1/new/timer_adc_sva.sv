`timescale 1ns / 1ps

module timer_adc_sva (
    input logic       clk,
    input logic       rst_n,
    // APB interface signals
    input logic       psel,
    input logic       penable,
    input logic       pwrite,
    input logic [3:0] paddr,
    input logic [7:0] pwdata,
    input logic [7:0] prdata,
    input logic       pready,
    input logic       pslverr,
    // Top-level outputs
    input logic       irq,
    input logic       pwm_out,
    input logic       adc_sample,
    input logic [1:0] adc_ch,
    input logic [7:0] adc_dac,
    input logic       adc_cmp,
    // Internal Timer signals
    input logic       tmr_en,
    input logic       tmr_oneshot,
    input logic [7:0] tmr_presc,
    input logic [7:0] tmr_load,
    input logic [7:0] tmr_cmp,
    input logic [7:0] tmr_cnt,
    input logic       tmr_ovf_pulse,
    input logic       tmr_cmp_pulse,
    // Internal ADC signals
    input logic       adc_en,
    input logic       adc_start,
    input logic       adc_cont_mode,
    input logic [1:0] adc_ch_sel,
    input logic [7:0] adc_smp,
    input logic [7:0] adc_div,
    input logic       adc_busy,
    input logic       adc_eoc,
    input logic [7:0] adc_result,
    // Internal FIFO signals
    input logic [7:0] fifo_rd_data,
    input logic [1:0] fifo_rd_ch,
    input logic       fifo_full,
    input logic       fifo_empty,
    input logic [3:0] fifo_level,
    input logic       fifo_overflow,
    input logic       fifo_pop,
    // Internal IRQ & threshold registers
    input logic [5:0] irq_en,
    input logic [5:0] irq_stat,
    input logic [7:0] adc_thr_lo,
    input logic [7:0] adc_thr_hi
);

    default clocking cb @(posedge clk);
    endclocking

    wire apb_wr_tmr_ctrl = psel && penable && pwrite && (paddr == 4'h0);
    wire apb_wr_tmr_load = psel && penable && pwrite && (paddr == 4'h2);
    wire apb_wr_irq_stat = psel && penable && pwrite && (paddr == 4'hE);

    // =========================================================================
    // Group 1: Timer Assertions (8 rules)
    // =========================================================================

    // 1. Timer count must never exceed LOAD while enabled (unless LOAD was just rewritten)
    a_cnt_le_load: assert property (
        disable iff (!rst_n)
        (tmr_en && !$past(apb_wr_tmr_load)) |-> (tmr_cnt <= tmr_load)
    ) else $error("[SVA] a_cnt_le_load failed");

    // 2. When timer is disabled, counter must be cleared to 0 on the next clock
    a_tmr_disabled_cnt_zero: assert property (
        disable iff (!rst_n)
        (!tmr_en) |=> (tmr_cnt == 8'h00)
    ) else $error("[SVA] a_tmr_disabled_cnt_zero failed");

    // 3. When timer is disabled, PWM output must be low
    a_tmr_disabled_pwm_low: assert property (
        disable iff (!rst_n)
        (!tmr_en) |-> (pwm_out == 1'b0)
    ) else $error("[SVA] a_tmr_disabled_pwm_low failed");

    // 4. PWM output matches (tmr_cnt < tmr_cmp) when running normally
    a_pwm_duty_logic: assert property (
        disable iff (!rst_n)
        (tmr_en && !(tmr_oneshot && tmr_ovf_pulse)) |-> (pwm_out == (tmr_cnt < tmr_cmp))
    ) else $error("[SVA] a_pwm_duty_logic failed");

    // 5. Overflow pulse is a single-cycle pulse when PRESC > 0 or LOAD > 0
    a_ovf_single_cycle: assert property (
        disable iff (!rst_n)
        (tmr_ovf_pulse && ((tmr_presc > 8'd0) || (tmr_load > 8'd0))) |=> !tmr_ovf_pulse
    ) else $error("[SVA] a_ovf_single_cycle failed");

    // 6. Compare pulse is a single-cycle pulse when PRESC > 0 or LOAD > 0
    a_cmp_single_cycle: assert property (
        disable iff (!rst_n)
        (tmr_cmp_pulse && ((tmr_presc > 8'd0) || (tmr_load > 8'd0))) |=> !tmr_cmp_pulse
    ) else $error("[SVA] a_cmp_single_cycle failed");

    // 7. Compare pulse only fires when counter equals CMP on the previous cycle
    a_cmp_match: assert property (
        disable iff (!rst_n)
        tmr_cmp_pulse |-> ($past(tmr_en) && ($past(tmr_cnt) == $past(tmr_cmp)))
    ) else $error("[SVA] a_cmp_match failed");

    // 8. One-shot mode stops the timer by clearing tmr_en on overflow
    a_oneshot_stop: assert property (
        disable iff (!rst_n)
        (tmr_en && tmr_oneshot && tmr_ovf_pulse && !apb_wr_tmr_ctrl) |=> !tmr_en
    ) else $error("[SVA] a_oneshot_stop failed");

    // =========================================================================
    // Group 2: SAR ADC Controller Assertions (8 rules)
    // =========================================================================

    // 9. Disabling ADC immediately clears busy and sample on the next cycle
    a_adc_abort_on_disable: assert property (
        disable iff (!rst_n)
        (!adc_en) |=> (!adc_busy && !adc_sample && !adc_eoc)
    ) else $error("[SVA] a_adc_abort_on_disable failed");

    // 10. adc_sample can only be high when adc_busy is high
    a_sample_implies_busy: assert property (
        disable iff (!rst_n)
        adc_sample |-> adc_busy
    ) else $error("[SVA] a_sample_implies_busy failed");

    // 11. During sampling phase, DAC trial value must be 0x00
    a_sample_dac_zero: assert property (
        disable iff (!rst_n)
        adc_sample |-> (adc_dac == 8'h00)
    ) else $error("[SVA] a_sample_dac_zero failed");

    // 12. First cycle of conversion phase sets DAC MSB (0x80)
    a_sample_width: assert property (
        disable iff (!rst_n || !adc_en)
        ($fell(adc_sample) && adc_busy) |-> (adc_dac == 8'h80)
    ) else $error("[SVA] a_sample_width failed");

    // 13. End-Of-Conversion (EOC) is strictly a 1-clock pulse
    a_eoc_single_cycle: assert property (
        disable iff (!rst_n)
        adc_eoc |=> !adc_eoc
    ) else $error("[SVA] a_eoc_single_cycle failed");

    // 14. EOC coincides with the falling edge of adc_busy
    a_conv_time: assert property (
        disable iff (!rst_n || !adc_en)
        adc_eoc |-> ($past(adc_busy) && !adc_busy)
    ) else $error("[SVA] a_conv_time failed");

    // 15. Selected analog channel remains stable throughout the conversion
    a_adc_ch_stable: assert property (
        disable iff (!rst_n || !adc_en)
        (adc_busy && $past(adc_busy)) |-> $stable(adc_ch)
    ) else $error("[SVA] a_adc_ch_stable failed");

    // 16. When EOC pulses, DAC returns to 0x00
    a_eoc_dac_zero: assert property (
        disable iff (!rst_n)
        adc_eoc |-> (adc_dac == 8'h00)
    ) else $error("[SVA] a_eoc_dac_zero failed");

    // =========================================================================
    // Group 3: Synchronous FIFO Assertions (7 rules)
    // =========================================================================

    // 17. FIFO level never exceeds depth 8
    a_fifo_level_bound: assert property (
        disable iff (!rst_n)
        fifo_level <= 4'd8
    ) else $error("[SVA] a_fifo_level_bound failed");

    // 18. FIFO empty flag matches (level == 0)
    a_fifo_empty_flag: assert property (
        disable iff (!rst_n)
        fifo_empty == (fifo_level == 4'd0)
    ) else $error("[SVA] a_fifo_empty_flag failed");

    // 19. FIFO full flag matches (level == 8)
    a_fifo_full_flag: assert property (
        disable iff (!rst_n)
        fifo_full == (fifo_level == 4'd8)
    ) else $error("[SVA] a_fifo_full_flag failed");

    // 20. Writing to a full FIFO triggers overflow and drops the sample
    a_overflow_drop: assert property (
        disable iff (!rst_n)
        (adc_eoc && fifo_full && !fifo_pop) |=> (fifo_level == 4'd8)
    ) else $error("[SVA] a_overflow_drop failed");

    // 21. Push without pop when not full increments FIFO level by 1
    a_fifo_push_inc: assert property (
        disable iff (!rst_n)
        (adc_eoc && !fifo_full && !(fifo_pop && !fifo_empty)) |=> (fifo_level == ($past(fifo_level) + 4'd1))
    ) else $error("[SVA] a_fifo_push_inc failed");

    // 22. Pop without push when not empty decrements FIFO level by 1
    a_fifo_pop_dec: assert property (
        disable iff (!rst_n)
        (fifo_pop && !fifo_empty && !adc_eoc) |=> (fifo_level == ($past(fifo_level) - 4'd1))
    ) else $error("[SVA] a_fifo_pop_dec failed");

    // 23. Simultaneous push and pop on non-empty, non-full FIFO keeps level constant
    a_fifo_push_pop_same: assert property (
        disable iff (!rst_n)
        (adc_eoc && !fifo_full && fifo_pop && !fifo_empty) |=> (fifo_level == $past(fifo_level))
    ) else $error("[SVA] a_fifo_push_pop_same failed");

    // =========================================================================
    // Group 4: APB Registers & Interrupt Assertions (7 rules)
    // =========================================================================

    // 24. Peripheral is zero-wait-state and error-free on APB
    a_apb_ready_no_err: assert property (
        disable iff (!rst_n)
        (pready == 1'b1) && (pslverr == 1'b0)
    ) else $error("[SVA] a_apb_ready_no_err failed");

    // 25. Reading ID register (0xF) always returns 0xA8
    a_id_reg_value: assert property (
        disable iff (!rst_n)
        (psel && !pwrite && (paddr == 4'hF)) |-> (prdata == 8'hA8)
    ) else $error("[SVA] a_id_reg_value failed");

    // 26. Reading ADC_CTRL (0x5) always returns 0 on the self-clearing START bit [1]
    a_start_bit_reads_zero: assert property (
        disable iff (!rst_n)
        (psel && !pwrite && (paddr == 4'h5)) |-> (prdata[1] == 1'b0)
    ) else $error("[SVA] a_start_bit_reads_zero failed");

    // 27. IRQ output line equals the reduction OR of enabled status flags
    a_irq_line_combinational: assert property (
        disable iff (!rst_n)
        irq == |(irq_stat & irq_en)
    ) else $error("[SVA] a_irq_line_combinational failed");

    // 28. Timer overflow event sets IRQ_STAT[0] on the next clock (even if W1C occurs)
    a_irq_set_tmr_ovf: assert property (
        disable iff (!rst_n)
        tmr_ovf_pulse |=> irq_stat[0]
    ) else $error("[SVA] a_irq_set_tmr_ovf failed");

    // 29. ADC EOC event sets IRQ_STAT[2] on the next clock (even if W1C occurs)
    a_irq_set_adc_eoc: assert property (
        disable iff (!rst_n)
        adc_eoc |=> irq_stat[2]
    ) else $error("[SVA] a_irq_set_adc_eoc failed");

    // 30. Window violation at EOC sets IRQ_STAT[3] on the next clock
    a_irq_set_adc_wd: assert property (
        disable iff (!rst_n)
        (adc_eoc && ((adc_result < adc_thr_lo) || (adc_result > adc_thr_hi))) |=> irq_stat[3]
    ) else $error("[SVA] a_irq_set_adc_wd failed");

endmodule

// Wrapper module that binds timer_adc_sva into every instance of timer_adc8_top
module bind_timer_adc_sva;
    bind timer_adc8_top timer_adc_sva u_sva (
        .clk           (clk),
        .rst_n         (rst_n),
        .psel          (psel),
        .penable       (penable),
        .pwrite        (pwrite),
        .paddr         (paddr),
        .pwdata        (pwdata),
        .prdata        (prdata),
        .pready        (pready),
        .pslverr       (pslverr),
        .irq           (irq),
        .pwm_out       (pwm_out),
        .adc_sample    (adc_sample),
        .adc_ch        (adc_ch),
        .adc_dac       (adc_dac),
        .adc_cmp       (adc_cmp),
        .tmr_en        (tmr_en),
        .tmr_oneshot   (tmr_oneshot),
        .tmr_presc     (tmr_presc),
        .tmr_load      (tmr_load),
        .tmr_cmp       (tmr_cmp),
        .tmr_cnt       (tmr_cnt),
        .tmr_ovf_pulse (tmr_ovf_pulse),
        .tmr_cmp_pulse (tmr_cmp_pulse),
        .adc_en        (adc_en),
        .adc_start     (adc_start),
        .adc_cont_mode (adc_cont_mode),
        .adc_ch_sel    (adc_ch_sel),
        .adc_smp       (adc_smp),
        .adc_div       (adc_div),
        .adc_busy      (adc_busy),
        .adc_eoc       (adc_eoc),
        .adc_result    (adc_result),
        .fifo_rd_data  (fifo_rd_data),
        .fifo_rd_ch    (fifo_rd_ch),
        .fifo_full     (fifo_full),
        .fifo_empty    (fifo_empty),
        .fifo_level    (fifo_level),
        .fifo_overflow (fifo_overflow),
        .fifo_pop      (fifo_pop),
        .irq_en        (u_regs.irq_en),
        .irq_stat      (u_regs.irq_stat),
        .adc_thr_lo    (u_regs.adc_thr_lo),
        .adc_thr_hi    (u_regs.adc_thr_hi)
    );
endmodule