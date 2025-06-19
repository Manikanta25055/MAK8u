`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: data_ram_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: 64KB Partitioned Data RAM Controller for MAKu Dual-Core MCU
//              32KB partition for RT-Core (0x20000-0x27FFF)
//              32KB partition for GP-Core (0x28000-0x2FFFF)
//              True dual-port design with bounds checking
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - RT-Core: 50MHz domain, GP-Core: 100MHz domain
// - Hardware bounds checking and memory protection
// - 1-cycle read/write latency for predictable timing
// - Block RAM inference for efficient implementation
// 
//////////////////////////////////////////////////////////////////////////////////

module data_ram_controller #(
    parameter ADDR_WIDTH = 32,              // Full 32-bit addressing
    parameter DATA_WIDTH = 32,              // 32-bit data words
    parameter RT_RAM_SIZE = 32768,          // 32KB for RT-Core (8K words)
    parameter GP_RAM_SIZE = 32768,          // 32KB for GP-Core (8K words)
    parameter RT_BASE_ADDR = 32'h20000,     // RT-Core base address
    parameter GP_BASE_ADDR = 32'h28000      // GP-Core base address
)(
    // Clock and Reset
    input  logic                    clk_rt_50mhz,
    input  logic                    clk_gp_100mhz,
    input  logic                    rst_n,
    
    // RT-Core Interface (50MHz domain)
    input  logic                    rt_mem_en,
    input  logic                    rt_mem_we,
    input  logic [ADDR_WIDTH-1:0]  rt_mem_addr,
    input  logic [DATA_WIDTH-1:0]  rt_mem_wdata,
    output logic [DATA_WIDTH-1:0]  rt_mem_rdata,
    output logic                    rt_mem_ready,
    output logic                    rt_mem_error,      // Bounds check error
    
    // GP-Core Interface (100MHz domain)
    input  logic                    gp_mem_en,
    input  logic                    gp_mem_we,
    input  logic [ADDR_WIDTH-1:0]  gp_mem_addr,
    input  logic [DATA_WIDTH-1:0]  gp_mem_wdata,
    output logic [DATA_WIDTH-1:0]  gp_mem_rdata,
    output logic                    gp_mem_ready,
    output logic                    gp_mem_error,      // Bounds check error
    
    // System Status
    output logic                    ram_ready,
    output logic [31:0]             rt_access_count,
    output logic [31:0]             gp_access_count,
    output logic                    address_collision,
    
    // Debug Interface
    output logic [15:0]             rt_local_addr,     // Local address for debug
    output logic [15:0]             gp_local_addr      // Local address for debug
);

    //--------------------------------------------------------------------------
    // Address Range Constants
    //--------------------------------------------------------------------------
    localparam RT_END_ADDR = RT_BASE_ADDR + RT_RAM_SIZE - 1;  // 0x27FFF
    localparam GP_END_ADDR = GP_BASE_ADDR + GP_RAM_SIZE - 1;  // 0x2FFFF
    localparam RT_WORD_COUNT = RT_RAM_SIZE / 4;               // 8192 words
    localparam GP_WORD_COUNT = GP_RAM_SIZE / 4;               // 8192 words
    
    //--------------------------------------------------------------------------
    // Memory Arrays - Block RAM Inference
    //--------------------------------------------------------------------------
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] rt_ram [0:RT_WORD_COUNT-1];
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] gp_ram [0:GP_WORD_COUNT-1];
    
    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    logic rt_addr_valid;
    logic gp_addr_valid;
    logic [12:0] rt_word_addr;  // Word address within RT partition (13 bits for 8K words)
    logic [12:0] gp_word_addr;  // Word address within GP partition (13 bits for 8K words)
    logic [31:0] rt_access_counter;
    logic [31:0] gp_access_counter;
    logic rt_mem_ready_reg;
    logic gp_mem_ready_reg;
    logic collision_detected;
    
    //--------------------------------------------------------------------------
    // Address Bounds Checking and Word Address Calculation
    //--------------------------------------------------------------------------
    always_comb begin
        // RT-Core address validation and word address calculation
        if ((rt_mem_addr >= RT_BASE_ADDR) && (rt_mem_addr <= RT_END_ADDR) && 
            (rt_mem_addr[1:0] == 2'b00)) begin
            rt_addr_valid = 1'b1;
            rt_word_addr = (rt_mem_addr - RT_BASE_ADDR) >> 2;  // Safe calculation
        end else begin
            rt_addr_valid = 1'b0;
            rt_word_addr = 13'h0;  // Default to safe value
        end
        
        // GP-Core address validation and word address calculation
        if ((gp_mem_addr >= GP_BASE_ADDR) && (gp_mem_addr <= GP_END_ADDR) && 
            (gp_mem_addr[1:0] == 2'b00)) begin
            gp_addr_valid = 1'b1;
            gp_word_addr = (gp_mem_addr - GP_BASE_ADDR) >> 2;  // Safe calculation
        end else begin
            gp_addr_valid = 1'b0;
            gp_word_addr = 13'h0;  // Default to safe value
        end
        
        // Collision detection - both cores accessing at same time
        collision_detected = rt_mem_en && gp_mem_en;
    end
    
    // Debug address outputs
    assign rt_local_addr = {3'b000, rt_word_addr};
    assign gp_local_addr = {3'b000, gp_word_addr};
    
    //--------------------------------------------------------------------------
    // RT-Core Memory Interface (50MHz domain)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            rt_mem_rdata <= 32'h0;
            rt_mem_ready_reg <= 1'b0;
            rt_mem_error <= 1'b0;
            rt_access_counter <= 32'h0;
        end else begin
            rt_mem_ready_reg <= rt_mem_en;
            rt_mem_error <= 1'b0;
            
            if (rt_mem_en) begin
                rt_access_counter <= rt_access_counter + 1;
                
                if (rt_addr_valid) begin
                    if (rt_mem_we) begin
                        // Write operation - only if address is valid
                        rt_ram[rt_word_addr] <= rt_mem_wdata;
                        rt_mem_rdata <= rt_mem_wdata; // Write-through for consistency
                    end else begin
                        // Read operation - only if address is valid
                        rt_mem_rdata <= rt_ram[rt_word_addr];
                    end
                end else begin
                    // Address out of bounds - set error and return error pattern
                    rt_mem_error <= 1'b1;
                    rt_mem_rdata <= 32'hDEADBEEF; // Error pattern
                end
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // GP-Core Memory Interface (100MHz domain)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            gp_mem_rdata <= 32'h0;
            gp_mem_ready_reg <= 1'b0;
            gp_mem_error <= 1'b0;
            gp_access_counter <= 32'h0;
        end else begin
            gp_mem_ready_reg <= gp_mem_en;
            gp_mem_error <= 1'b0;
            
            if (gp_mem_en) begin
                gp_access_counter <= gp_access_counter + 1;
                
                if (gp_addr_valid) begin
                    if (gp_mem_we) begin
                        // Write operation - only if address is valid
                        gp_ram[gp_word_addr] <= gp_mem_wdata;
                        gp_mem_rdata <= gp_mem_wdata; // Write-through for consistency
                    end else begin
                        // Read operation - only if address is valid
                        gp_mem_rdata <= gp_ram[gp_word_addr];
                    end
                end else begin
                    // Address out of bounds - set error and return error pattern
                    gp_mem_error <= 1'b1;
                    gp_mem_rdata <= 32'hDEADBEEF; // Error pattern
                end
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    assign rt_mem_ready = rt_mem_ready_reg;
    assign gp_mem_ready = gp_mem_ready_reg;
    assign ram_ready = 1'b1; // Always ready for access
    assign rt_access_count = rt_access_counter;
    assign gp_access_count = gp_access_counter;
    assign address_collision = collision_detected;
    
    //--------------------------------------------------------------------------
    // Memory Initialization
    //--------------------------------------------------------------------------
    initial begin
        // Initialize RT-Core RAM
        for (int i = 0; i < RT_WORD_COUNT; i++) begin
            rt_ram[i] = 32'h0;
        end
        
        // Initialize GP-Core RAM  
        for (int i = 0; i < GP_WORD_COUNT; i++) begin
            gp_ram[i] = 32'h0;
        end
        
        // Optional: Initialize with test patterns
        // RT-Core test pattern
        rt_ram[0] = 32'hAA55AA55;  // Test pattern at RT base
        rt_ram[1] = 32'h12345678;
        rt_ram[2] = 32'hABCDEF00;
        
        // GP-Core test pattern
        gp_ram[0] = 32'h55AA55AA;  // Test pattern at GP base
        gp_ram[1] = 32'h87654321;
        gp_ram[2] = 32'h00FEDCBA;
    end
    
    //--------------------------------------------------------------------------
    // Simulation Debug and Monitoring
    //--------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk_rt_50mhz) begin
        if (rt_mem_en) begin
            if (rt_addr_valid) begin
                if (rt_mem_we) begin
                    $display("RT RAM WRITE: Addr=0x%08X, Data=0x%08X, LocalAddr=0x%04X", 
                             rt_mem_addr, rt_mem_wdata, rt_word_addr);
                end else begin
                    $display("RT RAM READ: Addr=0x%08X, Data=0x%08X, LocalAddr=0x%04X", 
                             rt_mem_addr, rt_ram[rt_word_addr], rt_word_addr);
                end
            end else begin
                $error("RT RAM: Address out of bounds - 0x%08X", rt_mem_addr);
            end
        end
    end
    
    always @(posedge clk_gp_100mhz) begin
        if (gp_mem_en) begin
            if (gp_addr_valid) begin
                if (gp_mem_we) begin
                    $display("GP RAM WRITE: Addr=0x%08X, Data=0x%08X, LocalAddr=0x%04X", 
                             gp_mem_addr, gp_mem_wdata, gp_word_addr);
                end else begin
                    $display("GP RAM READ: Addr=0x%08X, Data=0x%08X, LocalAddr=0x%04X", 
                             gp_mem_addr, gp_ram[gp_word_addr], gp_word_addr);
                end
            end else begin
                $error("GP RAM: Address out of bounds - 0x%08X", gp_mem_addr);
            end
        end
    end
    
    always @(posedge clk_rt_50mhz or posedge clk_gp_100mhz) begin
        if (collision_detected) begin
            $warning("DATA RAM: Address collision detected - RT and GP cores accessing simultaneously");
        end
    end
    
    initial begin
        $display("Data RAM Controller Configuration:");
        $display("  Total Size: 64KB (32KB RT + 32KB GP)");
        $display("  RT-Core Partition: 0x%08X - 0x%08X (%0d words)", 
                 RT_BASE_ADDR, RT_END_ADDR, RT_RAM_SIZE/4);
        $display("  GP-Core Partition: 0x%08X - 0x%08X (%0d words)", 
                 GP_BASE_ADDR, GP_END_ADDR, GP_RAM_SIZE/4);
        $display("  Data Width: %0d bits", DATA_WIDTH);
    end
    // synthesis translate_on

endmodule
