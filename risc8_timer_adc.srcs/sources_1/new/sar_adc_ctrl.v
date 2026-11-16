`timescale 1ns / 1ps

module sar_adc_ctrl #(
    parameter N = 8
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         en,
    input  wire         start,
    input  wire         cont_mode,
    input  wire [1:0]   ch_in,
    input  wire [7:0]   smp_cycles,
    input  wire [7:0]   clk_div,
    input  wire         adc_cmp,
    output wire         busy,
    output reg          eoc,
    output reg  [N-1:0] result,
    output reg  [1:0]   result_ch,
    output wire         adc_sample,
    output reg  [1:0]   adc_ch,
    output reg  [N-1:0] adc_dac
);

    localparam [1:0] ST_IDLE    = 2'd0,
                     ST_SAMPLE  = 2'd1,
                     ST_CONVERT = 2'd2,
                     ST_DONE    = 2'd3;

    reg [1:0] state;
    reg [7:0] div_cnt;
    reg [7:0] smp_cnt;
    reg [2:0] bit_idx;

    wire adc_tick = (div_cnt >= clk_div);

    assign busy       = en && ((state == ST_SAMPLE) || (state == ST_CONVERT));
    assign adc_sample = en && (state == ST_SAMPLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            div_cnt   <= 8'd0;
            smp_cnt   <= 8'd0;
            bit_idx   <= 3'd7;
            eoc       <= 1'b0;
            result    <= {N{1'b0}};
            result_ch <= 2'd0;
            adc_ch    <= 2'd0;
            adc_dac   <= {N{1'b0}};
        end else begin
            eoc <= 1'b0;

            if (!en) begin
                // Huy chuyen doi ngay lap tuc khi tat EN
                state   <= ST_IDLE;
                div_cnt <= 8'd0;
                smp_cnt <= 8'd0;
                bit_idx <= 3'd7;
                adc_dac <= {N{1'b0}};
            end else begin
                case (state)
                    ST_IDLE: begin
                        div_cnt <= 8'd0;
                        smp_cnt <= 8'd0;
                        bit_idx <= 3'd7;
                        adc_dac <= {N{1'b0}};
                        if (start || cont_mode) begin
                            state  <= ST_SAMPLE;
                            adc_ch <= ch_in;
                        end
                    end

                    ST_SAMPLE: begin
                        if (adc_tick) begin
                            div_cnt <= 8'd0;
                            if (smp_cnt >= smp_cycles) begin
                                smp_cnt <= 8'd0;
                                state   <= ST_CONVERT;
                                bit_idx <= 3'd7;
                                adc_dac <= 8'h80; // Thu bit MSB (bit 7) dau tien
                            end else begin
                                smp_cnt <= smp_cnt + 8'd1;
                            end
                        end else begin
                            div_cnt <= div_cnt + 8'd1;
                        end
                    end

                    ST_CONVERT: begin
                        if (adc_tick) begin
                            div_cnt <= 8'd0;
                            if (bit_idx == 3'd0) begin
                                // Hoan tat bit LSB (bit 0)
                                result    <= {adc_dac[N-1:1], adc_cmp};
                                result_ch <= adc_ch;
                                eoc       <= 1'b1;
                                adc_dac   <= {N{1'b0}};
                                state     <= ST_DONE;
                            end else begin
                                // Quyet dinh bit hien tai theo adc_cmp va dat bit thu ke tiep len 1
                                case (bit_idx)
                                    3'd7: adc_dac <= {adc_cmp, 1'b1, 6'b000000};
                                    3'd6: adc_dac <= {adc_dac[7], adc_cmp, 1'b1, 5'b00000};
                                    3'd5: adc_dac <= {adc_dac[7:6], adc_cmp, 1'b1, 4'b0000};
                                    3'd4: adc_dac <= {adc_dac[7:5], adc_cmp, 1'b1, 3'b000};
                                    3'd3: adc_dac <= {adc_dac[7:4], adc_cmp, 1'b1, 2'b00};
                                    3'd2: adc_dac <= {adc_dac[7:3], adc_cmp, 1'b1, 1'b0};
                                    3'd1: adc_dac <= {adc_dac[7:2], adc_cmp, 1'b1};
                                    default: adc_dac <= {N{1'b0}};
                                endcase
                                bit_idx <= bit_idx - 3'd1;
                            end
                        end else begin
                            div_cnt <= div_cnt + 8'd1;
                        end
                    end

                    ST_DONE: begin
                        div_cnt <= 8'd0;
                        smp_cnt <= 8'd0;
                        bit_idx <= 3'd7;
                        if (cont_mode || start) begin
                            state  <= ST_SAMPLE;
                            adc_ch <= ch_in;
                        end else begin
                            state  <= ST_IDLE;
                        end
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end

endmodule