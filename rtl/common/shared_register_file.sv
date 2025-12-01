`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: shared_register_file
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Shared Register File (S0-S7)
//              - 8x 32-bit Registers accessible by both RT and GP cores
//              - Implements simple arbitration or dual-port access
//              - Priority given to RT-Core on collision
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module shared_register_file (
    input  logic        clk,
    input  logic        rst_n,
    
    // RT-Core Interface
    input  logic        rt_en,
    input  logic        rt_we,
    input  logic [2:0]  rt_addr,
    input  logic [31:0] rt_wdata,
    output logic [31:0] rt_rdata,
    
    // GP-Core Interface
    input  logic        gp_en,
    input  logic        gp_we,
    input  logic [2:0]  gp_addr,
    input  logic [31:0] gp_wdata,
    output logic [31:0] gp_rdata,
    
    // Status
    output logic        collision_detected
);

    // Shared Registers: 8 x 32-bit
    logic [31:0] shared_regs [0:7];

    // Collision Detection
    assign collision_detected = rt_en && gp_en && (rt_addr == gp_addr) && (rt_we || gp_we);

    // Synchronous Write with Priority Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                shared_regs[i] <= 32'h0;
            end
        end else begin
            // RT-Core has priority on write collision
            if (rt_en && rt_we) begin
                shared_regs[rt_addr] <= rt_wdata;
            end else if (gp_en && gp_we) begin
                shared_regs[gp_addr] <= gp_wdata;
            end
        end
    end

    // Asynchronous Read
    // If writing, output new data (bypass) or old data? 
    // For simplicity, output array value.
    assign rt_rdata = (rt_en) ? shared_regs[rt_addr] : 32'h0;
    assign gp_rdata = (gp_en) ? shared_regs[gp_addr] : 32'h0;

endmodule
