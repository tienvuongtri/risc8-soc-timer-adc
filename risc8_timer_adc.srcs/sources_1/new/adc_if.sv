`timescale 1ns / 1ps

interface adc_if (
    input logic clk,
    input logic rst_n
);
    // Digital control/status signals between DUT and AFE
    logic       adc_sample;
    logic [1:0] adc_ch;
    logic [7:0] adc_dac;
    logic       adc_cmp;

    // Analog channel voltages and reference (Volts)
    real        vin [0:3];
    real        vref;
    real        vhold;

    // Non-ideality injection parameters for analog noise testing
    real        offset_v;
    real        noise_lsb;

    // Observation signals for UVM monitor and coverage
    logic       eoc;
    logic [7:0] conv_result;
    logic [1:0] conv_ch;
    logic       tmr_ovf;
    logic       tmr_cmp;
    logic       pwm_out;
    logic       irq;

    initial begin
        vref      = 3.3;
        vin[0]    = 0.400;
        vin[1]    = 1.111;
        vin[2]    = 2.000;
        vin[3]    = 3.000;
        vhold     = 0.0;
        offset_v  = 0.0;
        noise_lsb = 0.0;
    end

    // Set voltage on a single analog channel
    function automatic void set_ch_voltage(input int ch, input real v);
        if (ch >= 0 && ch < 4) begin
            vin[ch] = v;
        end
    endfunction

    // Set all four analog channel voltages at once
    function automatic void set_all_voltages(
        input real v0,
        input real v1,
        input real v2,
        input real v3
    );
        vin[0] = v0;
        vin[1] = v1;
        vin[2] = v2;
        vin[3] = v3;
    endfunction

    // Configure analog offset and noise in LSBs
    function automatic void set_analog_impairments(input real off_v, input real n_lsb);
        offset_v  = off_v;
        noise_lsb = n_lsb;
    endfunction

endinterface