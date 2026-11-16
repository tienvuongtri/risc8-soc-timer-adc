`timescale 1ns / 1ps

module timer8 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire       oneshot,
    input  wire [7:0] presc,
    input  wire [7:0] load,
    input  wire [7:0] cmp,
    output reg  [7:0] cnt,
    output reg        ovf_pulse,
    output reg        cmp_pulse,
    output wire       pwm_out
);

    reg [7:0] presc_cnt;
    wire      tick;

    // Tin hieu tickkich hoat moi (presc + 1) chu ky xung nhip
    // Khi o che do oneshot va vua phat xung ovf_pulse, tam ngung tick trong chu ky do
    // de apb_regs8 kip xoa bit EN ma khong bi dem them nhip nao.
    assign tick = en && !(oneshot && ovf_pulse) && (presc_cnt >= presc);

    // Ngo ra PWM o muc cao khi Timer dang bat va gia tri dem nho hon CMP
    assign pwm_out = en && !(oneshot && ovf_pulse) && (cnt < cmp);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            presc_cnt <= 8'd0;
            cnt       <= 8'd0;
            ovf_pulse <= 1'b0;
            cmp_pulse <= 1'b0;
        end else begin
            ovf_pulse <= 1'b0;
            cmp_pulse <= 1'b0;

            if (!en || (oneshot && ovf_pulse)) begin
                presc_cnt <= 8'd0;
                cnt       <= 8'd0;
            end else begin
                if (tick) begin
                    presc_cnt <= 8'd0;

                    // Kiem tra su kien Compare
                    if (cnt == cmp) begin
                        cmp_pulse <= 1'b1;
                    end

                    // Kiem tra su kien Overflow / Wrap-around
                    if (cnt >= load) begin
                        cnt       <= 8'd0;
                        ovf_pulse <= 1'b1;
                    end else begin
                        cnt       <= cnt + 8'd1;
                    end
                end else begin
                    presc_cnt <= presc_cnt + 8'd1;
                end
            end
        end
    end

endmodule