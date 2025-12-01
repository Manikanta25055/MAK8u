`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: stack_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Hardware Stack Controller
//              - Manages dedicated stack memory for RT and GP cores
//              - Hardware overflow/underflow detection
//              - 4KB Stack per core
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module stack_controller #(
    parameter STACK_SIZE = 1024 // 1024 words = 4KB
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // RT-Core Stack Interface
    input  logic        rt_push,
    input  logic        rt_pop,
    input  logic [31:0] rt_wdata,
    output logic [31:0] rt_rdata,
    output logic        rt_overflow,
    output logic        rt_underflow,
    
    // GP-Core Stack Interface
    input  logic        gp_push,
    input  logic        gp_pop,
    input  logic [31:0] gp_wdata,
    output logic [31:0] gp_rdata,
    output logic        gp_overflow,
    output logic        gp_underflow
);

    // Stack Memory
    logic [31:0] rt_stack_mem [0:STACK_SIZE-1];
    logic [31:0] gp_stack_mem [0:STACK_SIZE-1];
    
    // Stack Pointers
    logic [9:0] rt_sp;
    logic [9:0] gp_sp;
    
    // RT-Core Stack Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rt_sp <= 10'h0; // Empty stack at 0? Or grows down? Let's say grows UP for simplicity here.
            rt_overflow <= 1'b0;
            rt_underflow <= 1'b0;
            rt_rdata <= 32'h0;
        end else begin
            rt_overflow <= 1'b0;
            rt_underflow <= 1'b0;
            
            if (rt_push) begin
                if (rt_sp == STACK_SIZE-1) begin
                    rt_overflow <= 1'b1;
                end else begin
                    rt_stack_mem[rt_sp] <= rt_wdata;
                    rt_sp <= rt_sp + 1;
                end
            end else if (rt_pop) begin
                if (rt_sp == 0) begin
                    rt_underflow <= 1'b1;
                end else begin
                    rt_sp <= rt_sp - 1;
                    rt_rdata <= rt_stack_mem[rt_sp - 1];
                end
            end
        end
    end
    
    // GP-Core Stack Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gp_sp <= 10'h0;
            gp_overflow <= 1'b0;
            gp_underflow <= 1'b0;
            gp_rdata <= 32'h0;
        end else begin
            gp_overflow <= 1'b0;
            gp_underflow <= 1'b0;
            
            if (gp_push) begin
                if (gp_sp == STACK_SIZE-1) begin
                    gp_overflow <= 1'b1;
                end else begin
                    gp_stack_mem[gp_sp] <= gp_wdata;
                    gp_sp <= gp_sp + 1;
                end
            end else if (gp_pop) begin
                if (gp_sp == 0) begin
                    gp_underflow <= 1'b1;
                end else begin
                    gp_sp <= gp_sp - 1;
                    gp_rdata <= gp_stack_mem[gp_sp - 1];
                end
            end
        end
    end

endmodule
