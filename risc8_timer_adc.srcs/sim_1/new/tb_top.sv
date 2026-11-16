`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import timer_adc_pkg::*;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    always #5 clk = ~clk; // 100 MHz system clock

    apb_if u_apb_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    adc_if u_adc_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    timer_adc8_top dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .psel       (u_apb_if.psel),
        .penable    (u_apb_if.penable),
        .pwrite     (u_apb_if.pwrite),
        .paddr      (u_apb_if.paddr),
        .pwdata     (u_apb_if.pwdata),
        .prdata     (u_apb_if.prdata),
        .pready     (u_apb_if.pready),
        .pslverr    (u_apb_if.pslverr),
        .irq        (u_apb_if.irq),
        .pwm_out    (u_apb_if.pwm_out),
        .adc_sample (u_adc_if.adc_sample),
        .adc_ch     (u_adc_if.adc_ch),
        .adc_dac    (u_adc_if.adc_dac),
        .adc_cmp    (u_adc_if.adc_cmp)
    );

    sar_afe_model u_afe (
        .aif (u_adc_if)
    );

    // Attach all 30 SVA rules to timer_adc8_top
    bind_timer_adc_sva u_bind_sva ();

    // Connect internal event probes for UVM monitor and scoreboard
    assign u_adc_if.eoc         = dut.adc_eoc;
    assign u_adc_if.conv_result = dut.adc_result;
    assign u_adc_if.conv_ch     = dut.adc_result_ch;
    assign u_adc_if.tmr_ovf     = dut.tmr_ovf_pulse;
    assign u_adc_if.tmr_cmp     = dut.tmr_cmp_pulse;
    assign u_adc_if.pwm_out     = dut.pwm_out;
    assign u_adc_if.irq         = dut.irq;

    initial begin
        u_apb_if.bus_reset();
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", u_apb_if);
        uvm_config_db#(virtual adc_if)::set(null, "*", "vif", u_adc_if);
        // Default to tadc_all_test if +UVM_TESTNAME is not specified
        run_test("tadc_all_test");
    end

endmodule