`timescale 1ns / 1ps

module apb_regs8 (
    input  wire       clk,
    input  wire       rst_n,
    // Giao tiep APB 8-bit
    input  wire       psel,
    input  wire       penable,
    input  wire       pwrite,
    input  wire [3:0] paddr,
    input  wire [7:0] pwdata,
    output reg  [7:0] prdata,
    output wire       pready,
    output wire       pslverr,
    // Giao tiep voi timer8
    output reg        tmr_en,
    output reg        tmr_oneshot,
    output reg  [7:0] tmr_presc,
    output reg  [7:0] tmr_load,
    output reg  [7:0] tmr_cmp,
    input  wire [7:0] tmr_cnt,
    input  wire       tmr_ovf_pulse,
    input  wire       tmr_cmp_pulse,
    // Giao tiep voi sar_adc_ctrl
    output reg        adc_en,
    output wire       adc_start,
    output wire       adc_cont_mode,
    output reg  [1:0] adc_ch_sel,
    output reg  [7:0] adc_smp,
    output reg  [7:0] adc_div,
    input  wire       adc_busy,
    input  wire       adc_eoc,
    input  wire [7:0] adc_result,
    // Giao tiep voi sync_fifo
    input  wire [7:0] fifo_rd_data,
    input  wire [1:0] fifo_rd_ch,
    input  wire       fifo_full,
    input  wire       fifo_empty,
    input  wire [3:0] fifo_level,
    input  wire       fifo_overflow,
    output wire       fifo_pop,
    // Ngo ra ngat
    output wire       irq
);

    // Dia chi 16 thanh ghi
    localparam [3:0] ADDR_TMR_CTRL   = 4'h0,
                     ADDR_TMR_PRESC  = 4'h1,
                     ADDR_TMR_LOAD   = 4'h2,
                     ADDR_TMR_CMP    = 4'h3,
                     ADDR_TMR_CNT    = 4'h4,
                     ADDR_ADC_CTRL   = 4'h5,
                     ADDR_ADC_SMP    = 4'h6,
                     ADDR_ADC_DIV    = 4'h7,
                     ADDR_ADC_THR_LO = 4'h8,
                     ADDR_ADC_THR_HI = 4'h9,
                     ADDR_ADC_DATA   = 4'hA,
                     ADDR_ADC_RCH    = 4'hB,
                     ADDR_ADC_STAT   = 4'hC,
                     ADDR_IRQ_EN     = 4'hD,
                     ADDR_IRQ_STAT   = 4'hE,
                     ADDR_ID         = 4'hF;

    localparam [7:0] PERIPH_ID = 8'hA8;

    reg [1:0] adc_trig_sel;
    reg       sw_start_pulse;
    reg [7:0] adc_thr_lo;
    reg [7:0] adc_thr_hi;
    reg [5:0] irq_en;
    reg [5:0] irq_stat;

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    wire apb_wr = psel && penable && pwrite;
    wire apb_rd = psel && penable && !pwrite;

    // Doc thanh ghi ADC_DATA (0xA) se pop 1 phan tu khoi FIFO
    assign fifo_pop = apb_rd && (paddr == ADDR_ADC_DATA);

    // Chon nguon kich hoat ADC
    assign adc_cont_mode = (adc_trig_sel == 2'd3);

    wire sel_trig_pulse = (adc_trig_sel == 2'd0) ? sw_start_pulse :
                          (adc_trig_sel == 2'd1) ? tmr_ovf_pulse  :
                          (adc_trig_sel == 2'd2) ? tmr_cmp_pulse  : 1'b0;

    assign adc_start = adc_en && !adc_busy && (sel_trig_pulse || adc_cont_mode);

    // Kiem tra cac su kien ngat phan cung
    wire trig_miss_ev = adc_en && adc_busy && sel_trig_pulse;
    wire adc_wd_ev    = adc_eoc && ((adc_result < adc_thr_lo) || (adc_result > adc_thr_hi));

    wire [5:0] hw_irq_set = {
        trig_miss_ev,   // [5] TRIG_MISS
        fifo_overflow,  // [4] FIFO_OVR
        adc_wd_ev,      // [3] ADC_WD
        adc_eoc,        // [2] ADC_EOC
        tmr_cmp_pulse,  // [1] TMR_CMP
        tmr_ovf_pulse   // [0] TMR_OVF
    };

    wire [5:0] sw_irq_clr = (apb_wr && (paddr == ADDR_IRQ_STAT)) ? pwdata[5:0] : 6'b000000;

    // Ngo ra irq tich cuc muc cao khi co bat ky co ngat nao duoc bat
    assign irq = |(irq_stat & irq_en);

    // Cap nhat cac thanh ghi
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmr_en         <= 1'b0;
            tmr_oneshot    <= 1'b0;
            tmr_presc      <= 8'h00;
            tmr_load       <= 8'hFF;
            tmr_cmp        <= 8'h80;
            adc_en         <= 1'b0;
            sw_start_pulse <= 1'b0;
            adc_trig_sel   <= 2'd0;
            adc_ch_sel     <= 2'd0;
            adc_smp        <= 8'h04;
            adc_div        <= 8'h00;
            adc_thr_lo     <= 8'h00;
            adc_thr_hi     <= 8'hFF;
            irq_en         <= 6'b000000;
            irq_stat       <= 6'b000000;
        end else begin
            // Xung START tu xoa sau 1 chu ky
            sw_start_pulse <= 1'b0;

            // Tu dong xoa TMR_CTRL.EN khi tran o che do ONESHOT
            if (tmr_en && tmr_oneshot && tmr_ovf_pulse) begin
                tmr_en <= 1'b0;
            end

            // Ghi thanh ghi tu APB
            if (apb_wr) begin
                case (paddr)
                    ADDR_TMR_CTRL: begin
                        tmr_en      <= pwdata[0];
                        tmr_oneshot <= pwdata[1];
                    end
                    ADDR_TMR_PRESC:  tmr_presc  <= pwdata;
                    ADDR_TMR_LOAD:   tmr_load   <= pwdata;
                    ADDR_TMR_CMP:    tmr_cmp    <= pwdata;
                    ADDR_ADC_CTRL: begin
                        adc_en         <= pwdata[0];
                        sw_start_pulse <= pwdata[1] && pwdata[0];
                        adc_trig_sel   <= pwdata[3:2];
                        adc_ch_sel     <= pwdata[5:4];
                    end
                    ADDR_ADC_SMP:    adc_smp    <= pwdata;
                    ADDR_ADC_DIV:    adc_div    <= pwdata;
                    ADDR_ADC_THR_LO: adc_thr_lo <= pwdata;
                    ADDR_ADC_THR_HI: adc_thr_hi <= pwdata;
                    ADDR_IRQ_EN:     irq_en     <= pwdata[5:0];
                    default: begin end
                endcase
            end

            // Thanh ghi IRQ_STAT: W1C, phan cung (hw_irq_set) co uu tien cao hon xoa mem (sw_irq_clr)
            irq_stat <= (irq_stat & ~sw_irq_clr) | hw_irq_set;
        end
    end

    // Bo doc MUX to hop (tra ve 0 khi khong duoc chon doc)
    always @* begin
        prdata = 8'h00;
        if (psel && !pwrite) begin
            case (paddr)
                ADDR_TMR_CTRL:   prdata = {6'b000000, tmr_oneshot, tmr_en};
                ADDR_TMR_PRESC:  prdata = tmr_presc;
                ADDR_TMR_LOAD:   prdata = tmr_load;
                ADDR_TMR_CMP:    prdata = tmr_cmp;
                ADDR_TMR_CNT:    prdata = tmr_cnt;
                // Bit START [1] luon doc ve 0
                ADDR_ADC_CTRL:   prdata = {2'b00, adc_ch_sel, adc_trig_sel, 1'b0, adc_en};
                ADDR_ADC_SMP:    prdata = adc_smp;
                ADDR_ADC_DIV:    prdata = adc_div;
                ADDR_ADC_THR_LO: prdata = adc_thr_lo;
                ADDR_ADC_THR_HI: prdata = adc_thr_hi;
                ADDR_ADC_DATA:   prdata = fifo_rd_data;
                ADDR_ADC_RCH:    prdata = {!fifo_empty, 5'b00000, fifo_rd_ch};
                ADDR_ADC_STAT:   prdata = {1'b0, adc_busy, fifo_full, fifo_empty, fifo_level};
                ADDR_IRQ_EN:     prdata = {2'b00, irq_en};
                ADDR_IRQ_STAT:   prdata = {2'b00, irq_stat};
                ADDR_ID:         prdata = PERIPH_ID;
                default:         prdata = 8'h00;
            endcase
        end
    end

endmodule