`timescale 1ns / 1ps

module tb_risc8_soc;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    wire       halted;
    wire [7:0] pc_out;
    wire       irq;
    wire       pwm_out;
    wire       adc_sample;
    wire [1:0] adc_ch;
    wire [7:0] adc_dac;
    wire       adc_cmp;

    always #5 clk = ~clk; // 100 MHz system clock

    risc8_soc #(
        .IMEM_FILE ("soc_demo.mem")
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc_out),
        .irq        (irq),
        .pwm_out    (pwm_out),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

    afe_model u_afe (
        .clk        (clk),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .adc_cmp    (adc_cmp)
    );

`ifdef SVA
    bind_timer_adc_sva u_bind_sva ();
`endif

    integer cycle_cnt  = 0;
    integer io_acc_cnt = 0;
    integer irq_seen   = 0;
    integer pwm_hi_cnt = 0;
    integer pass_cnt   = 0;
    integer fail_cnt   = 0;
    integer trace_fd;
    integer i;

    task check_mem;
        input [7:0]      addr;
        input [7:0]      expected;
        input [8*44-1:0] label;
        reg   [7:0]      actual;
        begin
            actual = dut.u_cpu.data_memory.mem[addr];
            if (actual === expected) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS: MEM[%02x] = %02x  (%0s)", addr, actual, label);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL: MEM[%02x] = %02x, expected %02x (%0s)",
                         addr, actual, expected, label);
            end
        end
    endtask

    initial begin
        trace_fd = $fopen("io_trace.csv", "w");
        $fwrite(trace_fd, "cycle,pc,io_cs,io_we,io_addr,io_wdata,io_rdata,irq,pwm_out\n");

        repeat (2) @(posedge clk);
        rst = 1'b0;

        while (!halted && (cycle_cnt < 5000)) begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;
            if (dut.io_cs) begin
                io_acc_cnt = io_acc_cnt + 1;
            end
            if (irq) begin
                irq_seen = 1;
            end
            $fwrite(trace_fd, "%0d,%02x,%0d,%0d,%01x,%02x,%02x,%0d,%0d\n",
                    cycle_cnt, pc_out, dut.io_cs, dut.io_we,
                    dut.io_addr, dut.io_wdata, dut.io_rdata, irq, pwm_out);
        end

        $fclose(trace_fd);
        $display("CPU halted after %0d cycles, %0d I/O accesses", cycle_cnt, io_acc_cnt);

        // Check 1: CPU halted cleanly before timeout
        if (halted) begin
            pass_cnt = pass_cnt + 1;
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("FAIL: CPU did not halt before timeout");
        end

        // Checks 2..19: Verify RAM results written by soc_demo.mem (0x80 .. 0x91)
        check_mem(8'h80, 8'hA8, "A: ID register");
        check_mem(8'h81, 8'h81, "B: ADC_RCH = valid, ch1");
        check_mem(8'h82, 8'h56, "B: ch1 code (1.111 V)");
        check_mem(8'h83, 8'h82, "C: ADC_RCH = valid, ch2 (sample 1)");
        check_mem(8'h84, 8'h9B, "C: ch2 code (2.0 V), timer start 1");
        check_mem(8'h85, 8'h82, "C: ADC_RCH = valid, ch2 (sample 2)");
        check_mem(8'h86, 8'h9B, "C: ch2 code (2.0 V), timer start 2");
        check_mem(8'h87, 8'h82, "C: ADC_RCH = valid, ch2 (sample 3)");
        check_mem(8'h88, 8'h9B, "C: ch2 code (2.0 V), timer start 3");
        check_mem(8'h89, 8'h82, "C: ADC_RCH = valid, ch2 (sample 4)");
        check_mem(8'h8A, 8'h9B, "C: ch2 code (2.0 V), timer start 4");
        check_mem(8'h8B, 8'h07, "C: IRQ_STAT = OVF | CMP | EOC");
        check_mem(8'h8C, 8'h03, "C: IRQ_STAT after W1C 0x04");
        check_mem(8'h8D, 8'h0C, "D: IRQ_STAT = EOC | WD");
        check_mem(8'h8E, 8'hE8, "D: ch3 code (3.0 V)");
        check_mem(8'h8F, 8'h1F, "F: 1st pop, ch0 code (0.40 V)");
        check_mem(8'h90, 8'h56, "F: 2nd pop, ch1 code (1.111 V)");
        check_mem(8'h91, 8'h10, "F: ADC_STAT = empty after 2 pops");

        // Check 20 & 21: irq pin rose during Part D and was cleared
        if (irq_seen && (irq === 1'b0)) begin
            pass_cnt = pass_cnt + 2;
            $display("PASS: irq pin went high during part D and was cleared");
        end else begin
            fail_cnt = fail_cnt + 2;
            $display("FAIL: irq_seen=%0d, final irq=%b", irq_seen, irq);
        end

        // Check 22: Measure PWM duty cycle over 100 clocks after CPU halt (expect 30/100)
        pwm_hi_cnt = 0;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (pwm_out) begin
                pwm_hi_cnt = pwm_hi_cnt + 1;
            end
        end

        if (pwm_hi_cnt == 30) begin
            pass_cnt = pass_cnt + 1;
            $display("PASS: PWM high for %0d of 100 clocks", pwm_hi_cnt);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("FAIL: PWM high for %0d of 100 clocks (expected 30)", pwm_hi_cnt);
        end

        if (fail_cnt == 0) begin
            $display("*** SOC TEST PASSED *** (%0d checks)", pass_cnt);
        end else begin
            $display("*** SOC TEST FAILED *** (%0d failed, %0d passed)", fail_cnt, pass_cnt);
        end
        $finish;
    end

endmodule