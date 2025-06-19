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
// Description: RT-Core Instruction Cache Controller (2KB) - COMPLETELY REWRITTEN
//              Simple, functional direct-mapped cache with proper state management
// 
// Dependencies: None
// 
// Revision:
// Revision 0.03 - Complete rewrite for functionality
// Additional Comments:
// - Simplified state machine
// - Fixed cache hit detection
// - Proper fill counter management
// - Working performance counters
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
    localparam CACHE_LINES = 128;              // 128 cache lines
    localparam WORDS_PER_LINE = 8;             // 8 words per line
    localparam TAG_BITS = 6;                   // 6 tag bits
    localparam INDEX_BITS = 7;                 // 7 index bits
    localparam OFFSET_BITS = 3;                // 3 offset bits
    
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
    
    assign addr_tag    = cpu_addr[15:10];      // Bits [15:10]
    assign addr_index  = cpu_addr[9:3];        // Bits [9:3] 
    assign addr_offset = cpu_addr[2:0];        // Bits [2:0]
    
    //--------------------------------------------------------------------------
    // Simple State Machine
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        CHECK   = 3'b001,
        MISS    = 3'b010,
        FILL    = 3'b011,
        READY   = 3'b100,
        FLUSH   = 3'b101
    } state_t;
    
    state_t state;
    
    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    logic is_hit;
    logic is_miss;
    logic [2:0] fill_word_count;
    logic [15:0] fill_addr_base;
    logic [31:0] hit_count_reg;
    logic [31:0] miss_count_reg;
    logic [31:0] total_count_reg;
    logic [6:0] flush_line_count;
    logic access_was_hit;  // Track if current access was originally a hit
    
    //--------------------------------------------------------------------------
    // Cache Hit/Miss Detection
    //--------------------------------------------------------------------------
    always_comb begin
        is_hit = cache_valid[addr_index] && 
                 (cache_tags[addr_index] == addr_tag) && 
                 cache_enable;
        is_miss = cpu_req && !is_hit && cache_enable;
    end
    
    //--------------------------------------------------------------------------
    // Main State Machine
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fill_word_count <= 3'h0;
            fill_addr_base <= 16'h0;
            flush_line_count <= 7'h0;
            access_was_hit <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    access_was_hit <= 1'b0;
                    if (cache_flush) begin
                        state <= FLUSH;
                        flush_line_count <= 7'h0;
                    end else if (cpu_req && cache_enable) begin
                        state <= CHECK;
                    end
                end
                
                CHECK: begin
                    access_was_hit <= is_hit;  // Record if this access was a hit
                    if (is_hit) begin
                        state <= READY;
                    end else if (is_miss) begin
                        state <= MISS;
                        fill_word_count <= 3'h0;
                        fill_addr_base <= {cpu_addr[15:3], 3'b000}; // Line-aligned
                    end else begin
                        state <= IDLE;
                    end
                end
                
                MISS: begin
                    state <= FILL;
                end
                
                FILL: begin
                    if (rom_ready) begin
                        cache_data[addr_index][fill_word_count] <= rom_data;
                        if (fill_word_count == 3'd7) begin
                            // Line fill complete
                            cache_valid[addr_index] <= 1'b1;
                            cache_tags[addr_index] <= addr_tag;
                            state <= READY;
                        end else begin
                            fill_word_count <= fill_word_count + 1;
                        end
                    end
                    // Stay in FILL until ROM responds
                end
                
                READY: begin
                    if (!cpu_req) begin
                        state <= IDLE;
                    end
                end
                
                FLUSH: begin
                    cache_valid[flush_line_count] <= 1'b0;
                    if (flush_line_count == 7'd127) begin
                        state <= IDLE;
                    end else begin
                        flush_line_count <= flush_line_count + 1;
                    end
                end
            endcase
        end
    end
    
    //--------------------------------------------------------------------------
    // ROM Interface
    //--------------------------------------------------------------------------
    assign rom_req = (state == FILL);
    assign rom_addr = fill_addr_base + {13'h0, fill_word_count};
    
    //--------------------------------------------------------------------------
    // CPU Interface
    //--------------------------------------------------------------------------
    assign cpu_ready = (state == READY);
    assign cpu_hit = access_was_hit && (state == READY);  // Use recorded hit status
    assign cache_ready = (state == IDLE);
    assign cpu_data = (state == READY) ? 
                      cache_data[addr_index][addr_offset] : 16'h0000;
    
    //--------------------------------------------------------------------------
    // Performance Counters
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            hit_count_reg <= 32'h0;
            miss_count_reg <= 32'h0;
            total_count_reg <= 32'h0;
        end else begin
            if (state == CHECK && cpu_req) begin
                total_count_reg <= total_count_reg + 1;
                if (is_hit) begin
                    hit_count_reg <= hit_count_reg + 1;
                end else begin
                    miss_count_reg <= miss_count_reg + 1;
                end
            end
        end
    end
    
    assign hit_count = hit_count_reg;
    assign miss_count = miss_count_reg;
    assign total_accesses = total_count_reg;
    assign hit_rate_percent = (total_count_reg > 0) ? 
                             (hit_count_reg * 100 / total_count_reg) : 8'h0;
    
    //--------------------------------------------------------------------------
    // Initialize Cache
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
    // Debug Output
    //--------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk_rt_50mhz) begin
        if (state == CHECK && is_hit) begin
            $display("RT I-Cache HIT: Addr=0x%04X, Tag=%0d, Index=%0d, Data=0x%04X", 
                     cpu_addr, addr_tag, addr_index, cache_data[addr_index][addr_offset]);
        end
        if (state == CHECK && is_miss) begin
            $display("RT I-Cache MISS: Addr=0x%04X, Tag=%0d, Index=%0d", 
                     cpu_addr, addr_tag, addr_index);
        end
        if (state == FILL && rom_ready) begin
            $display("RT I-Cache FILL: Index=%0d, Word=%0d, Data=0x%04X", 
                     addr_index, fill_word_count, rom_data);
        end
    end
    
    initial begin
        $display("RT I-Cache Controller Configuration:");
        $display("  Cache Size: 2KB (%0d lines x %0d words)", CACHE_LINES, WORDS_PER_LINE);
        $display("  Tag bits: %0d, Index bits: %0d, Offset bits: %0d", 
                 TAG_BITS, INDEX_BITS, OFFSET_BITS);
    end
    // synthesis translate_on

endmodule
