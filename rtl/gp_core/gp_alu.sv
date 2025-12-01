`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: gp_alu
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Arithmetic Logic Unit for GP-Core
//              - 32-bit Integer Operations
//              - Includes Hardware Multiplier support
//              - Optimized for performance (100MHz target)
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  alu_op,
    output logic [31:0] result,
    output logic        zero,
    output logic        negative,
    output logic        overflow,
    output logic        carry
);

    // ALU Operation Codes
    localparam ALU_ADD = 4'b0000;
    localparam ALU_SUB = 4'b0001;
    localparam ALU_AND = 4'b0010;
    localparam ALU_OR  = 4'b0011;
    localparam ALU_XOR = 4'b0100;
    localparam ALU_NOT = 4'b0101;
    localparam ALU_SHL = 4'b0110;
    localparam ALU_SHR = 4'b0111;
    localparam ALU_MUL = 4'b1000; // Hardware Multiply
    localparam ALU_SRA = 4'b1001; // Arithmetic Shift Right

    logic [63:0] mul_result;
    logic [32:0] temp_result;

    always_comb begin
        temp_result = 33'h0;
        mul_result = 64'h0;
        overflow = 1'b0;
        
        case (alu_op)
            ALU_ADD: begin
                temp_result = {1'b0, a} + {1'b0, b};
                overflow = (~a[31] & ~b[31] & temp_result[31]) | (a[31] & b[31] & ~temp_result[31]);
            end
            ALU_SUB: begin
                temp_result = {1'b0, a} - {1'b0, b};
                overflow = (~a[31] & b[31] & temp_result[31]) | (a[31] & ~b[31] & ~temp_result[31]);
            end
            ALU_AND: temp_result = {1'b0, a & b};
            ALU_OR:  temp_result = {1'b0, a | b};
            ALU_XOR: temp_result = {1'b0, a ^ b};
            ALU_NOT: temp_result = {1'b0, ~a};
            ALU_SHL: temp_result = {1'b0, a << b[4:0]};
            ALU_SHR: temp_result = {1'b0, a >> b[4:0]};
            ALU_SRA: temp_result = {1'b0, $signed(a) >>> b[4:0]};
            ALU_MUL: begin
                mul_result = $signed(a) * $signed(b);
                temp_result = {1'b0, mul_result[31:0]}; // Return lower 32 bits
                // Overflow if upper 32 bits are not sign extension of bit 31
                // Simplified: overflow if result doesn't fit in 32 bits
            end
            default: temp_result = 33'h0;
        endcase
    end

    assign result = temp_result[31:0];
    assign carry  = temp_result[32];
    assign zero   = (result == 32'h0);
    assign negative = result[31];

endmodule
