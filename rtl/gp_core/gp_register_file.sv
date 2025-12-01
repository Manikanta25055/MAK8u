`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: gp_register_file
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Register File for General-Purpose Core (GP-Core)
//              - 8x 32-bit Scalar Registers (R0-R7)
//              - 8x 128-bit Vector Registers (V0-V7)
//              - Separate ports for Scalar and Vector access
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_register_file (
    input  logic        clk,
    input  logic        rst_n,
    
    // --- Scalar Register Interface (R0-R7) ---
    // Read Port 1
    input  logic [2:0]  scalar_raddr1,
    output logic [31:0] scalar_rdata1,
    
    // Read Port 2
    input  logic [2:0]  scalar_raddr2,
    output logic [31:0] scalar_rdata2,
    
    // Write Port
    input  logic        scalar_we,
    input  logic [2:0]  scalar_waddr,
    input  logic [31:0] scalar_wdata,
    
    // --- Vector Register Interface (V0-V7) ---
    // Read Port 1
    input  logic [2:0]   vector_raddr1,
    output logic [127:0] vector_rdata1,
    
    // Read Port 2
    input  logic [2:0]   vector_raddr2,
    output logic [127:0] vector_rdata2,
    
    // Write Port
    input  logic         vector_we,
    input  logic [2:0]   vector_waddr,
    input  logic [127:0] vector_wdata
);

    // Scalar Registers: 8 x 32-bit
    logic [31:0] scalar_regs [0:7];
    
    // Vector Registers: 8 x 128-bit
    logic [127:0] vector_regs [0:7];

    // --- Scalar Operations ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                scalar_regs[i] <= 32'h0;
            end
        end else if (scalar_we) begin
            scalar_regs[scalar_waddr] <= scalar_wdata;
        end
    end

    assign scalar_rdata1 = scalar_regs[scalar_raddr1];
    assign scalar_rdata2 = scalar_regs[scalar_raddr2];

    // --- Vector Operations ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                vector_regs[i] <= 128'h0;
            end
        end else if (vector_we) begin
            vector_regs[vector_waddr] <= vector_wdata;
        end
    end

    assign vector_rdata1 = vector_regs[vector_raddr1];
    assign vector_rdata2 = vector_regs[vector_raddr2];

endmodule
