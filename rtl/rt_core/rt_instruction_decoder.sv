`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: rt_instruction_decoder
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Instruction Decoder for RT-Core
//              - Decodes 16-bit MAK-8 Instructions
//              - Generates control signals for 5-stage pipeline
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module rt_instruction_decoder (
    input  logic [15:0] instruction,
    
    // Decoded Fields
    output logic [3:0]  opcode,
    output logic [2:0]  rd,
    output logic [2:0]  rs1,
    output logic [2:0]  rs2,
    output logic [2:0]  func,
    output logic [15:0] imm_ext, // Sign-extended immediate
    
    // Control Signals
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        branch,
    output logic        jump,
    output logic [3:0]  alu_op,
    output logic        alu_src_imm, // 1 if ALU source B is immediate
    output logic        is_rt_op     // 1 if RT-specific operation (Timer/PWM)
);

    // Instruction Fields
    assign opcode = instruction[15:12];
    assign rd     = instruction[11:9];
    assign rs1    = instruction[8:6];
    assign rs2    = instruction[5:3];
    assign func   = instruction[2:0];

    // Immediate Generation (Sign Extension)
    // I-Type: imm[5:0] -> instruction[5:0]
    // B-Type: offset[8:0] -> instruction[8:0]
    logic [5:0] imm_i;
    logic [8:0] imm_b;
    assign imm_i = instruction[5:0];
    assign imm_b = instruction[8:0];

    always_comb begin
        // Defaults
        reg_write   = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        branch      = 1'b0;
        jump        = 1'b0;
        alu_op      = 4'b0000;
        alu_src_imm = 1'b0;
        is_rt_op    = 1'b0;
        imm_ext     = 16'h0;

        case (opcode)
            // R-Type (Arithmetic/Logic)
            4'b0000: begin // ADD, SUB, AND, OR, XOR, NOT, SHL, SHR
                reg_write = 1'b1;
                alu_op    = {1'b0, func}; // Map func directly to ALU op
            end
            
            // I-Type (Immediate Arithmetic)
            4'b0001: begin // ADDI
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                alu_op      = 4'b0000; // ADD
                imm_ext     = {{10{imm_i[5]}}, imm_i};
            end
            // ... (Other I-Type ops would follow similar pattern)
            
            // Memory Instructions
            4'b0111: begin // LDB (Load Byte/Word)
                reg_write   = 1'b1;
                mem_read    = 1'b1;
                alu_src_imm = 1'b1;
                alu_op      = 4'b0000; // Add offset
                imm_ext     = {{10{imm_i[5]}}, imm_i};
            end
            4'b1000: begin // STB (Store Byte/Word)
                mem_write   = 1'b1;
                alu_src_imm = 1'b1;
                alu_op      = 4'b0000; // Add offset
                imm_ext     = {{10{imm_i[5]}}, imm_i};
            end
            
            // Branch/Jump
            4'b1001: begin // Branch
                branch      = 1'b1;
                alu_op      = 4'b0001; // SUB for comparison
                imm_ext     = {{7{imm_b[8]}}, imm_b};
            end
            
            // RT Extensions
            4'b1100: begin // Timer/PWM
                is_rt_op    = 1'b1;
                // Specific decoding for RT ops would go here
            end
            
            default: begin
                // NOP or Unknown
            end
        endcase
    end

endmodule
