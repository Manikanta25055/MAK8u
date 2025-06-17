`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/29/2024
// Design Name: MAKu Microcontroller
// Module Name: program_rom_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: 128KB Program ROM Controller for MAKu Dual-Core Microcontroller
//              Supports simultaneous access from both RT-Core and GP-Core
//              Implements true dual-port Block RAM configuration
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - 128KB = 64K x 16-bit instructions
// - Dual-port access for both cores
// - Synchronous read with 1-cycle latency
// - Supports memory initialization from .mem files
// - Address space: 0x00000 - 0x1FFFF
// 
//////////////////////////////////////////////////////////////////////////////////

module program_rom_controller #(
    parameter ADDR_WIDTH = 16,          // 64K instructions (16-bit addresses)
    parameter DATA_WIDTH = 16,          // 16-bit instructions
    parameter ROM_SIZE = 65536,         // 64K instructions = 128KB
    parameter MEM_INIT_FILE = ""        // Memory initialization file path
)(
    // Clock and Reset
    input  logic                     clk,
    input  logic                     rst_n,
    
    // RT-Core Interface (Port A)
    input  logic                     rt_core_en,        // Enable signal
    input  logic [ADDR_WIDTH-1:0]   rt_core_addr,      // Instruction address
    output logic [DATA_WIDTH-1:0]   rt_core_data,      // Instruction data
    output logic                     rt_core_valid,     // Data valid signal
    
    // GP-Core Interface (Port B)  
    input  logic                     gp_core_en,        // Enable signal
    input  logic [ADDR_WIDTH-1:0]   gp_core_addr,      // Instruction address
    output logic [DATA_WIDTH-1:0]   gp_core_data,      // Instruction data
    output logic                     gp_core_valid,     // Data valid signal
    
    // System Interface
    output logic                     rom_ready,         // ROM initialization complete
    output logic [31:0]              access_count_rt,   // RT-Core access counter
    output logic [31:0]              access_count_gp    // GP-Core access counter
);

    // Internal ROM storage - using Block RAM inference
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] rom_memory [0:ROM_SIZE-1];
    
    // Pipeline registers for valid signals
    logic rt_core_valid_reg;
    logic gp_core_valid_reg;
    
    // Access counters for debugging/profiling
    logic [31:0] rt_access_counter;
    logic [31:0] gp_access_counter;
    
    // ROM initialization flag
    logic rom_initialized;
    
    //--------------------------------------------------------------------------
    // ROM Initialization
    //--------------------------------------------------------------------------
    initial begin
        rom_initialized = 1'b0;
        
        // Initialize all locations to NOP (0xF000) by default
        for (int i = 0; i < ROM_SIZE; i++) begin
            rom_memory[i] = 16'hF000;  // NOP instruction
        end
        
        // Load from memory file if specified
        if (MEM_INIT_FILE != "") begin
            $readmemh(MEM_INIT_FILE, rom_memory);
            $display("MAKu ROM: Loaded program from %s", MEM_INIT_FILE);
        end else begin
            // Default test program for simulation
            rom_memory[0] = 16'h1100;   // ADDI R1, R0, 0    ; Initialize R1
            rom_memory[1] = 16'h1201;   // ADDI R2, R0, 1    ; Initialize R2  
            rom_memory[2] = 16'h0112;   // ADD R1, R1, R2    ; R1 = R1 + R2
            rom_memory[3] = 16'h91FD;   // BNE R1, -3        ; Loop back
            rom_memory[4] = 16'hE000;   // HLT               ; Halt
            $display("MAKu ROM: Loaded default test program");
        end
        
        rom_initialized = 1'b1;
    end
    
    //--------------------------------------------------------------------------
    // RT-Core Access (Port A) - Optimized for deterministic timing
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rt_core_data <= 16'h0000;
            rt_core_valid_reg <= 1'b0;
            rt_access_counter <= 32'h0;
        end else begin
            rt_core_valid_reg <= rt_core_en;
            
            if (rt_core_en) begin
                // Bounds checking for safety
                if (rt_core_addr < ROM_SIZE) begin
                    rt_core_data <= rom_memory[rt_core_addr];
                    rt_access_counter <= rt_access_counter + 1;
                end else begin
                    rt_core_data <= 16'hF000;  // NOP for out-of-bounds
                    $warning("MAKu ROM: RT-Core address out of bounds: 0x%04X", rt_core_addr);
                end
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // GP-Core Access (Port B) - High performance access
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gp_core_data <= 16'h0000;
            gp_core_valid_reg <= 1'b0;
            gp_access_counter <= 32'h0;
        end else begin
            gp_core_valid_reg <= gp_core_en;
            
            if (gp_core_en) begin
                // Bounds checking for safety
                if (gp_core_addr < ROM_SIZE) begin
                    gp_core_data <= rom_memory[gp_core_addr];
                    gp_access_counter <= gp_access_counter + 1;
                end else begin
                    gp_core_data <= 16'hF000;  // NOP for out-of-bounds
                    $warning("MAKu ROM: GP-Core address out of bounds: 0x%04X", gp_core_addr);
                end
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    assign rt_core_valid = rt_core_valid_reg;
    assign gp_core_valid = gp_core_valid_reg;
    assign rom_ready = rom_initialized;
    assign access_count_rt = rt_access_counter;
    assign access_count_gp = gp_access_counter;
    
    //--------------------------------------------------------------------------
    // Simulation-Only Debug
    //--------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk) begin
        if (rt_core_en && rt_core_addr < ROM_SIZE) begin
            $display("MAKu ROM RT: Addr=0x%04X Data=0x%04X", rt_core_addr, rom_memory[rt_core_addr]);
        end
        if (gp_core_en && gp_core_addr < ROM_SIZE) begin
            $display("MAKu ROM GP: Addr=0x%04X Data=0x%04X", gp_core_addr, rom_memory[gp_core_addr]);
        end
    end
    
    // Resource utilization reporting
    initial begin
        $display("MAKu ROM Controller Configuration:");
        $display("  ROM Size: %0d KB (%0d instructions)", (ROM_SIZE * 2) / 1024, ROM_SIZE);
        $display("  Address Width: %0d bits", ADDR_WIDTH);
        $display("  Data Width: %0d bits", DATA_WIDTH);
        $display("  Expected Block RAMs: %0d", (ROM_SIZE * DATA_WIDTH) / 36864);
    end
    // synthesis translate_on

endmodule
