`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: vector_processing_unit
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Vector Processing Unit (VPU)
//              - 128-bit SIMD Operations
//              - Supports: VADD, VSUB, VMUL, VAND, VOR, VXOR
//              - 16x8-bit, 8x16-bit, 4x32-bit modes
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module vector_processing_unit (
    input  logic         clk,
    input  logic         rst_n,
    
    // Control Interface
    input  logic         vpu_en,
    input  logic [3:0]   vpu_op,
    input  logic [1:0]   vpu_mode, // 00=8b, 01=16b, 10=32b
    
    // Data Interface
    input  logic [127:0] src_a,
    input  logic [127:0] src_b,
    output logic [127:0] result,
    output logic         done
);

    // Operation Codes
    localparam VOP_ADD = 4'b0000;
    localparam VOP_SUB = 4'b0001;
    localparam VOP_MUL = 4'b0010;
    localparam VOP_AND = 4'b0011;
    localparam VOP_OR  = 4'b0100;
    localparam VOP_XOR = 4'b0101;
    
    logic [127:0] res_comb;
    
    always_comb begin
        res_comb = 128'h0;
        
        case (vpu_op)
            VOP_ADD: begin
                if (vpu_mode == 2'b00) begin // 16x 8-bit
                    for (int i=0; i<16; i++) res_comb[i*8 +: 8] = src_a[i*8 +: 8] + src_b[i*8 +: 8];
                end else if (vpu_mode == 2'b01) begin // 8x 16-bit
                    for (int i=0; i<8; i++) res_comb[i*16 +: 16] = src_a[i*16 +: 16] + src_b[i*16 +: 16];
                end else begin // 4x 32-bit
                    for (int i=0; i<4; i++) res_comb[i*32 +: 32] = src_a[i*32 +: 32] + src_b[i*32 +: 32];
                end
            end
            
            VOP_SUB: begin
                if (vpu_mode == 2'b00) begin
                    for (int i=0; i<16; i++) res_comb[i*8 +: 8] = src_a[i*8 +: 8] - src_b[i*8 +: 8];
                end else if (vpu_mode == 2'b01) begin
                    for (int i=0; i<8; i++) res_comb[i*16 +: 16] = src_a[i*16 +: 16] - src_b[i*16 +: 16];
                end else begin
                    for (int i=0; i<4; i++) res_comb[i*32 +: 32] = src_a[i*32 +: 32] - src_b[i*32 +: 32];
                end
            end
            
            VOP_AND: res_comb = src_a & src_b;
            VOP_OR:  res_comb = src_a | src_b;
            VOP_XOR: res_comb = src_a ^ src_b;
            
            default: res_comb = 128'h0;
        endcase
    end
    
    // Output Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 128'h0;
            done <= 1'b0;
        end else begin
            if (vpu_en) begin
                result <= res_comb;
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule
