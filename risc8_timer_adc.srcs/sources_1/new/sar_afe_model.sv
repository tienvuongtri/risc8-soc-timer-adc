`timescale 1ns / 1ps

module sar_afe_model (
    adc_if aif
);
    real v_mux;
    real v_dac;
    real lsb_v;
    real rand_norm;
    real noise_v;
    int  seed = 32'h1357_2468;

    // Analog input multiplexer
    always_comb begin
        v_mux = aif.vin[aif.adc_ch];
    end

    // Sample-and-hold tracking and holding behavior
    always @(posedge aif.clk or negedge aif.rst_n) begin
        if (!aif.rst_n) begin
            aif.vhold <= 0.0;
        end else if (aif.adc_sample) begin
            lsb_v = (aif.vref > 0.0) ? (aif.vref / 256.0) : (3.3 / 256.0);
            if (aif.noise_lsb > 0.0) begin
                // Uniform random noise in [-noise_lsb, +noise_lsb] LSBs
                rand_norm = (real'($urandom(seed) % 2001) - 1000.0) / 1000.0;
                noise_v   = rand_norm * aif.noise_lsb * lsb_v;
            end else begin
                noise_v   = 0.0;
            end

            aif.vhold <= v_mux + aif.offset_v + noise_v;
            if (aif.vhold < 0.0)      aif.vhold <= 0.0;
            if (aif.vhold > aif.vref) aif.vhold <= aif.vref;
        end
    end

    // 8-bit binary-weighted DAC and comparator
    always_comb begin
        v_dac = (real'(aif.adc_dac) / 256.0) * aif.vref;
        if (!aif.rst_n) begin
            aif.adc_cmp = 1'b0;
        end else begin
            aif.adc_cmp = (aif.vhold >= v_dac) ? 1'b1 : 1'b0;
        end
    end

endmodule