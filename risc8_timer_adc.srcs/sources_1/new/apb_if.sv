`timescale 1ns / 1ps

interface apb_if (
    input logic clk,
    input logic rst_n
);
    logic       psel;
    logic       penable;
    logic       pwrite;
    logic [3:0] paddr;
    logic [7:0] pwdata;
    logic [7:0] prdata;
    logic       pready;
    logic       pslverr;
    logic       irq;
    logic       pwm_out;

//    // Clocking block for UVM Driver
//    clocking drv_cb @(posedge clk);
//        default input #1step output #1ns;
//        output psel, penable, pwrite, paddr, pwdata;
//        input  prdata, pready, pslverr, irq, pwm_out;
//    endclocking

//    // Clocking block for UVM Monitor
//    clocking mon_cb @(posedge clk);
//        default input #1step;
//        input psel, penable, pwrite, paddr, pwdata;
//        input prdata, pready, pslverr, irq, pwm_out;
//    endclocking

    // Helper task: Reset APB master signals
    task automatic bus_reset();
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
        paddr   <= 4'h0;
        pwdata  <= 8'h00;
    endtask

    // Helper task: 2-cycle APB write transaction (Setup -> Access)
    task automatic apb_write(input logic [3:0] addr, input logic [7:0] data);
        @(posedge clk);
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b1;
        paddr   <= addr;
        pwdata  <= data;
        @(posedge clk);
        penable <= 1'b1;
        @(posedge clk);
        while (!pready) @(posedge clk);
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    // Helper task: 2-cycle APB read transaction (Setup -> Access)
    task automatic apb_read(input logic [3:0] addr, output logic [7:0] data);
        @(posedge clk);
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b0;
        paddr   <= addr;
        @(posedge clk);
        penable <= 1'b1;
        @(posedge clk);
        while (!pready) @(posedge clk);
        data    = prdata;
        psel    <= 1'b0;
        penable <= 1'b0;
    endtask

    // APB protocol assertion: PENABLE must only be asserted when PSEL is high
    property p_penable_requires_psel;
        @(posedge clk) disable iff (!rst_n)
        penable |-> psel;
    endproperty
    apb_penable_check: assert property (p_penable_requires_psel)
        else $error("[APB_IF] Protocol violation: penable asserted without psel");

endinterface