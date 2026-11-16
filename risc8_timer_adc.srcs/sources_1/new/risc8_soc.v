`timescale 1ns / 1ps

module risc8_soc #(
    parameter IMEM_FILE = "soc_demo.mem"
) (
    input  wire       clk,
    input  wire       rst,
    output wire       halted,
    output wire [7:0] pc_out,
    output wire       irq,
    output wire       pwm_out,
    output wire       adc_sample,
    output wire [1:0] adc_ch,
    output wire [7:0] adc_dac,
    input  wire       adc_cmp
);

    wire       io_cs;
    wire       io_we;
    wire [3:0] io_addr;
    wire [7:0] io_wdata;
    wire [7:0] io_rdata;
    wire [1:0] flags_unused;
    wire       instr_done_unused;

    risc8_5stage_core #(
        .IMEM_FILE (IMEM_FILE),
        .IO_ENABLE (1),
        .IO_PAGE   (4'hF)
    ) u_cpu (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc_out),
        .flags_out  (flags_unused),
        .instr_done (instr_done_unused),
        .io_cs      (io_cs),
        .io_we      (io_we),
        .io_addr    (io_addr),
        .io_wdata   (io_wdata),
        .io_rdata   (io_rdata)
    );

    timer_adc8_cpu_if u_tadc (
        .clk        (clk),
        .rst_n      (~rst),
        .cs         (io_cs),
        .we         (io_we),
        .addr       (io_addr),
        .wdata      (io_wdata),
        .rdata      (io_rdata),
        .irq        (irq),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp),
        .pwm_out    (pwm_out)
    );

endmodule