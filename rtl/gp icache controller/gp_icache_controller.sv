`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: gp_icache_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: GP-Core Instruction Cache Controller (4KB)
//              High-performance cache with dual-issue support
//              Optimized for 100MHz GP-Core operation
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - GP-Core: 100MHz domain, 7-stage pipeline
// - 4KB direct-mapped cache (256 lines x 8 words)
// - Dual instruction fetch capability
// - Enhanced performance counters
// - Cache coherency support
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_icache_controller #(
    parameter ADDR_WIDTH = 16,                  // 16-bit instruction addresses
    parameter DATA_WIDTH = 16,                  // 16-bit instruction words
    parameter CACHE_SIZE = 4096,                // 4KB cache
    parameter WORDS_PER_LINE = 8,               // 8 words per cache line
    parameter CACHE_LINES = 256,                // 256 cache lines
    parameter TAG_BITS = 5,                     // 5 tag bits (16-8-3=5)
    parameter INDEX_BITS = 8,                   // 8 index bits
    parameter OFFSET_BITS = 3                   // 3 offset bits
)(
    // Clock and Reset
    input  logic                    clk_gp_100mhz,
    input  logic                    rst_n,
    
    // GP-Core Interface (100MHz domain) - Dual Issue Support
    input  logic                    cpu_req,
    input  logic [ADDR_WIDTH-1:0]  cpu_addr,
    output logic [DATA_WIDTH-1:0]  cpu_data,
    output logic                    cpu_ready,
    output logic                    cpu_hit,
    
    // Dual-issue second instruction fetch
    input  logic                    cpu_req_2,
    input  logic [ADDR_WIDTH-1:0]  cpu_addr_2,
    output logic [DATA_WIDTH-1:0]  cpu_data_2,
    output logic                    cpu_ready_2,
    output logic                    cpu_hit_2,
    
    // ROM Controller Interface
    output logic                    rom_req,
    output logic [ADDR_WIDTH-1:0]  rom_addr,
    input  logic [DATA_WIDTH-1:0]  rom_data,
    input  logic                    rom_ready,
    
    // Control Interface
    input  logic                    cache_enable,
    input  logic                    cache_flush,
    input  logic                    cache_invalidate,    // Cache coherency
    input  logic [ADDR_WIDTH-1:0]  invalidate_addr,
    output logic                    cache_ready,
    
    // Performance Monitoring
    output logic [31:0]             hit_count,
    output logic [31:0]             miss_count,
    output logic [31:0]             total_accesses,
    output logic [31:0]             dual_issue_count,
    output logic [7:0]              hit_rate_percent,
    output logic [7:0]              cache_utilization,
    
    // Debug Interface
    output logic [INDEX_BITS-1:0]  debug_index,
    output logic [TAG_BITS-1:0]    debug_tag,
    output logic                    debug_valid,
    output logic [2:0]              debug_state
);

    //--------------------------------------------------------------------------
    // Cache Memory Arrays - Block RAM Inference
    //--------------------------------------------------------------------------
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] cache_data [0:CACHE_LINES-1][0:WORDS_PER_LINE-1];
    (* ram_style = "distributed" *) logic [TAG_BITS-1:0] cache_tags [0:CACHE_LINES-1];
    (* ram_style = "distributed" *) logic cache_valid [0:CACHE_LINES-1];
    (* ram_style = "distributed" *) logic cache_dirty [0:CACHE_LINES-1];  // For future coherency
    
    //--------------------------------------------------------------------------
    // Address Breakdown Functions
    //--------------------------------------------------------------------------
    function automatic logic [TAG_BITS-1:0] get_tag(input logic [ADDR_WIDTH-1:0] addr);
        return addr[ADDR_WIDTH-1:ADDR_WIDTH-TAG_BITS];
    endfunction
    
    function automatic logic [INDEX_BITS-1:0] get_index(input logic [ADDR_WIDTH-1:0] addr);
        return addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    endfunction
    
    function automatic logic [OFFSET_BITS-1:0] get_offset(input logic [ADDR_WIDTH-1:0] addr);
        return addr[OFFSET_BITS-1:0];
    endfunction
    
    function automatic logic [ADDR_WIDTH-1:0] get_line_addr(input logic [ADDR_WIDTH-1:0] addr);
        return {addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    endfunction
    
    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    // Address breakdown for primary request
    logic [TAG_BITS-1:0]   addr_tag;
    logic [INDEX_BITS-1:0] addr_index;
    logic [OFFSET_BITS-1:0] addr_offset;
    
    // Address breakdown for secondary request (dual-issue)
    logic [TAG_BITS-1:0]   addr_tag_2;
    logic [INDEX_BITS-1:0] addr_index_2;
    logic [OFFSET_BITS-1:0] addr_offset_2;
    
    // Cache hit/miss detection
    logic is_hit, is_miss;
    logic is_hit_2, is_miss_2;
    logic can_dual_issue;
    
    // State machine
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        CHECK       = 3'b001,
        MISS        = 3'b010,
        FILL        = 3'b011,
        READY       = 3'b100,
        FLUSH       = 3'b101,
        INVALIDATE  = 3'b110
    } state_t;
    
    state_t state;
    
    // Fill control
    logic [2:0] fill_word_count;
    logic [ADDR_WIDTH-1:0] fill_addr_base;
    logic [INDEX_BITS-1:0] fill_index;
    logic [TAG_BITS-1:0] fill_tag;
    
    // Flush control
    logic [INDEX_BITS-1:0] flush_line_count;
    
    // Performance counters
    logic [31:0] hit_count_reg;
    logic [31:0] miss_count_reg;
    logic [31:0] total_count_reg;
    logic [31:0] dual_issue_count_reg;
    logic [31:0] valid_lines_count;
    
    // Pipeline registers
    logic access_was_hit;
    logic access_was_hit_2;
    logic dual_issue_active;
    
    //--------------------------------------------------------------------------
    // Address Breakdown Assignment
    //--------------------------------------------------------------------------
    always_comb begin
        addr_tag = get_tag(cpu_addr);
        addr_index = get_index(cpu_addr);
        addr_offset = get_offset(cpu_addr);
        
        addr_tag_2 = get_tag(cpu_addr_2);
        addr_index_2 = get_index(cpu_addr_2);
        addr_offset_2 = get_offset(cpu_addr_2);
    end
    
    //--------------------------------------------------------------------------
    // Cache Hit/Miss Detection
    //--------------------------------------------------------------------------
    always_comb begin
        // Primary instruction hit detection
        is_hit = cache_valid[addr_index] && 
                 (cache_tags[addr_index] == addr_tag) && 
                 cache_enable;
        is_miss = cpu_req && !is_hit && cache_enable;
        
        // Secondary instruction hit detection (dual-issue)
        is_hit_2 = cache_valid[addr_index_2] && 
                   (cache_tags[addr_index_2] == addr_tag_2) && 
                   cache_enable;
        is_miss_2 = cpu_req_2 && !is_hit_2 && cache_enable;
        
        // Dual-issue feasibility - both must hit same or different cache lines
        can_dual_issue = cpu_req && cpu_req_2 && is_hit && is_hit_2 && cache_enable;
    end
    
    //--------------------------------------------------------------------------
    // Main State Machine
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fill_word_count <= 3'h0;
            fill_addr_base <= {ADDR_WIDTH{1'b0}};
            fill_index <= {INDEX_BITS{1'b0}};
            fill_tag <= {TAG_BITS{1'b0}};
            flush_line_count <= {INDEX_BITS{1'b0}};
            access_was_hit <= 1'b0;
            access_was_hit_2 <= 1'b0;
            dual_issue_active <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    access_was_hit <= 1'b0;
                    access_was_hit_2 <= 1'b0;
                    dual_issue_active <= 1'b0;
                    
                    if (!cache_enable) begin
                        // Cache disabled - stay in IDLE, handle in ROM interface
                        state <= IDLE;
                    end else if (cache_flush) begin
                        state <= FLUSH;
                        flush_line_count <= {INDEX_BITS{1'b0}};
                    end else if (cache_invalidate) begin
                        state <= INVALIDATE;
                    end else if (cpu_req && cache_enable) begin
                        state <= CHECK;
                    end
                end
                
                CHECK: begin
                    if (can_dual_issue) begin
                        // Dual-issue success - both hit
                        access_was_hit <= 1'b1;
                        access_was_hit_2 <= 1'b1;
                        dual_issue_active <= 1'b1;
                        state <= READY;
                    end else if (is_hit && !cpu_req_2) begin
                        // Single instruction hit
                        access_was_hit <= 1'b1;
                        access_was_hit_2 <= 1'b0;
                        dual_issue_active <= 1'b0;
                        state <= READY;
                    end else if (is_hit && cpu_req_2 && is_miss_2) begin
                        // First hits, second misses - serve first as single instruction
                        access_was_hit <= 1'b1;
                        access_was_hit_2 <= 1'b0;
                        dual_issue_active <= 1'b0;
                        state <= READY;
                    end else if (is_miss) begin
                        // Primary instruction miss - handle miss
                        access_was_hit <= 1'b0;
                        access_was_hit_2 <= 1'b0;
                        dual_issue_active <= 1'b0;
                        state <= MISS;
                        fill_word_count <= 3'h0;
                        fill_addr_base <= get_line_addr(cpu_addr);
                        fill_index <= addr_index;
                        fill_tag <= addr_tag;
                    end else begin
                        state <= IDLE;
                    end
                end
                
                MISS: begin
                    state <= FILL;
                end
                
                FILL: begin
                    if (rom_ready) begin
                        cache_data[fill_index][fill_word_count] <= rom_data;
                        if (fill_word_count == 3'd7) begin
                            // Line fill complete
                            cache_valid[fill_index] <= 1'b1;
                            cache_tags[fill_index] <= fill_tag;
                            cache_dirty[fill_index] <= 1'b0;
                            // Don't set access_was_hit here - this was a miss that got filled
                            state <= READY;
                        end else begin
                            fill_word_count <= fill_word_count + 1;
                        end
                    end
                end
                
                READY: begin
                    if (!cpu_req && !cpu_req_2) begin
                        state <= IDLE;
                    end
                end
                
                FLUSH: begin
                    cache_valid[flush_line_count] <= 1'b0;
                    cache_dirty[flush_line_count] <= 1'b0;
                    if (flush_line_count == (CACHE_LINES-1)) begin
                        state <= IDLE;
                    end else begin
                        flush_line_count <= flush_line_count + 1;
                    end
                end
                
                INVALIDATE: begin
                    // Invalidate specific cache line
                    cache_valid[get_index(invalidate_addr)] <= 1'b0;
                    cache_dirty[get_index(invalidate_addr)] <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end
    
    //--------------------------------------------------------------------------
    // ROM Interface
    //--------------------------------------------------------------------------
    assign rom_req = cache_enable ? (state == FILL) : cpu_req;
    assign rom_addr = cache_enable ? 
                      (fill_addr_base + {{(ADDR_WIDTH-3){1'b0}}, fill_word_count}) :
                      cpu_addr;
    
    //--------------------------------------------------------------------------
    // CPU Interface Outputs
    //--------------------------------------------------------------------------
    assign cpu_ready = cache_enable ? (state == READY) : rom_ready;
    assign cpu_hit = cache_enable ? (access_was_hit && (state == READY)) : 1'b0;
    assign cpu_data = cache_enable ? 
                      ((state == READY) ? cache_data[addr_index][addr_offset] : {DATA_WIDTH{1'b0}}) :
                      rom_data;
    
    assign cpu_ready_2 = cache_enable ? ((state == READY) && access_was_hit_2 && dual_issue_active) : 1'b0;
    assign cpu_hit_2 = cache_enable ? (access_was_hit_2 && (state == READY) && dual_issue_active) : 1'b0;
    assign cpu_data_2 = cache_enable ? 
                        ((state == READY && dual_issue_active) ? cache_data[addr_index_2][addr_offset_2] : {DATA_WIDTH{1'b0}}) :
                        {DATA_WIDTH{1'b0}};
    
    assign cache_ready = (state == IDLE);
    
    //--------------------------------------------------------------------------
    // Performance Counters
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            hit_count_reg <= 32'h0;
            miss_count_reg <= 32'h0;
            total_count_reg <= 32'h0;
            dual_issue_count_reg <= 32'h0;
        end else begin
            if (state == CHECK && cpu_req && cache_enable) begin
                total_count_reg <= total_count_reg + 1;
                if (can_dual_issue) begin
                    hit_count_reg <= hit_count_reg + 2;  // Count both instructions
                    dual_issue_count_reg <= dual_issue_count_reg + 1;
                end else if (is_hit) begin
                    hit_count_reg <= hit_count_reg + 1;
                end else if (is_miss) begin
                    miss_count_reg <= miss_count_reg + 1;
                end
            end
        end
    end
    
    // Calculate cache utilization
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            valid_lines_count <= 32'h0;
        end else begin
            // Recalculate every few cycles to avoid timing issues
            if (state == IDLE) begin
                valid_lines_count <= 32'h0;
                for (int i = 0; i < CACHE_LINES; i++) begin
                    if (cache_valid[i]) begin
                        valid_lines_count <= valid_lines_count + 1;
                    end
                end
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    assign hit_count = hit_count_reg;
    assign miss_count = miss_count_reg;
    assign total_accesses = total_count_reg;
    assign dual_issue_count = dual_issue_count_reg;
    assign hit_rate_percent = (total_count_reg > 0) ? 
                              (hit_count_reg * 100 / total_count_reg) : 8'h0;
    assign cache_utilization = (CACHE_LINES > 0) ? 
                               ((valid_lines_count * 100) / CACHE_LINES) : 8'h0;
    
    // Debug outputs
    assign debug_index = addr_index;
    assign debug_tag = addr_tag;
    assign debug_valid = cache_valid[addr_index];
    assign debug_state = state;
    
    //--------------------------------------------------------------------------
    // Memory Initialization
    //--------------------------------------------------------------------------
    initial begin
        for (int i = 0; i < CACHE_LINES; i++) begin
            cache_valid[i] = 1'b0;
            cache_dirty[i] = 1'b0;
            cache_tags[i] = {TAG_BITS{1'b0}};
            for (int j = 0; j < WORDS_PER_LINE; j++) begin
                cache_data[i][j] = {DATA_WIDTH{1'b0}};
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Simulation Debug and Monitoring
    //--------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk_gp_100mhz) begin
        if (state == CHECK && can_dual_issue) begin
            $display("GP I-Cache DUAL HIT: Addr1=0x%04X, Addr2=0x%04X, Data1=0x%04X, Data2=0x%04X", 
                     cpu_addr, cpu_addr_2, 
                     cache_data[addr_index][addr_offset],
                     cache_data[addr_index_2][addr_offset_2]);
        end else if (state == CHECK && is_hit) begin
            $display("GP I-Cache HIT: Addr=0x%04X, Tag=%0d, Index=%0d, Data=0x%04X", 
                     cpu_addr, addr_tag, addr_index, cache_data[addr_index][addr_offset]);
        end else if (state == CHECK && is_miss) begin
            $display("GP I-Cache MISS: Addr=0x%04X, Tag=%0d, Index=%0d", 
                     cpu_addr, addr_tag, addr_index);
        end
        if (state == FILL && rom_ready) begin
            $display("GP I-Cache FILL: Index=%0d, Word=%0d, Data=0x%04X", 
                     fill_index, fill_word_count, rom_data);
        end
    end
    
    initial begin
        $display("GP I-Cache Controller Configuration:");
        $display("  Cache Size: 4KB (%0d lines x %0d words)", CACHE_LINES, WORDS_PER_LINE);
        $display("  Tag bits: %0d, Index bits: %0d, Offset bits: %0d", 
                 TAG_BITS, INDEX_BITS, OFFSET_BITS);
        $display("  Dual-issue capable: YES");
        $display("  Clock frequency: 100MHz");
    end
    // synthesis translate_on

endmodule
