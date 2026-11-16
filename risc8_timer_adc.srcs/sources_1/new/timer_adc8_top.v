`timescale 1ns / 1ps

module timer_adc8_top (
    input  wire       clk,
    input  wire       rst_n,
    // Giao tiep APB
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [3:0] paddr,
    input  wire [7:0] pwdata,
    output wire [7:0] prdata,
    output wire       pready,
    output wire       pslverr,
    // Ngo ra he thong
    output wire       irq,
    output wire       pwm_out,
    // Giao tiep Analog Front-End (AFE)
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp
);

    // Day ket noi Timer
    wire       tmr_en;
    wire       tmr_oneshot;
    wire [7:0] tmr_presc;
    wire [7:0] tmr_load;
    wire [7:0] tmr_cmp;
    wire [7:0] tmr_cnt;
    wire       tmr_ovf_pulse;
    wire       tmr_cmp_pulse;

    // Day ket noi SAR ADC
    wire       adc_en;
    wire       adc_start;
    wire       adc_cont_mode;
    wire [1:0] adc_ch_sel;
    wire [7:0] adc_smp;
    wire [7:0] adc_div;
    wire       adc_busy;
    wire       adc_eoc;
    wire [7:0] adc_result;
    wire [1:0] adc_result_ch;

    // Day ket noi FIFO
    wire [7:0] fifo_rd_data;
    wire [1:0] fifo_rd_ch;
    wire       fifo_full;
    wire       fifo_empty;
    wire [3:0] fifo_level;
    wire       fifo_overflow;
    wire       fifo_pop;

    apb_regs8 u_regs (
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
        .irq           (irq)
    );

    timer8 u_timer (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (tmr_en),
        .oneshot   (tmr_oneshot),
        .presc     (tmr_presc),
        .load      (tmr_load),
        .cmp       (tmr_cmp),
        .cnt       (tmr_cnt),
        .ovf_pulse (tmr_ovf_pulse),
        .cmp_pulse (tmr_cmp_pulse),
        .pwm_out   (pwm_out)
    );

    sar_adc_ctrl #(
        .N (8)
    ) u_adc (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (adc_en),
        .start      (adc_start),
        .cont_mode  (adc_cont_mode),
        .ch_in      (adc_ch_sel),
        .smp_cycles (adc_smp),
        .clk_div    (adc_div),
        .adc_cmp    (adc_cmp),
        .busy       (adc_busy),
        .eoc        (adc_eoc),
        .result     (adc_result),
        .result_ch  (adc_result_ch),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac)
    );

    sync_fifo #(
        .DEPTH (8)
    ) u_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (adc_eoc),
        .wr_data  (adc_result),
        .wr_ch    (adc_result_ch),
        .rd_en    (fifo_pop),
        .rd_data  (fifo_rd_data),
        .rd_ch    (fifo_rd_ch),
        .full     (fifo_full),
        .empty    (fifo_empty),
        .level    (fifo_level),
        .overflow (fifo_overflow)
    );

endmodule