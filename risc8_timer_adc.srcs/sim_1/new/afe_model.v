`timescale 1ns / 1ps

// Verilog-2001 Analog Front-End model for SoC simulation
module afe_model (
    input  wire       clk,
    input  wire       adc_sample,
    input  wire [1:0] adc_ch,
    input  wire [7:0] adc_dac,
    output wire       adc_cmp
);
    real vref;
    real vin_0, vin_1, vin_2, vin_3;
    real v_mux;
    real v_hold;
    real v_dac;

    initial begin
        vref   = 3.300;
        vin_0  = 0.400; // Expected code: floor(0.400 / 3.3 * 256) = 31  (0x1F)
        vin_1  = 1.111; // Expected code: floor(1.111 / 3.3 * 256) = 86  (0x56)
        vin_2  = 2.000; // Expected code: floor(2.000 / 3.3 * 256) = 155 (0x9B)
        vin_3  = 3.000; // Expected code: floor(3.000 / 3.3 * 256) = 232 (0xE8)
        v_hold = 0.000;
    end

    always @* begin
        case (adc_ch)
            2'd0:    v_mux = vin_0;
            2'd1:    v_mux = vin_1;
            2'd2:    v_mux = vin_2;
            default: v_mux = vin_3;
        endcase
        v_dac = ($itor(adc_dac) / 256.0) * vref;
    end

    always @(posedge clk) begin
        if (adc_sample) begin
            v_hold <= v_mux;
        end
    end

    assign adc_cmp = (v_hold >= v_dac) ? 1'b1 : 1'b0;

endmodule