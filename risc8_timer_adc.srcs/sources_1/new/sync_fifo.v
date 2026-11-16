`timescale 1ns / 1ps

module sync_fifo #(
    parameter DEPTH = 8
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_en,
    input  wire [7:0] wr_data,
    input  wire [1:0] wr_ch,
    input  wire       rd_en,
    output wire [7:0] rd_data,
    output wire [1:0] rd_ch,
    output wire       full,
    output wire       empty,
    output reg  [3:0] level,
    output wire       overflow
);

    reg [7:0] data_mem [0:DEPTH-1];
    reg [1:0] ch_mem   [0:DEPTH-1];
    reg [2:0] wr_ptr;
    reg [2:0] rd_ptr;

    integer i;

    assign full     = (level == 4'd8);
    assign empty    = (level == 4'd0);
    assign overflow = wr_en && full;

    // Ngo ra doc to hop tu phan tu cu nhat, bang 0 khi FIFO rong
    assign rd_data  = empty ? 8'h00 : data_mem[rd_ptr];
    assign rd_ch    = empty ? 2'b00 : ch_mem[rd_ptr];

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 3'd0;
            rd_ptr <= 3'd0;
            level  <= 4'd0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                data_mem[i] <= 8'h00;
                ch_mem[i]   <= 2'b00;
            end
        end else begin
            if (do_write) begin
                data_mem[wr_ptr] <= wr_data;
                ch_mem[wr_ptr]   <= wr_ch;
                wr_ptr           <= wr_ptr + 3'd1;
            end

            if (do_read) begin
                rd_ptr <= rd_ptr + 3'd1;
            end

            case ({do_write, do_read})
                2'b10:   level <= level + 4'd1;
                2'b01:   level <= level - 4'd1;
                default: level <= level;
            endcase
        end
    end

endmodule