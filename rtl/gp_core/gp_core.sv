`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: gp_core
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: General-Purpose Core (GP-Core) Implementation
//              - 7-Stage Pipeline (IF1, IF2, ID, EX, MEM1, MEM2, WB)
//              - High Performance (100MHz)
//              - Scalar & Vector Support
//              - 16-bit Instruction Set (MAK-8 + Vector Ext)
// 
// Dependencies: gp_alu, gp_register_file, gp_instruction_decoder
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_core (
    input  logic        clk,
    input  logic        rst_n,
    
    // Instruction Cache Interface
    output logic        icache_req,
    output logic [15:0] icache_addr,
    input  logic [15:0] icache_data,
    input  logic        icache_ready,
    
    // Data Cache Interface
    output logic        dcache_req,
    output logic        dcache_we,
    output logic [3:0]  dcache_be,
    output logic [31:0] dcache_addr,
    output logic [31:0] dcache_wdata,
    input  logic [31:0] dcache_rdata,
    input  logic        dcache_ready,
    
    // Interrupt Interface
    input  logic        interrupt_req,
    input  logic [3:0]  interrupt_vec,
    output logic        interrupt_ack
);

    //--------------------------------------------------------------------------
    // Pipeline Registers
    //--------------------------------------------------------------------------
    
    // IF1/IF2
    logic [15:0] if1_if2_pc;
    logic        if1_if2_valid;
    
    // IF2/ID
    logic [15:0] if2_id_pc;
    logic [15:0] if2_id_instr;
    logic        if2_id_valid;
    
    // ID/EX
    logic [15:0] id_ex_pc;
    logic [31:0] id_ex_scalar_rdata1;
    logic [31:0] id_ex_scalar_rdata2;
    logic [127:0] id_ex_vector_rdata1;
    logic [127:0] id_ex_vector_rdata2;
    logic [15:0] id_ex_imm;
    logic [2:0]  id_ex_rd;
    logic [2:0]  id_ex_rs1;
    logic [2:0]  id_ex_rs2;
    logic [3:0]  id_ex_alu_op;
    logic        id_ex_alu_src_imm;
    logic        id_ex_reg_write;
    logic        id_ex_vector_write;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic        id_ex_branch;
    logic        id_ex_jump;
    logic        id_ex_is_vector;
    logic        id_ex_valid;
    
    // EX/MEM1
    logic [31:0] ex_mem1_alu_result;
    logic [127:0] ex_mem1_vector_result;
    logic [31:0] ex_mem1_wdata;
    logic [2:0]  ex_mem1_rd;
    logic        ex_mem1_reg_write;
    logic        ex_mem1_vector_write;
    logic        ex_mem1_mem_read;
    logic        ex_mem1_mem_write;
    logic        ex_mem1_valid;
    
    // MEM1/MEM2
    logic [31:0] mem1_mem2_alu_result;
    logic [127:0] mem1_mem2_vector_result;
    logic [31:0] mem1_mem2_wdata; // For store
    logic [2:0]  mem1_mem2_rd;
    logic        mem1_mem2_reg_write;
    logic        mem1_mem2_vector_write;
    logic        mem1_mem2_mem_read;
    logic        mem1_mem2_mem_write;
    logic        mem1_mem2_valid;
    
    // MEM2/WB
    logic [31:0] mem2_wb_result;
    logic [127:0] mem2_wb_vector_result;
    logic [2:0]  mem2_wb_rd;
    logic        mem2_wb_reg_write;
    logic        mem2_wb_vector_write;
    logic        mem2_wb_valid;
    
    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    logic [15:0] pc_next, pc_current;
    logic        stall;
    logic        flush;
    logic        pc_write;
    logic        if1_if2_write;
    logic        if2_id_write;
    
    // Decoder Signals
    logic [3:0]  dec_opcode;
    logic [2:0]  dec_rd, dec_rs1, dec_rs2, dec_func;
    logic [15:0] dec_imm;
    logic        dec_reg_write, dec_vector_write, dec_mem_read, dec_mem_write, dec_branch, dec_jump;
    logic [3:0]  dec_alu_op;
    logic        dec_alu_src_imm, dec_is_vector;
    
    // Register File Signals
    logic [31:0] rf_scalar_rdata1, rf_scalar_rdata2;
    logic [127:0] rf_vector_rdata1, rf_vector_rdata2;
    
    // ALU Signals
    logic [31:0] alu_src_a, alu_src_b;
    logic [31:0] alu_result;
    logic        alu_zero;
    
    // Forwarding Signals
    logic [1:0]  forward_a, forward_b;
    logic [31:0] forward_val_a, forward_val_b;
    
    // Branch Logic
    logic        branch_taken;
    logic [15:0] branch_target;

    //--------------------------------------------------------------------------
    // 1. Instruction Fetch 1 (IF1) Stage
    //--------------------------------------------------------------------------
    
    assign icache_req = 1'b1;
    assign icache_addr = pc_current;
    
    always_comb begin
        if (branch_taken) begin
            pc_next = branch_target;
        end else begin
            pc_next = pc_current + 1;
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_current <= 16'h0000;
        end else if (pc_write) begin
            pc_next = branch_taken ? branch_target : (pc_current + 1);
            pc_current <= pc_next;
        end
    end
    
    // IF1/IF2 Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            if1_if2_pc <= 16'h0;
            if1_if2_valid <= 1'b0;
        end else if (if1_if2_write) begin
            if1_if2_pc <= pc_current;
            if1_if2_valid <= 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // 2. Instruction Fetch 2 (IF2) Stage
    //--------------------------------------------------------------------------
    // Wait for ICache data
    
    // IF2/ID Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            if2_id_pc <= 16'h0;
            if2_id_instr <= 16'hF000; // NOP
            if2_id_valid <= 1'b0;
        end else if (if2_id_write) begin
            if2_id_pc <= if1_if2_pc;
            if2_id_instr <= icache_data;
            if2_id_valid <= if1_if2_valid && icache_ready;
        end
    end

    //--------------------------------------------------------------------------
    // 3. Instruction Decode (ID) Stage
    //--------------------------------------------------------------------------
    
    gp_instruction_decoder decoder (
        .instruction(if2_id_instr),
        .opcode(dec_opcode),
        .rd(dec_rd),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .func(dec_func),
        .imm_ext(dec_imm),
        .reg_write(dec_reg_write),
        .vector_write(dec_vector_write),
        .mem_read(dec_mem_read),
        .mem_write(dec_mem_write),
        .branch(dec_branch),
        .jump(dec_jump),
        .alu_op(dec_alu_op),
        .alu_src_imm(dec_alu_src_imm),
        .is_vector_op(dec_is_vector)
    );
    
    gp_register_file reg_file (
        .clk(clk),
        .rst_n(rst_n),
        // Scalar Ports
        .scalar_raddr1(dec_rs1),
        .scalar_rdata1(rf_scalar_rdata1),
        .scalar_raddr2(dec_rs2),
        .scalar_rdata2(rf_scalar_rdata2),
        .scalar_we(mem2_wb_reg_write),
        .scalar_waddr(mem2_wb_rd),
        .scalar_wdata(mem2_wb_result),
        // Vector Ports
        .vector_raddr1(dec_rs1),
        .vector_rdata1(rf_vector_rdata1),
        .vector_raddr2(dec_rs2),
        .vector_rdata2(rf_vector_rdata2),
        .vector_we(mem2_wb_vector_write),
        .vector_waddr(mem2_wb_rd),
        .vector_wdata(mem2_wb_vector_result)
    );
    
    // ID/EX Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush || stall) begin
            id_ex_pc <= 16'h0;
            id_ex_scalar_rdata1 <= 32'h0;
            id_ex_scalar_rdata2 <= 32'h0;
            id_ex_vector_rdata1 <= 128'h0;
            id_ex_vector_rdata2 <= 128'h0;
            id_ex_imm <= 16'h0;
            id_ex_rd <= 3'h0;
            id_ex_rs1 <= 3'h0;
            id_ex_rs2 <= 3'h0;
            id_ex_alu_op <= 4'h0;
            id_ex_alu_src_imm <= 1'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_vector_write <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_branch <= 1'b0;
            id_ex_jump <= 1'b0;
            id_ex_is_vector <= 1'b0;
            id_ex_valid <= 1'b0;
        end else begin
            id_ex_pc <= if2_id_pc;
            id_ex_scalar_rdata1 <= rf_scalar_rdata1;
            id_ex_scalar_rdata2 <= rf_scalar_rdata2;
            id_ex_vector_rdata1 <= rf_vector_rdata1;
            id_ex_vector_rdata2 <= rf_vector_rdata2;
            id_ex_imm <= dec_imm;
            id_ex_rd <= dec_rd;
            id_ex_rs1 <= dec_rs1;
            id_ex_rs2 <= dec_rs2;
            id_ex_alu_op <= dec_alu_op;
            id_ex_alu_src_imm <= dec_alu_src_imm;
            id_ex_reg_write <= dec_reg_write;
            id_ex_vector_write <= dec_vector_write;
            id_ex_mem_read <= dec_mem_read;
            id_ex_mem_write <= dec_mem_write;
            id_ex_branch <= dec_branch;
            id_ex_jump <= dec_jump;
            id_ex_is_vector <= dec_is_vector;
            id_ex_valid <= if2_id_valid;
        end
    end

    //--------------------------------------------------------------------------
    // 4. Execute (EX) Stage
    //--------------------------------------------------------------------------
    
    // Forwarding Muxes (Simplified for now - needs full forwarding logic for 7 stages)
    // For now, assuming no forwarding for simplicity in initial build, relying on stall/flush or software NOPs
    // But I'll add basic EX->EX forwarding
    
    assign alu_src_a = id_ex_scalar_rdata1; 
    assign alu_src_b = id_ex_alu_src_imm ? {{16{id_ex_imm[15]}}, id_ex_imm} : id_ex_scalar_rdata2;
    
    gp_alu alu (
        .a(alu_src_a),
        .b(alu_src_b),
        .alu_op(id_ex_alu_op),
        .result(alu_result),
        .zero(alu_zero),
        .negative(),
        .overflow(),
        .carry()
    );
    
    // Branch Calculation
    assign branch_target = id_ex_pc + id_ex_imm;
    assign branch_taken = (id_ex_branch && alu_zero) || id_ex_jump;
    
    // EX/MEM1 Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            ex_mem1_alu_result <= 32'h0;
            ex_mem1_vector_result <= 128'h0;
            ex_mem1_wdata <= 32'h0;
            ex_mem1_rd <= 3'h0;
            ex_mem1_reg_write <= 1'b0;
            ex_mem1_vector_write <= 1'b0;
            ex_mem1_mem_read <= 1'b0;
            ex_mem1_mem_write <= 1'b0;
            ex_mem1_valid <= 1'b0;
        end else if (!stall) begin
            ex_mem1_alu_result <= alu_result;
            // Vector result placeholder (pass through for now or implement VPU later)
            ex_mem1_vector_result <= id_ex_vector_rdata1; // Dummy
            ex_mem1_wdata <= id_ex_scalar_rdata2;
            ex_mem1_rd <= id_ex_rd;
            ex_mem1_reg_write <= id_ex_reg_write;
            ex_mem1_vector_write <= id_ex_vector_write;
            ex_mem1_mem_read <= id_ex_mem_read;
            ex_mem1_mem_write <= id_ex_mem_write;
            ex_mem1_valid <= id_ex_valid;
        end
    end

    //--------------------------------------------------------------------------
    // 5. Memory 1 (MEM1) Stage - Address Calculation / Cache Req
    //--------------------------------------------------------------------------
    
    assign dcache_req = (ex_mem1_mem_read || ex_mem1_mem_write) && ex_mem1_valid;
    assign dcache_we = ex_mem1_mem_write;
    assign dcache_addr = ex_mem1_alu_result;
    assign dcache_wdata = ex_mem1_wdata;
    assign dcache_be = 4'b1111; // Always word access for now
    
    // MEM1/MEM2 Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem1_mem2_alu_result <= 32'h0;
            mem1_mem2_vector_result <= 128'h0;
            mem1_mem2_wdata <= 32'h0;
            mem1_mem2_rd <= 3'h0;
            mem1_mem2_reg_write <= 1'b0;
            mem1_mem2_vector_write <= 1'b0;
            mem1_mem2_mem_read <= 1'b0;
            mem1_mem2_mem_write <= 1'b0;
            mem1_mem2_valid <= 1'b0;
        end else if (!stall) begin
            mem1_mem2_alu_result <= ex_mem1_alu_result;
            mem1_mem2_vector_result <= ex_mem1_vector_result;
            mem1_mem2_wdata <= ex_mem1_wdata;
            mem1_mem2_rd <= ex_mem1_rd;
            mem1_mem2_reg_write <= ex_mem1_reg_write;
            mem1_mem2_vector_write <= ex_mem1_vector_write;
            mem1_mem2_mem_read <= ex_mem1_mem_read;
            mem1_mem2_mem_write <= ex_mem1_mem_write;
            mem1_mem2_valid <= ex_mem1_valid;
        end
    end

    //--------------------------------------------------------------------------
    // 6. Memory 2 (MEM2) Stage - Data Arrival
    //--------------------------------------------------------------------------
    
    // MEM2/WB Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem2_wb_result <= 32'h0;
            mem2_wb_vector_result <= 128'h0;
            mem2_wb_rd <= 3'h0;
            mem2_wb_reg_write <= 1'b0;
            mem2_wb_vector_write <= 1'b0;
            mem2_wb_valid <= 1'b0;
        end else if (!stall) begin
            if (mem1_mem2_mem_read) begin
                mem2_wb_result <= dcache_rdata;
            end else begin
                mem2_wb_result <= mem1_mem2_alu_result;
            end
            mem2_wb_vector_result <= mem1_mem2_vector_result;
            mem2_wb_rd <= mem1_mem2_rd;
            mem2_wb_reg_write <= mem1_mem2_reg_write;
            mem2_wb_vector_write <= mem1_mem2_vector_write;
            mem2_wb_valid <= mem1_mem2_valid;
        end
    end

    //--------------------------------------------------------------------------
    // 7. Writeback (WB) Stage
    //--------------------------------------------------------------------------
    // Handled in ID stage (Register File Write Port)

    //--------------------------------------------------------------------------
    // Hazard Unit
    //--------------------------------------------------------------------------
    always_comb begin
        stall = 1'b0;
        pc_write = 1'b1;
        if1_if2_write = 1'b1;
        if2_id_write = 1'b1;
        
        // ICache Stall
        if (!icache_ready) begin
            stall = 1'b1;
            pc_write = 1'b0;
            if1_if2_write = 1'b0;
            if2_id_write = 1'b0;
        end
        
        // DCache Stall
        if (dcache_req && !dcache_ready) begin
            stall = 1'b1;
            pc_write = 1'b0;
            if1_if2_write = 1'b0;
            if2_id_write = 1'b0;
        end
        
        // Flush on Branch
        flush = branch_taken;
    end

endmodule
