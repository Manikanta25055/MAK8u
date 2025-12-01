`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: gp_instruction_decoder
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Instruction Decoder for GP-Core
//              - Decodes 16-bit MAK-8 Instructions + Vector Extensions
//              - Generates control signals for 7-stage pipeline
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_instruction_decoder (
    input  logic [15:0] instruction,
    
    // Decoded Fields
    output logic [3:0]  opcode,
    output logic [2:0]  rd,
    output logic [2:0]  rs1,
    output logic [2:0]  rs2,
    output logic [2:0]  func,
    output logic [15:0] imm_ext,
    
    // Control Signals
    output logic        reg_write,
    output logic        vector_write, // Write to Vector Register
    output logic        mem_read,
    output logic        mem_write,
    output logic        branch,
    output logic        jump,
    output logic [3:0]  alu_op,
    output logic        alu_src_imm,
    output logic        is_vector_op
);

    // Instruction Fields
    assign opcode = instruction[15:12];
    assign rd     = instruction[11:9];
    assign rs1    = instruction[8:6];
    assign rs2    = instruction[5:3];
    assign func   = instruction[2:0];

    logic [5:0] imm_i;
    logic [8:0] imm_b;
    assign imm_i = instruction[5:0];
    assign imm_b = instruction[8:0];

    always_comb begin
        // Defaults
        reg_write    = 1'b0;
        vector_write = 1'b0;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        branch       = 1'b0;
        jump         = 1'b0;
        alu_op       = 4'b0000;
        alu_src_imm  = 1'b0;
        is_vector_op = 1'b0;
        imm_ext      = 16'h0;

        case (opcode)
            // R-Type (Arithmetic/Logic)
            4'b0000: begin 
                reg_write = 1'b1;
                alu_op    = {1'b0, func};
            end
            
            // I-Type
            4'b0001: begin // ADDI
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                alu_op      = 4'b0000;
                imm_ext     = {{10{imm_i[5]}}, imm_i};
            end
            
            // Memory
            4'b0111: begin // LDB
                reg_write   = 1'b1;
                mem_read    = 1'b1;
                alu_src_imm = 1'b1;
                imm_ext     = {{10{imm_i[5]}}, imm_i};
            end
            4'b1000: begin // STB
                mem_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_ext     = {{10{imm_i[5]}}, imm_i};
            end
            
            // Branch
            4'b1001: begin 
                branch      = 1'b1;
                alu_op      = 4'b0001;
                imm_ext     = {{7{imm_b[8]}}, imm_b};
            end
            
            // Vector Extensions (GP Only)
            4'b1011: begin 
                is_vector_op = 1'b1;
                vector_write = 1'b1; // Assuming vector arithmetic writes back
                // Vector decoding logic...
            end
            
            default: begin
                // NOP
            end
        endcase
    end

endmodule
