`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: rt_icache_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: RT-Core Instruction Cache Controller (2KB)
//              Direct-mapped cache for deterministic timing
//              No D-Cache for predictable memory access patterns
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - Initial implementation
// Additional Comments:
// - 2KB cache size, 16-byte lines
// - Direct-mapped for deterministic timing
// - Optimized for real-time applications
// 
//////////////////////////////////////////////////////////////////////////////////

module rt_icache_controller (
    // Clock and Reset
    input  logic        clk_rt_50mhz,
    input  logic        rst_n,
    
    // RT-Core Interface (50MHz domain)
    input  logic        cpu_req,
    input  logic [15:0] cpu_addr,
    output logic [15:0] cpu_data,
    output logic        cpu_ready,
    output logic        cpu_hit,
    
    // ROM Controller Interface
    output logic        rom_req,
    output logic [15:0] rom_addr,
    input  logic [15:0] rom_data,
    input  logic        rom_ready,
    
    // Control Interface
    input  logic        cache_enable,
    input  logic        cache_flush,
    output logic        cache_ready,
    
    // Performance Monitoring
    output logic [31:0] hit_count,
    output logic [31:0] miss_count,
    output logic [31:0] total_accesses,
    output logic [7:0]  hit_rate_percent
);

    //--------------------------------------------------------------------------
    // Cache Configuration (2KB, Direct-Mapped)
    //--------------------------------------------------------------------------
    localparam CACHE_SIZE_BYTES = 2048;        // 2KB cache
    localparam LINE_SIZE_BYTES = 16;           // 16-byte cache lines
    localparam WORDS_PER_LINE = 8;             // 8 x 16-bit words per line
    localparam CACHE_LINES = 128;              // 2KB / 16 bytes = 128 lines
    localparam INDEX_BITS = 7;                 // log2(128) = 7 bits
    localparam OFFSET_BITS = 3;                // log2(8) = 3 bits for word offset
    localparam TAG_BITS = 6;                   // 16 - 7 - 3 = 6 tag bits
    
    //--------------------------------------------------------------------------
    // Cache Memory Arrays
    //--------------------------------------------------------------------------
    logic [15:0] cache_data [0:CACHE_LINES-1][0:WORDS_PER_LINE-1];
    logic [TAG_BITS-1:0] cache_tags [0:CACHE_LINES-1];
    logic cache_valid [0:CACHE_LINES-1];
    
    //--------------------------------------------------------------------------
    // Address Breakdown
    //--------------------------------------------------------------------------
    logic [TAG_BITS-1:0]   addr_tag;
    logic [INDEX_BITS-1:0] addr_index;
    logic [OFFSET_BITS-1:0] addr_offset;
    
    assign addr_tag    = cpu_addr[15:10];
    assign addr_index  = cpu_addr[9:3];
    assign addr_offset = cpu_addr[2:0];
    
    //--------------------------------------------------------------------------
    // Cache State Machine - More robust with error handling
    //--------------------------------------------------------------------------
    typedef enum logic [3:0] {
        CACHE_IDLE,
        CACHE_CHECK,
        CACHE_MISS,
        CACHE_FILL,
        CACHE_READY_STATE,
        CACHE_FLUSH_STATE,
        CACHE_ERROR_STATE,
        CACHE_WAIT_ROM
    } cache_state_t;
    
    cache_state_t current_state, next_state;
    
    //--------------------------------------------------------------------------
    // Internal Signals - Enhanced for robustness
    //--------------------------------------------------------------------------
    logic cache_hit;
    logic cache_miss;
    logic [2:0] fill_counter;
    logic [15:0] fill_base_addr;
    logic [31:0] hit_count_reg;
    logic [31:0] miss_count_reg;
    logic [31:0] total_accesses_reg;
    logic [7:0] rom_timeout_counter;
    logic rom_timeout;
    logic fill_complete;
    logic flush_in_progress;
    
    //--------------------------------------------------------------------------
    // Enhanced Cache Hit Detection with edge case handling
    //--------------------------------------------------------------------------
    always_comb begin
        cache_hit = cache_valid[addr_index] && 
                   (cache_tags[addr_index] == addr_tag) && 
                   cache_enable && !flush_in_progress;
        cache_miss = cpu_req && !cache_hit && cache_enable && !flush_in_progress;
        fill_complete = (fill_counter == 3'd7) && rom_ready;
        rom_timeout = (rom_timeout_counter > 8'd100); // Timeout after 100 cycles
    end
    
    //--------------------------------------------------------------------------
    // Robust State Machine with timeout and error handling
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= CACHE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        next_state = current_state;
        case (current_state)
            CACHE_IDLE: begin
                if (cache_flush) begin
                    next_state = CACHE_FLUSH_STATE;
                end else if (cpu_req && cache_enable) begin
                    next_state = CACHE_CHECK;
                end
            end
            
            CACHE_CHECK: begin
                if (cache_hit) begin
                    next_state = CACHE_READY_STATE;
                end else if (cache_miss) begin
                    next_state = CACHE_MISS;
                end else begin
                    next_state = CACHE_IDLE;
                end
            end
            
            CACHE_MISS: begin
                next_state = CACHE_FILL;
            end
            
            CACHE_FILL: begin
                if (rom_timeout) begin
                    next_state = CACHE_ERROR_STATE;
                end else if (fill_complete) begin
                    next_state = CACHE_READY_STATE;
                end else if (!rom_req) begin
                    next_state = CACHE_WAIT_ROM;
                end
            end
            
            CACHE_WAIT_ROM: begin
                if (rom_timeout) begin
                    next_state = CACHE_ERROR_STATE;
                end else if (rom_ready) begin
                    next_state = CACHE_FILL;
                end
            end
            
            CACHE_READY_STATE: begin
                if (cache_flush) begin
                    next_state = CACHE_FLUSH_STATE;
                end else if (!cpu_req) begin
                    next_state = CACHE_IDLE;
                end
            end
            
            CACHE_FLUSH_STATE: begin
                next_state = CACHE_IDLE;
            end
            
            CACHE_ERROR_STATE: begin
                // Stay in error state until reset or flush
                if (cache_flush) begin
                    next_state = CACHE_FLUSH_STATE;
                end
            end
        endcase
    end
    
    //--------------------------------------------------------------------------
    // Enhanced Cache Fill Logic with timeout and error handling
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            fill_counter <= 3'h0;
            fill_base_addr <= 16'h0;
            rom_timeout_counter <= 8'h0;
            flush_in_progress <= 1'b0;
        end else begin
            case (current_state)
                CACHE_MISS: begin
                    fill_counter <= 3'h0;
                    fill_base_addr <= {cpu_addr[15:3], 3'h0}; // Align to cache line
                    rom_timeout_counter <= 8'h0;
                end
                
                CACHE_FILL, CACHE_WAIT_ROM: begin
                    // Increment timeout counter
                    if (rom_timeout_counter < 8'd255) begin
                        rom_timeout_counter <= rom_timeout_counter + 1;
                    end
                    
                    if (rom_ready && !rom_timeout) begin
                        cache_data[addr_index][fill_counter] <= rom_data;
                        fill_counter <= fill_counter + 1;
                        rom_timeout_counter <= 8'h0; // Reset timeout on progress
                        
                        // Update cache metadata on last word
                        if (fill_counter == 3'd7) begin
                            cache_tags[addr_index] <= addr_tag;
                            cache_valid[addr_index] <= 1'b1;
                        end
                    end
                end
                
                CACHE_FLUSH_STATE: begin
                    flush_in_progress <= 1'b1;
                    // Invalidate all cache lines robustly
                    for (int i = 0; i < CACHE_LINES; i++) begin
                        cache_valid[i] <= 1'b0;
                        cache_tags[i] <= {TAG_BITS{1'b0}};
                    end
                end
                
                CACHE_ERROR_STATE: begin
                    // Mark current line as invalid on timeout
                    cache_valid[addr_index] <= 1'b0;
                    rom_timeout_counter <= 8'h0;
                end
                
                default: begin
                    flush_in_progress <= 1'b0;
                    rom_timeout_counter <= 8'h0;
                end
            endcase
        end
    end
    
    //--------------------------------------------------------------------------
    // ROM Interface  
    //--------------------------------------------------------------------------
    always_comb begin
        rom_req = (current_state == CACHE_FILL);
        rom_addr = fill_base_addr + {13'h0, fill_counter};
    end
    
    //--------------------------------------------------------------------------
    // CPU Interface
    //--------------------------------------------------------------------------
    always_comb begin
        cpu_ready = (current_state == CACHE_READY_STATE);
        cpu_hit = cache_hit && (current_state == CACHE_READY_STATE);
        cache_ready = (current_state == CACHE_IDLE);
        
        if (cache_hit && (current_state == CACHE_READY_STATE)) begin
            cpu_data = cache_data[addr_index][addr_offset];
        end else begin
            cpu_data = 16'h0000; // NOP during miss
        end
    end
    
    //--------------------------------------------------------------------------
    // Performance Counters
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            hit_count_reg <= 32'h0;
            miss_count_reg <= 32'h0;
            total_accesses_reg <= 32'h0;
        end else begin
            if (current_state == CACHE_CHECK) begin
                total_accesses_reg <= total_accesses_reg + 1;
                if (cache_hit) begin
                    hit_count_reg <= hit_count_reg + 1;
                end else if (cache_miss) begin
                    miss_count_reg <= miss_count_reg + 1;
                end
            end
        end
    end
    
    // Calculate hit rate percentage
    always_comb begin
        if (total_accesses_reg == 0) begin
            hit_rate_percent = 8'd0;
        end else begin
            hit_rate_percent = (hit_count_reg * 100) / total_accesses_reg;
        end
    end
    
    assign hit_count = hit_count_reg;
    assign miss_count = miss_count_reg;
    assign total_accesses = total_accesses_reg;
    
    //--------------------------------------------------------------------------
    // Cache Initialization
    //--------------------------------------------------------------------------
    initial begin
        for (int i = 0; i < CACHE_LINES; i++) begin
            cache_valid[i] = 1'b0;
            cache_tags[i] = {TAG_BITS{1'b0}};
            for (int j = 0; j < WORDS_PER_LINE; j++) begin
                cache_data[i][j] = 16'h0000;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Simulation Debug
    //--------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk_rt_50mhz) begin
        if (current_state == CACHE_CHECK && cache_hit) begin
            $display("RT I-Cache HIT: Addr=0x%04X, Data=0x%04X, Line=%0d", 
                    cpu_addr, cpu_data, addr_index);
        end else if (current_state == CACHE_MISS) begin
            $display("RT I-Cache MISS: Addr=0x%04X, Tag=%0d, Index=%0d", 
                    cpu_addr, addr_tag, addr_index);
        end
    end
    
    initial begin
        $display("RT-Core I-Cache Configuration:");
        $display("  Cache Size: 2KB (%0d lines x %0d words)", CACHE_LINES, WORDS_PER_LINE);
        $display("  Line Size: %0d bytes", LINE_SIZE_BYTES);
        $display("  Tag bits: %0d, Index bits: %0d, Offset bits: %0d", 
                TAG_BITS, INDEX_BITS, OFFSET_BITS);
    end
    // synthesis translate_on

endmodule
