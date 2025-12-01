`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: rt_register_file
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Register File for Real-Time Core (RT-Core)
//              - 8x 32-bit General Purpose Registers (R0-R7)
//              - 2 Read Ports, 1 Write Port
//              - R0 is NOT hardwired to 0 (General Purpose)
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module rt_register_file (
    input  logic        clk,
    input  logic        rst_n,
    
    // Read Port 1
    input  logic [2:0]  raddr1,
    output logic [31:0] rdata1,
    
    // Read Port 2
    input  logic [2:0]  raddr2,
    output logic [31:0] rdata2,
    
    // Write Port
    input  logic        we,
    input  logic [2:0]  waddr,
    input  logic [31:0] wdata
);

    // Register Array: 8 registers of 32-bit width
    logic [31:0] registers [0:7];

    // Write Operation (Synchronous)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                registers[i] <= 32'h0;
            end
        end else if (we) begin
            registers[waddr] <= wdata;
        end
    end

    // Read Operations (Asynchronous)
    // Forwarding logic should be handled in the pipeline, but for simple
    // register file behavior, we output the current value.
    // If reading and writing same address in same cycle, this outputs OLD value.
    // (Standard block RAM / distributed RAM behavior).
    assign rdata1 = registers[raddr1];
    assign rdata2 = registers[raddr2];

endmodule
