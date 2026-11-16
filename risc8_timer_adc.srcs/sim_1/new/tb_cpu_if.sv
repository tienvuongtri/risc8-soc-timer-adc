`timescale 1ns / 1ps

module tb_cpu_if;

    logic       clk   = 1'b0;
    logic       rst_n = 1'b0;
    logic       cs    = 1'b0;
    logic       we    = 1'b0;
    logic [3:0] addr  = 4'h0;
    logic [7:0] wdata = 8'h00;
    logic [7:0] rdata;
    logic       irq;
    logic       pwm_out;

    always #5 clk = ~clk;

    adc_if u_adc_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    timer_adc8_cpu_if dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cs         (cs),
        .we         (we),
        .addr       (addr),
        .wdata      (wdata),
        .rdata      (rdata),
        .irq        (irq),
        .adc_sample (u_adc_if.adc_sample),
        .adc_ch     (u_adc_if.adc_ch),
        .adc_dac    (u_adc_if.adc_dac),
        .adc_cmp    (u_adc_if.adc_cmp),
        .pwm_out    (pwm_out)
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

    // Single-cycle CPU store (ST)
    task automatic cpu_write(input logic [3:0] a, input logic [7:0] d);
        @(posedge clk);
        cs    <= 1'b1;
        we    <= 1'b1;
        addr  <= a;
        wdata <= d;
        @(posedge clk);
        cs    <= 1'b0;
        we    <= 1'b0;
    endtask

    // Single-cycle CPU load (LD)
    task automatic cpu_read(input logic [3:0] a, output logic [7:0] d);
        @(posedge clk);
        cs    <= 1'b1;
        we    <= 1'b0;
        addr  <= a;
        @(posedge clk);
        d     = rdata;
        cs    <= 1'b0;
    endtask

    task automatic cpu_poll_adc_done();
        logic [7:0] st;
        do begin
            cpu_read(4'hC, st);
        end while (st[6] == 1'b1);
        #1; // Cho phep NBA cap nhat irq_stat va FIFO tai suon clk ket thuc
    endtask

    initial begin
        logic [7:0] val;
        int         i;

        u_adc_if.set_all_voltages(0.400, 1.111, 2.000, 3.000);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("=== Starting tb_cpu_if (20 CPU-bus checks) ===");

        // 1. rdata must be 0x00 when cs == 0
        addr = 4'hF;
        #1;
        check_val("Bus deselected rdata == 0x00", rdata, 8'h00);

        // 2. Single-cycle read of ID register
        cpu_read(4'hF, val);
        check_val("Single-cycle LD ID (0xF)", val, 8'hA8);

        // 3. Single-cycle read of reset ADC_STAT
        cpu_read(4'hC, val);
        check_val("Single-cycle LD ADC_STAT", val, 8'h10);

        // 4. Single-cycle write & readback of TMR_LOAD
        cpu_write(4'h2, 8'h31);
        cpu_read(4'h2, val);
        check_val("Single-cycle ST/LD TMR_LOAD", val, 8'h31);

        // 5..8. Software conversions on CH0..CH3 via CPU wrapper
        cpu_write(4'h6, 8'h01); // ADC_SMP = 1
        cpu_write(4'h7, 8'h00); // ADC_DIV = 0

        cpu_write(4'h5, 8'h03); // CH0
        cpu_poll_adc_done();
        cpu_read(4'hA, val);
        check_val("CPU LD CH0 result (0x1F)", val, 8'h1F);

        cpu_write(4'h5, 8'h13); // CH1
        cpu_poll_adc_done();
        cpu_read(4'hA, val);
        check_val("CPU LD CH1 result (0x56)", val, 8'h56);

        cpu_write(4'h5, 8'h23); // CH2
        cpu_poll_adc_done();
        cpu_read(4'hA, val);
        check_val("CPU LD CH2 result (0x9B)", val, 8'h9B);

        cpu_write(4'h5, 8'h33); // CH3
        cpu_poll_adc_done();
        cpu_read(4'hA, val);
        check_val("CPU LD CH3 result (0xE8)", val, 8'hE8);

        // 9..10. Non-popping ADC_RCH read followed by popping ADC_DATA read
        cpu_write(4'h5, 8'h23); // CH2
        cpu_poll_adc_done();
        cpu_read(4'hB, val);
        check_val("ADC_RCH valid=1, ch=2 (no pop)", val, 8'h82);
        cpu_read(4'hC, val);
        check_val("ADC_STAT level still 1 after RCH", val, 8'h01);
        cpu_read(4'hA, val); // Pop

        // 11..12. Timer periodic run & compare/overflow flags
        cpu_write(4'hE, 8'h3F);
        cpu_write(4'h1, 8'h00);
        cpu_write(4'h2, 8'h05);
        cpu_write(4'h3, 8'h02);
        cpu_write(4'h0, 8'h01);
        repeat (12) @(posedge clk);
        cpu_write(4'h0, 8'h00);
        cpu_read(4'hE, val);
        check_val("Timer OVF flag set", val[0], 8'h01);
        check_val("Timer CMP flag set", val[1], 8'h01);

        // 13..14. Timer one-shot mode
        cpu_write(4'hE, 8'h3F);
        cpu_write(4'h2, 8'h03);
        cpu_write(4'h0, 8'h03); // EN=1, ONESHOT=1
        repeat (8) @(posedge clk);
        cpu_read(4'h0, val);
        check_val("One-shot cleared EN", val, 8'h02);
        cpu_read(4'h4, val);
        check_val("One-shot counter is 0", val, 8'h00);

        // 15..17. Window comparator IRQ assertion and W1C deassertion
        cpu_write(4'hE, 8'h3F);
        cpu_write(4'h9, 8'h64); // THR_HI = 100
        cpu_write(4'hD, 8'h08); // IRQ_EN = ADC_WD
        cpu_write(4'h5, 8'h33); // CH3 (232 > 100)
        cpu_poll_adc_done();
        check_val("IRQ pin high on window violation", {7'd0, irq}, 8'h01);
        cpu_read(4'hA, val);
        check_val("Window violation sample == 0xE8", val, 8'hE8);
        cpu_write(4'hE, 8'h0C); // W1C ADC_WD | ADC_EOC
        @(posedge clk);
        check_val("IRQ pin low after W1C clear", {7'd0, irq}, 8'h00);
        cpu_write(4'h9, 8'hFF);
        cpu_write(4'hD, 8'h00);

        // 18..20. Fill FIFO to 8 entries, trigger overflow, then drain
        cpu_write(4'hE, 8'h3F);
        for (i = 0; i < 8; i++) begin
            cpu_write(4'h5, 8'h03);
            cpu_poll_adc_done();
        end
        cpu_read(4'hC, val);
        check_val("FIFO full (0x28)", val, 8'h28);

        cpu_write(4'h5, 8'h13); // 9th sample dropped
        cpu_poll_adc_done();
        cpu_read(4'hE, val);
        check_val("FIFO_OVR set on 9th conversion", val[4], 8'h01);

        for (i = 0; i < 8; i++) begin
            cpu_read(4'hA, val);
        end
        cpu_read(4'hC, val);
        check_val("FIFO empty (0x10) after 8 pops", val, 8'h10);

        if (fail_cnt == 0) begin
            $display("*** CPU_IF TEST PASSED (%0d / %0d checks) ***", pass_cnt, pass_cnt);
        end else begin
            $display("*** CPU_IF TEST FAILED (%0d failed of %0d) ***", fail_cnt, pass_cnt + fail_cnt);
        end
        $finish;
    end

endmodule