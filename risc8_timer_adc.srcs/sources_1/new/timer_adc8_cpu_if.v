`timescale 1ns / 1ps

module timer_adc8_cpu_if (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cs,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata,
    output wire       irq,
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp,
    output wire       pwm_out
);

    wire [7:0] prdata_int;
    wire       pready_unused;
    wire       pslverr_unused;

    assign rdata = (cs && !we) ? prdata_int : 8'h00;

    timer_adc8_top u_periph (
        .clk        (clk),
        .rst_n      (rst_n),
        .psel       (cs),
        .penable    (cs),
        .pwrite     (we),
        .paddr      (addr),
        .pwdata     (wdata),
        .prdata     (prdata_int),
        .pready     (pready_unused),
        .pslverr    (pslverr_unused),
        .irq        (irq),
        .pwm_out    (pwm_out),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

endmodule