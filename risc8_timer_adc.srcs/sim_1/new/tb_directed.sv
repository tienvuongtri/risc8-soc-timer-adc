`timescale 1ns / 1ps

module tb_directed;

    logic clk   = 1'b0;
    logic rst_n = 1'b0;

    always #5 clk = ~clk; // 100 MHz clock

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

    bind_timer_adc_sva u_bind_sva ();

    int pass_cnt = 0;
    int fail_cnt = 0;

    function automatic void check_val(
        input string      name,
        input logic [7:0] actual,
        input logic [7:0] expected
    );
        if (actual === expected) begin
            pass_cnt++;
            $display("  PASS [%02d]: %-36s = 0x%02h", pass_cnt + fail_cnt, name, actual);
        end else begin
            fail_cnt++;
            $display("  FAIL [%02d]: %-36s = 0x%02h (expected 0x%02h)",
                     pass_cnt + fail_cnt, name, actual, expected);
        end
    endfunction

    task automatic wait_adc_not_busy();
        logic [7:0] stat;
        do begin
            u_apb_if.apb_read(4'hC, stat);
        end while (stat[6] == 1'b1);
    endtask

    initial begin
        logic [7:0] rdata;
        int         pwm_hi_cnt;
        int         i;

        u_apb_if.bus_reset();
        u_adc_if.set_all_voltages(0.400, 1.111, 2.000, 3.000);

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("=== Starting tb_directed (37 register-level checks) ===");

        // -----------------------------------------------------------------
        // Checks 1..16: Reset values of all 16 registers (0x0 .. 0xF)
        // -----------------------------------------------------------------
        u_apb_if.apb_read(4'h0, rdata); check_val("Reset TMR_CTRL",   rdata, 8'h00);
        u_apb_if.apb_read(4'h1, rdata); check_val("Reset TMR_PRESC",  rdata, 8'h00);
        u_apb_if.apb_read(4'h2, rdata); check_val("Reset TMR_LOAD",   rdata, 8'hFF);
        u_apb_if.apb_read(4'h3, rdata); check_val("Reset TMR_CMP",    rdata, 8'h80);
        u_apb_if.apb_read(4'h4, rdata); check_val("Reset TMR_CNT",    rdata, 8'h00);
        u_apb_if.apb_read(4'h5, rdata); check_val("Reset ADC_CTRL",   rdata, 8'h00);
        u_apb_if.apb_read(4'h6, rdata); check_val("Reset ADC_SMP",    rdata, 8'h04);
        u_apb_if.apb_read(4'h7, rdata); check_val("Reset ADC_DIV",    rdata, 8'h00);
        u_apb_if.apb_read(4'h8, rdata); check_val("Reset ADC_THR_LO", rdata, 8'h00);
        u_apb_if.apb_read(4'h9, rdata); check_val("Reset ADC_THR_HI", rdata, 8'hFF);
        u_apb_if.apb_read(4'hA, rdata); check_val("Reset ADC_DATA",   rdata, 8'h00);
        u_apb_if.apb_read(4'hB, rdata); check_val("Reset ADC_RCH",    rdata, 8'h00);
        u_apb_if.apb_read(4'hC, rdata); check_val("Reset ADC_STAT",   rdata, 8'h10);
        u_apb_if.apb_read(4'hD, rdata); check_val("Reset IRQ_EN",     rdata, 8'h00);
        u_apb_if.apb_read(4'hE, rdata); check_val("Reset IRQ_STAT",   rdata, 8'h00);
        u_apb_if.apb_read(4'hF, rdata); check_val("Reset ID",         rdata, 8'hA8);

        // -----------------------------------------------------------------
        // Checks 17..19: Read-only protection on ID and TMR_CNT
        // -----------------------------------------------------------------
        u_apb_if.apb_write(4'hF, 8'h55);
        u_apb_if.apb_read(4'hF, rdata);
        check_val("RO protection ID", rdata, 8'hA8);

        u_apb_if.apb_write(4'h4, 8'h99);
        u_apb_if.apb_read(4'h4, rdata);
        check_val("RO protection TMR_CNT", rdata, 8'h00);

        u_apb_if.apb_write(4'h2, 8'h09);
        u_apb_if.apb_read(4'h2, rdata);
        check_val("RW TMR_LOAD write/readback", rdata, 8'h09);

        // -----------------------------------------------------------------
        // Checks 20..23: Timer periodic mode, PWM duty, OVF and CMP flags
        // -----------------------------------------------------------------
        u_apb_if.apb_write(4'h1, 8'h00); // PRESC = 0
        u_apb_if.apb_write(4'h2, 8'h09); // LOAD  = 9 (period = 10 clocks)
        u_apb_if.apb_write(4'h3, 8'h04); // CMP   = 4 (40% duty cycle)
        u_apb_if.apb_write(4'hE, 8'h3F); // Clear all IRQ flags
        u_apb_if.apb_write(4'h0, 8'h01); // Start periodic timer

        pwm_hi_cnt = 0;
        for (i = 0; i < 20; i++) begin
            @(posedge clk);
            if (u_apb_if.pwm_out) pwm_hi_cnt++;
        end
        check_val("PWM high count in 20 clocks", pwm_hi_cnt[7:0], 8'd8);

        u_apb_if.apb_write(4'h0, 8'h00); // Stop timer
        u_apb_if.apb_read(4'hE, rdata);
        check_val("Timer OVF and CMP flags set", rdata & 8'h03, 8'h03);

        u_apb_if.apb_write(4'hE, 8'h01); // W1C TMR_OVF only
        u_apb_if.apb_read(4'hE, rdata);
        check_val("IRQ_STAT after W1C TMR_OVF", rdata & 8'h03, 8'h02);

        u_apb_if.apb_write(4'hE, 8'h3F); // Clear remaining flags
        u_apb_if.apb_read(4'h4, rdata);
        check_val("TMR_CNT reset when disabled", rdata, 8'h00);

        // -----------------------------------------------------------------
        // Checks 24..25: Timer one-shot mode auto-stops and clears EN
        // -----------------------------------------------------------------
        u_apb_if.apb_write(4'h1, 8'h00); // PRESC = 0
        u_apb_if.apb_write(4'h2, 8'h04); // LOAD  = 4
        u_apb_if.apb_write(4'h0, 8'h03); // EN = 1, ONESHOT = 1
        repeat (10) @(posedge clk);
        u_apb_if.apb_read(4'h0, rdata);
        check_val("One-shot auto-clears TMR_CTRL.EN", rdata, 8'h02);
        u_apb_if.apb_read(4'h4, rdata);
        check_val("One-shot TMR_CNT stopped at 0", rdata, 8'h00);
        u_apb_if.apb_write(4'h0, 8'h00);
        u_apb_if.apb_write(4'hE, 8'h3F);

        // -----------------------------------------------------------------
        // Checks 26..30: Software-triggered ADC conversions on CH0..CH3
        // -----------------------------------------------------------------
        u_apb_if.apb_write(4'h6, 8'h02); // SMP = 2
        u_apb_if.apb_write(4'h7, 8'h00); // DIV = 0

        // Convert CH0 (0.40 V -> 0x1F)
        u_apb_if.apb_write(4'h5, 8'h03);
        wait_adc_not_busy();
        u_apb_if.apb_read(4'hB, rdata);
        check_val("CH0 ADC_RCH (valid=1, ch=0)", rdata, 8'h80);
        u_apb_if.apb_read(4'hA, rdata);
        check_val("CH0 ADC_DATA (0.40 V -> 0x1F)", rdata, 8'h1F);

        // Convert CH1 (1.111 V -> 0x56)
        u_apb_if.apb_write(4'h5, 8'h13);
        wait_adc_not_busy();
        u_apb_if.apb_read(4'hA, rdata);
        check_val("CH1 ADC_DATA (1.111 V -> 0x56)", rdata, 8'h56);

        // Convert CH2 (2.00 V -> 0x9B)
        u_apb_if.apb_write(4'h5, 8'h23);
        wait_adc_not_busy();
        u_apb_if.apb_read(4'hA, rdata);
        check_val("CH2 ADC_DATA (2.00 V -> 0x9B)", rdata, 8'h9B);

        // Convert CH3 (3.00 V -> 0xE8)
        u_apb_if.apb_write(4'h5, 8'h33);
        wait_adc_not_busy();
        u_apb_if.apb_read(4'hA, rdata);
        check_val("CH3 ADC_DATA (3.00 V -> 0xE8)", rdata, 8'hE8);

        // -----------------------------------------------------------------
        // Checks 31..32: Timer-triggered conversion (TRIG_SEL = 1)
        // -----------------------------------------------------------------
        u_apb_if.apb_write(4'hE, 8'h3F);
        u_apb_if.apb_write(4'h1, 8'h01); // PRESC = 1
        u_apb_if.apb_write(4'h2, 8'h09); // LOAD  = 9 (20 clocks)
        u_apb_if.apb_write(4'h5, 8'h15); // EN=1, TRIG_SEL=1 (tmr_ovf), CH=1
        u_apb_if.apb_write(4'h0, 8'h03); // One-shot timer trigger
        repeat (40) @(posedge clk);
        u_apb_if.apb_read(4'hC, rdata);
        check_val("Timer-triggered FIFO level=1", rdata, 8'h01);
        u_apb_if.apb_read(4'hA, rdata);
        check_val("Timer-triggered CH1 result", rdata, 8'h56);

        // -----------------------------------------------------------------
        // Checks 33..34: Window comparator (ADC_WD) & IRQ pin assertion
        // -----------------------------------------------------------------
        u_apb_if.apb_write(4'hE, 8'h3F);
        u_apb_if.apb_write(4'h8, 8'h30); // THR_LO = 0x30
        u_apb_if.apb_write(4'h9, 8'h80); // THR_HI = 0x80
        u_apb_if.apb_write(4'hD, 8'h08); // IRQ_EN = ADC_WD
        u_apb_if.apb_write(4'h5, 8'h03); // Convert CH0 (0x1F < 0x30)
        wait_adc_not_busy();
        check_val("IRQ line high on ADC_WD", {7'd0, u_apb_if.irq}, 8'h01);
        u_apb_if.apb_read(4'hE, rdata);
        check_val("IRQ_STAT has ADC_WD | ADC_EOC", rdata & 8'h0C, 8'h0C);
        u_apb_if.apb_read(4'hA, rdata);  // Pop FIFO
        u_apb_if.apb_write(4'h8, 8'h00);
        u_apb_if.apb_write(4'h9, 8'hFF);
        u_apb_if.apb_write(4'hD, 8'h00);
        u_apb_if.apb_write(4'hE, 8'h3F);

        // -----------------------------------------------------------------
        // Checks 35..37: TRIG_MISS, FIFO full (8 entries) and FIFO_OVR
        // -----------------------------------------------------------------
        u_apb_if.apb_write(4'h6, 8'h04); // SMP = 4
        u_apb_if.apb_write(4'h5, 8'h03); // Start conversion 1
        u_apb_if.apb_write(4'h5, 8'h03); // Trigger again while busy -> TRIG_MISS!
        wait_adc_not_busy();
        u_apb_if.apb_read(4'hE, rdata);
        check_val("TRIG_MISS flag set on busy trigger", rdata[5], 8'h01);

        // Push 7 more samples to fill the 8-entry FIFO
        for (i = 0; i < 7; i++) begin
            u_apb_if.apb_write(4'h5, 8'h03);
            wait_adc_not_busy();
        end
        u_apb_if.apb_read(4'hC, rdata);
        check_val("FIFO full status (FULL=1, LEVEL=8)", rdata, 8'h28);

        // 9th conversion while FIFO is full -> FIFO_OVR
        u_apb_if.apb_write(4'h5, 8'h13);
        wait_adc_not_busy();
        u_apb_if.apb_read(4'hE, rdata);
        check_val("FIFO_OVR flag set on 9th sample", rdata[4], 8'h01);

        if (fail_cnt == 0) begin
            $display("*** DIRECTED TEST PASSED (%0d / %0d checks) ***", pass_cnt, pass_cnt);
        end else begin
            $display("*** DIRECTED TEST FAILED (%0d failed of %0d) ***", fail_cnt, pass_cnt + fail_cnt);
        end
        $finish;
    end

endmodule