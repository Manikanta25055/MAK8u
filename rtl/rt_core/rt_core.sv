`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: rt_core
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Real-Time Core (RT-Core) Implementation
//              - 5-Stage Pipeline (IF, ID, EX, MEM, WB)
//              - Deterministic Execution
//              - 16-bit Instruction Set (MAK-8)
//              - 32-bit Data Path
// 
// Dependencies: rt_alu, rt_register_file, rt_instruction_decoder
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module rt_core (
    input  logic        clk,
    input  logic        rst_n,
    
    // Instruction Cache Interface
    output logic        icache_req,
    output logic [15:0] icache_addr,
    input  logic [15:0] icache_data,
    input  logic        icache_ready,
    
    // Data Memory Interface
    output logic        dmem_en,
    output logic        dmem_we,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_ready,
    
    // Interrupt Interface
    input  logic        interrupt_req,
    input  logic [3:0]  interrupt_vec,
    output logic        interrupt_ack
);

    //--------------------------------------------------------------------------
    // Pipeline Registers
    //--------------------------------------------------------------------------
    
    // IF/ID Pipeline Register
    logic [15:0] if_id_pc;
    logic [15:0] if_id_instr;
    logic        if_id_valid;
    
    // ID/EX Pipeline Register
    logic [15:0] id_ex_pc;
    logic [31:0] id_ex_rdata1;
    logic [31:0] id_ex_rdata2;
    logic [15:0] id_ex_imm;
    logic [2:0]  id_ex_rd;
    logic [2:0]  id_ex_rs1;
    logic [2:0]  id_ex_rs2;
    logic [3:0]  id_ex_alu_op;
    logic        id_ex_alu_src_imm;
    logic        id_ex_reg_write;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic        id_ex_branch;
    logic        id_ex_jump;
    logic        id_ex_valid;
    
    // EX/MEM Pipeline Register
    logic [31:0] ex_mem_alu_result;
    logic [31:0] ex_mem_wdata;
    logic [2:0]  ex_mem_rd;
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic        ex_mem_valid;
    
    // MEM/WB Pipeline Register
    logic [31:0] mem_wb_result;
    logic [2:0]  mem_wb_rd;
    logic        mem_wb_reg_write;
    logic        mem_wb_valid;
    
    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    logic [15:0] pc_next, pc_current;
    logic        stall;
    logic        flush;
    logic        pc_write;
    logic        if_id_write;
    
    // Decoder Signals
    logic [3:0]  dec_opcode;
    logic [2:0]  dec_rd, dec_rs1, dec_rs2, dec_func;
    logic [15:0] dec_imm;
    logic        dec_reg_write, dec_mem_read, dec_mem_write, dec_branch, dec_jump;
    logic [3:0]  dec_alu_op;
    logic        dec_alu_src_imm;
    
    // Register File Signals
    logic [31:0] rf_rdata1, rf_rdata2;
    
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
    // 1. Instruction Fetch (IF) Stage
    //--------------------------------------------------------------------------
    
    assign icache_req = 1'b1; // Always request instruction
    assign icache_addr = pc_current;
    
    // PC Mux
    always_comb begin
        if (branch_taken) begin
            pc_next = branch_target;
        end else begin
            pc_next = pc_current + 1; // 16-bit instructions, word addressable? 
            // NOTE: ICache uses 16-bit address. If byte addressable, +2. 
            // If word addressable, +1. Spec says "128KB program ROM".
            // Let's assume byte addressable for standard, so +2.
            // Wait, ICache addr is [15:0]. 64K words? 
            // Spec: "128KB program ROM". 128KB = 64K x 16-bit words.
            // So 16-bit address covers 64K words. +1 is correct for word addressing.
        end
    end
    
    // PC Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_current <= 16'h0000;
        end else if (pc_write) begin
            pc_next = branch_taken ? branch_target : (pc_current + 1); // Recalculate to be safe
            pc_current <= pc_next;
        end
    end
    
    // IF/ID Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc <= 16'h0;
            if_id_instr <= 16'h0; // NOP
            if_id_valid <= 1'b0;
        end else if (flush) begin
            if_id_valid <= 1'b0;
            if_id_instr <= 16'hF000; // NOP (Assuming F000 is NOP, based on decoder default)
        end else if (if_id_write) begin
            if_id_pc <= pc_current;
            if_id_instr <= icache_data;
            if_id_valid <= icache_ready;
        end
    end

    //--------------------------------------------------------------------------
    // 2. Instruction Decode (ID) Stage
    //--------------------------------------------------------------------------
    
    rt_instruction_decoder decoder (
        .instruction(if_id_instr),
        .opcode(dec_opcode),
        .rd(dec_rd),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .func(dec_func),
        .imm_ext(dec_imm),
        .reg_write(dec_reg_write),
        .mem_read(dec_mem_read),
        .mem_write(dec_mem_write),
        .branch(dec_branch),
        .jump(dec_jump),
        .alu_op(dec_alu_op),
        .alu_src_imm(dec_alu_src_imm),
        .is_rt_op()
    );
    
    rt_register_file reg_file (
        .clk(clk),
        .rst_n(rst_n),
        .raddr1(dec_rs1),
        .rdata1(rf_rdata1),
        .raddr2(dec_rs2),
        .rdata2(rf_rdata2),
        .we(mem_wb_reg_write),
        .waddr(mem_wb_rd),
        .wdata(mem_wb_result)
    );
    
    // ID/EX Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush || stall) begin
            id_ex_pc <= 16'h0;
            id_ex_rdata1 <= 32'h0;
            id_ex_rdata2 <= 32'h0;
            id_ex_imm <= 16'h0;
            id_ex_rd <= 3'h0;
            id_ex_rs1 <= 3'h0;
            id_ex_rs2 <= 3'h0;
            id_ex_alu_op <= 4'h0;
            id_ex_alu_src_imm <= 1'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_branch <= 1'b0;
            id_ex_jump <= 1'b0;
            id_ex_valid <= 1'b0;
        end else begin
            id_ex_pc <= if_id_pc;
            id_ex_rdata1 <= rf_rdata1;
            id_ex_rdata2 <= rf_rdata2;
            id_ex_imm <= dec_imm;
            id_ex_rd <= dec_rd;
            id_ex_rs1 <= dec_rs1;
            id_ex_rs2 <= dec_rs2;
            id_ex_alu_op <= dec_alu_op;
            id_ex_alu_src_imm <= dec_alu_src_imm;
            id_ex_reg_write <= dec_reg_write;
            id_ex_mem_read <= dec_mem_read;
            id_ex_mem_write <= dec_mem_write;
            id_ex_branch <= dec_branch;
            id_ex_jump <= dec_jump;
            id_ex_valid <= if_id_valid;
        end
    end

    //--------------------------------------------------------------------------
    // 3. Execute (EX) Stage
    //--------------------------------------------------------------------------
    
    // Forwarding Muxes
    always_comb begin
        case (forward_a)
            2'b00: forward_val_a = id_ex_rdata1;
            2'b01: forward_val_a = mem_wb_result; // Forward from WB
            2'b10: forward_val_a = ex_mem_alu_result; // Forward from MEM
            default: forward_val_a = id_ex_rdata1;
        endcase
        
        case (forward_b)
            2'b00: forward_val_b = id_ex_rdata2;
            2'b01: forward_val_b = mem_wb_result;
            2'b10: forward_val_b = ex_mem_alu_result;
            default: forward_val_b = id_ex_rdata2;
        endcase
    end
    
    assign alu_src_a = forward_val_a;
    assign alu_src_b = id_ex_alu_src_imm ? {{16{id_ex_imm[15]}}, id_ex_imm} : forward_val_b;
    
    rt_alu alu (
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
    assign branch_taken = (id_ex_branch && alu_zero) || id_ex_jump; // Simple BEQ
    
    // EX/MEM Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin // Flush on branch taken
            ex_mem_alu_result <= 32'h0;
            ex_mem_wdata <= 32'h0;
            ex_mem_rd <= 3'h0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_valid <= 1'b0;
        end else if (!stall) begin
            ex_mem_alu_result <= alu_result;
            ex_mem_wdata <= forward_val_b; // Store data
            ex_mem_rd <= id_ex_rd;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_mem_read <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_valid <= id_ex_valid;
        end
    end

    //--------------------------------------------------------------------------
    // 4. Memory (MEM) Stage
    //--------------------------------------------------------------------------
    
    assign dmem_en = (ex_mem_mem_read || ex_mem_mem_write) && ex_mem_valid;
    assign dmem_we = ex_mem_mem_write;
    assign dmem_addr = ex_mem_alu_result;
    assign dmem_wdata = ex_mem_wdata;
    
    // MEM/WB Register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_result <= 32'h0;
            mem_wb_rd <= 3'h0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_valid <= 1'b0;
        end else if (!stall) begin // If memory stalls, we stall here too
            if (ex_mem_mem_read) begin
                mem_wb_result <= dmem_rdata;
            end else begin
                mem_wb_result <= ex_mem_alu_result;
            end
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_valid <= ex_mem_valid;
        end
    end

    //--------------------------------------------------------------------------
    // Hazard Unit
    //--------------------------------------------------------------------------
    
    always_comb begin
        // Forwarding Logic
        forward_a = 2'b00;
        forward_b = 2'b00;
        
        // EX Hazard (Forward from MEM stage)
        if (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1))
            forward_a = 2'b10;
        if (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs2))
            forward_b = 2'b10;
            
        // MEM Hazard (Forward from WB stage)
        if (mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1) && 
            !(ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1)))
            forward_a = 2'b01;
        if (mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs2) && 
            !(ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs2)))
            forward_b = 2'b01;
            
        // Stall Logic
        stall = 1'b0;
        pc_write = 1'b1;
        if_id_write = 1'b1;
        
        // ICache Stall
        if (!icache_ready) begin
            stall = 1'b1;
            pc_write = 1'b0;
            if_id_write = 1'b0;
        end
        
        // Data Memory Stall (if dmem_ready goes low during access)
        // Note: dmem_ready is usually 1-cycle latency, but if it can stall:
        if (dmem_en && !dmem_ready) begin
            stall = 1'b1;
            pc_write = 1'b0;
            if_id_write = 1'b0;
        end
        
        // Load-Use Hazard
        if (id_ex_mem_read && ((id_ex_rd == dec_rs1) || (id_ex_rd == dec_rs2))) begin
            stall = 1'b1;
            pc_write = 1'b0;
            if_id_write = 1'b0;
        end
        
        // Flush on Branch
        flush = branch_taken;
    end

endmodule
