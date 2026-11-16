`timescale 1ns / 1ps

module tb_risc8_5stage;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    wire       halted;
    wire [7:0] pc_out;
    wire [1:0] flags_out;
    wire       instr_done;

    // Unused I/O port wires (IO_ENABLE = 0 by default)
    wire       io_cs;
    wire       io_we;
    wire [3:0] io_addr;
    wire [7:0] io_wdata;

    always #5 clk = ~clk; // 100 MHz clock

    risc8_5stage_core #(
        .IMEM_FILE (""),
        .IO_ENABLE (0),
        .IO_PAGE   (4'hF)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc_out),
        .flags_out  (flags_out),
        .instr_done (instr_done),
        .io_cs      (io_cs),
        .io_we      (io_we),
        .io_addr    (io_addr),
        .io_wdata   (io_wdata),
        .io_rdata   (8'h00)
    );

    integer cycles  = 0;
    integer retired = 0;
    integer errors  = 0;

    task check_val;
        input [8*16-1:0] name;
        input [7:0]      actual;
        input [7:0]      expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = 0x%02h (expected 0x%02h)", name, actual, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s = 0x%02h", name, actual);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst = 1'b0;

        while (!halted && (cycles < 500)) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (instr_done)
                retired = retired + 1;
        end

        $display("CPU halted after %0d cycles, %0d instructions retired", cycles, retired);

        check_val("R0",      dut.registers.regs[0],       8'h00);
        check_val("R1",      dut.registers.regs[1],       8'h05);
        check_val("R2",      dut.registers.regs[2],       8'h03);
        check_val("R3",      dut.registers.regs[3],       8'h08);
        check_val("R4",      dut.registers.regs[4],       8'h20);
        check_val("R5",      dut.registers.regs[5],       8'h08);
        check_val("R6",      dut.registers.regs[6],       8'h00);
        check_val("R7",      dut.registers.regs[7],       8'hFF);
        check_val("MEM[20]", dut.data_memory.mem[8'h20],  8'h08);
        check_val("Flags ZC",{6'b0, flags_out},           8'h03);

        if (errors == 0)
            $display("*** ALL CPU TESTS PASSED ***");
        else
            $display("*** CPU TEST FAILED (%0d errors) ***", errors);
        $finish;
    end

endmodule