`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: gp_dcache_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: GP-Core Data Cache Controller (2KB)
//              High-performance data cache with write-back capability
//              Supports cache coherency and advanced memory management
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - GP-Core: 100MHz domain, 7-stage pipeline
// - 2KB direct-mapped cache (128 lines x 4 words)
// - Write-back and write-through support
// - Cache coherency with invalidation
// - Advanced performance monitoring
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_dcache_controller #(
    parameter ADDR_WIDTH = 32,                  // 32-bit data addresses
    parameter DATA_WIDTH = 32,                  // 32-bit data words
    parameter CACHE_SIZE = 2048,                // 2KB cache
    parameter WORDS_PER_LINE = 4,               // 4 words per cache line
    parameter CACHE_LINES = 128,                // 128 cache lines
    parameter TAG_BITS = 24,                    // 24 tag bits (32-7-2=23, +1 for safety)
    parameter INDEX_BITS = 7,                   // 7 index bits
    parameter OFFSET_BITS = 2                   // 2 offset bits (4 words = 2^2)
)(
    // Clock and Reset
    input  logic                    clk_gp_100mhz,
    input  logic                    rst_n,
    
    // GP-Core Interface (100MHz domain)
    input  logic                    cpu_req,
    input  logic                    cpu_we,         // Write enable
    input  logic [3:0]              cpu_be,         // Byte enable
    input  logic [ADDR_WIDTH-1:0]  cpu_addr,
    input  logic [DATA_WIDTH-1:0]  cpu_wdata,
    output logic [DATA_WIDTH-1:0]  cpu_rdata,
    output logic                    cpu_ready,
    output logic                    cpu_hit,
    
    // Data RAM Interface
    output logic                    ram_req,
    output logic                    ram_we,
    output logic [ADDR_WIDTH-1:0]  ram_addr,
    output logic [DATA_WIDTH-1:0]  ram_wdata,
    input  logic [DATA_WIDTH-1:0]  ram_rdata,
    input  logic                    ram_ready,
    
    // Control Interface
    input  logic                    cache_enable,
    input  logic                    cache_flush,
    input  logic                    cache_invalidate,
    input  logic [ADDR_WIDTH-1:0]  invalidate_addr,
    input  logic                    write_through_mode,  // 0=write-back, 1=write-through
    output logic                    cache_ready,
    
    // Cache Coherency Interface
    input  logic                    coherency_invalidate,
    input  logic [ADDR_WIDTH-1:0]  coherency_addr,
    output logic                    coherency_hit,
    output logic                    writeback_pending,
    
    // Performance Monitoring
    output logic [31:0]             read_hit_count,
    output logic [31:0]             write_hit_count,
    output logic [31:0]             read_miss_count,
    output logic [31:0]             write_miss_count,
    output logic [31:0]             total_accesses,
    output logic [31:0]             writeback_count,
    output logic [7:0]              hit_rate_percent,
    output logic [7:0]              cache_utilization,
    
    // Debug Interface
    output logic [INDEX_BITS-1:0]  debug_index,
    output logic [TAG_BITS-1:0]    debug_tag,
    output logic                    debug_valid,
    output logic                    debug_dirty,
    output logic [2:0]              debug_state
);

    //--------------------------------------------------------------------------
    // Cache Memory Arrays - Block RAM Inference
    //--------------------------------------------------------------------------
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] cache_data [0:CACHE_LINES-1][0:WORDS_PER_LINE-1];
    (* ram_style = "distributed" *) logic [TAG_BITS-1:0] cache_tags [0:CACHE_LINES-1];
    (* ram_style = "distributed" *) logic cache_valid [0:CACHE_LINES-1];
    (* ram_style = "distributed" *) logic cache_dirty [0:CACHE_LINES-1];
    
    //--------------------------------------------------------------------------
    // Address Breakdown Functions
    //--------------------------------------------------------------------------
    function automatic logic [TAG_BITS-1:0] get_tag(input logic [ADDR_WIDTH-1:0] addr);
        return addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
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
    // Address breakdown
    logic [TAG_BITS-1:0]   addr_tag;
    logic [INDEX_BITS-1:0] addr_index;
    logic [OFFSET_BITS-1:0] addr_offset;
    
    // Cache hit/miss detection
    logic is_hit, is_miss;
    logic coherency_match;
    
    // State machine
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        CHECK       = 3'b001,
        MISS        = 3'b010,
        FILL        = 3'b011,
        WRITEBACK   = 3'b100,
        READY       = 3'b101,
        FLUSH       = 3'b110,
        INVALIDATE  = 3'b111
    } state_t;
    
    state_t state;
    
    // Fill/Writeback control
    logic [1:0] fill_word_count;
    logic [1:0] wb_word_count;
    logic [ADDR_WIDTH-1:0] fill_addr_base;
    logic [ADDR_WIDTH-1:0] wb_addr_base;
    logic [INDEX_BITS-1:0] fill_index;
    logic [TAG_BITS-1:0] fill_tag;
    logic [INDEX_BITS-1:0] wb_index;
    logic need_writeback;
    
    // Flush control
    logic [INDEX_BITS-1:0] flush_line_count;
    
    // Performance counters
    logic [31:0] read_hit_count_reg;
    logic [31:0] write_hit_count_reg;
    logic [31:0] read_miss_count_reg;
    logic [31:0] write_miss_count_reg;
    logic [31:0] total_count_reg;
    logic [31:0] writeback_count_reg;
    logic [31:0] valid_lines_count;
    
    // Pipeline registers
    logic access_was_hit;
    logic access_was_write;
    logic [DATA_WIDTH-1:0] write_data_reg;
    logic [3:0] byte_enable_reg;
    
    //--------------------------------------------------------------------------
    // Address Breakdown Assignment
    //--------------------------------------------------------------------------
    always_comb begin
        addr_tag = get_tag(cpu_addr);
        addr_index = get_index(cpu_addr);
        addr_offset = get_offset(cpu_addr);
    end
    
    //--------------------------------------------------------------------------
    // Cache Hit/Miss Detection
    //--------------------------------------------------------------------------
    always_comb begin
        // Cache hit detection
        is_hit = cache_valid[addr_index] && 
                 (cache_tags[addr_index] == addr_tag) && 
                 cache_enable;
        is_miss = cpu_req && !is_hit && cache_enable;
        
        // Coherency hit detection
        coherency_match = cache_valid[get_index(coherency_addr)] && 
                         (cache_tags[get_index(coherency_addr)] == get_tag(coherency_addr));
    end
    
    //--------------------------------------------------------------------------
    // Main State Machine
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fill_word_count <= 2'h0;
            wb_word_count <= 2'h0;
            fill_addr_base <= {ADDR_WIDTH{1'b0}};
            wb_addr_base <= {ADDR_WIDTH{1'b0}};
            fill_index <= {INDEX_BITS{1'b0}};
            fill_tag <= {TAG_BITS{1'b0}};
            wb_index <= {INDEX_BITS{1'b0}};
            flush_line_count <= {INDEX_BITS{1'b0}};
            access_was_hit <= 1'b0;
            access_was_write <= 1'b0;
            write_data_reg <= {DATA_WIDTH{1'b0}};
            byte_enable_reg <= 4'h0;
            need_writeback <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    access_was_hit <= 1'b0;
                    access_was_write <= 1'b0;
                    need_writeback <= 1'b0;
                    
                    if (!cache_enable) begin
                        // Cache disabled - stay in IDLE
                        state <= IDLE;
                    end else if (cache_flush) begin
                        state <= FLUSH;
                        flush_line_count <= {INDEX_BITS{1'b0}};
                    end else if (cache_invalidate) begin
                        state <= INVALIDATE;
                    end else if (coherency_invalidate && coherency_match) begin
                        state <= INVALIDATE;
                    end else if (cpu_req && cache_enable) begin
                        state <= CHECK;
                        access_was_write <= cpu_we;
                        write_data_reg <= cpu_wdata;
                        byte_enable_reg <= cpu_be;
                    end
                end
                
                CHECK: begin
                    if (is_hit) begin
                        // Cache hit
                        access_was_hit <= 1'b1;
                        state <= READY;
                    end else if (is_miss) begin
                        // Cache miss - check if writeback needed
                        access_was_hit <= 1'b0;
                        if (cache_valid[addr_index] && cache_dirty[addr_index] && !write_through_mode) begin
                            // Need writeback first
                            need_writeback <= 1'b1;
                            wb_index <= addr_index;
                            wb_addr_base <= {cache_tags[addr_index], addr_index, {OFFSET_BITS{1'b0}}};
                            wb_word_count <= 2'h0;
                            state <= WRITEBACK;
                        end else begin
                            // Direct to fill
                            state <= MISS;
                        end
                    end else begin
                        state <= IDLE;
                    end
                end
                
                MISS: begin
                    state <= FILL;
                    fill_word_count <= 2'h0;
                    fill_addr_base <= get_line_addr(cpu_addr);
                    fill_index <= addr_index;
                    fill_tag <= addr_tag;
                end
                
                FILL: begin
                    if (ram_ready) begin
                        cache_data[fill_index][fill_word_count] <= ram_rdata;
                        if (fill_word_count == 2'd3) begin
                            // Line fill complete
                            cache_valid[fill_index] <= 1'b1;
                            cache_tags[fill_index] <= fill_tag;
                            cache_dirty[fill_index] <= 1'b0;
                            state <= READY;
                        end else begin
                            fill_word_count <= fill_word_count + 1;
                        end
                    end
                end
                
                WRITEBACK: begin
                    if (ram_ready) begin
                        if (wb_word_count == 2'd3) begin
                            // Writeback complete
                            cache_dirty[wb_index] <= 1'b0;
                            state <= MISS;
                        end else begin
                            wb_word_count <= wb_word_count + 1;
                        end
                    end
                end
                
                READY: begin
                    if (!cpu_req) begin
                        state <= IDLE;
                    end
                end
                
                FLUSH: begin
                    if (cache_valid[flush_line_count] && cache_dirty[flush_line_count] && !write_through_mode) begin
                        // Need to writeback dirty line
                        wb_index <= flush_line_count;
                        wb_addr_base <= {cache_tags[flush_line_count], flush_line_count, {OFFSET_BITS{1'b0}}};
                        wb_word_count <= 2'h0;
                        state <= WRITEBACK;
                    end else begin
                        // Clear the line
                        cache_valid[flush_line_count] <= 1'b0;
                        cache_dirty[flush_line_count] <= 1'b0;
                        if (flush_line_count == (CACHE_LINES-1)) begin
                            state <= IDLE;
                        end else begin
                            flush_line_count <= flush_line_count + 1;
                        end
                    end
                end
                
                INVALIDATE: begin
                    // Invalidate specific cache line
                    if (cache_invalidate) begin
                        cache_valid[get_index(invalidate_addr)] <= 1'b0;
                        cache_dirty[get_index(invalidate_addr)] <= 1'b0;
                    end else if (coherency_invalidate) begin
                        cache_valid[get_index(coherency_addr)] <= 1'b0;
                        cache_dirty[get_index(coherency_addr)] <= 1'b0;
                    end
                    state <= IDLE;
                end
            endcase
        end
    end
    
    //--------------------------------------------------------------------------
    // Cache Data Update Logic
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz) begin
        if (state == READY && access_was_hit && access_was_write) begin
            // Write hit - update cache data
            for (int i = 0; i < 4; i++) begin
                if (byte_enable_reg[i]) begin
                    cache_data[addr_index][addr_offset][i*8 +: 8] <= write_data_reg[i*8 +: 8];
                end
            end
            
            if (write_through_mode) begin
                // Write-through: keep clean
                cache_dirty[addr_index] <= 1'b0;
            end else begin
                // Write-back: mark dirty
                cache_dirty[addr_index] <= 1'b1;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // RAM Interface
    //--------------------------------------------------------------------------
    always_comb begin
        case (state)
            FILL: begin
                ram_req = 1'b1;
                ram_we = 1'b0;
                ram_addr = fill_addr_base + {{(ADDR_WIDTH-2){1'b0}}, fill_word_count};
                ram_wdata = {DATA_WIDTH{1'b0}};
            end
            
            WRITEBACK: begin
                ram_req = 1'b1;
                ram_we = 1'b1;
                ram_addr = wb_addr_base + {{(ADDR_WIDTH-2){1'b0}}, wb_word_count};
                ram_wdata = cache_data[wb_index][wb_word_count];
            end
            
            default: begin
                ram_req = 1'b0;
                ram_we = 1'b0;
                ram_addr = {ADDR_WIDTH{1'b0}};
                ram_wdata = {DATA_WIDTH{1'b0}};
                
                // Write-through mode direct RAM access
                if (cache_enable && write_through_mode && 
                    state == READY && access_was_hit && access_was_write) begin
                    ram_req = 1'b1;
                    ram_we = 1'b1;
                    ram_addr = cpu_addr;
                    ram_wdata = cpu_wdata;
                end else if (!cache_enable && cpu_req) begin
                    // Cache disabled - direct RAM access
                    ram_req = 1'b1;
                    ram_we = cpu_we;
                    ram_addr = cpu_addr;
                    ram_wdata = cpu_wdata;
                end
            end
        endcase
    end
    
    //--------------------------------------------------------------------------
    // CPU Interface Outputs
    //--------------------------------------------------------------------------
    assign cpu_ready = cache_enable ? (state == READY) : ram_ready;
    assign cpu_hit = cache_enable ? (access_was_hit && (state == READY)) : 1'b0;
    assign cpu_rdata = cache_enable ? 
                       ((state == READY && access_was_hit) ? cache_data[addr_index][addr_offset] : {DATA_WIDTH{1'b0}}) :
                       ram_rdata;
    
    assign cache_ready = (state == IDLE);
    assign coherency_hit = coherency_match;
    assign writeback_pending = (state == WRITEBACK) || need_writeback;
    
    //--------------------------------------------------------------------------
    // Performance Counters
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            read_hit_count_reg <= 32'h0;
            write_hit_count_reg <= 32'h0;
            read_miss_count_reg <= 32'h0;
            write_miss_count_reg <= 32'h0;
            total_count_reg <= 32'h0;
            writeback_count_reg <= 32'h0;
        end else begin
            if (state == CHECK && cpu_req && cache_enable) begin
                total_count_reg <= total_count_reg + 1;
                if (is_hit) begin
                    if (cpu_we) begin
                        write_hit_count_reg <= write_hit_count_reg + 1;
                    end else begin
                        read_hit_count_reg <= read_hit_count_reg + 1;
                    end
                end else if (is_miss) begin
                    if (cpu_we) begin
                        write_miss_count_reg <= write_miss_count_reg + 1;
                    end else begin
                        read_miss_count_reg <= read_miss_count_reg + 1;
                    end
                end
            end
            
            if (state == WRITEBACK && ram_ready && wb_word_count == 2'd3) begin
                writeback_count_reg <= writeback_count_reg + 1;
            end
        end
    end
    
    // Calculate cache utilization
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            valid_lines_count <= 32'h0;
        end else begin
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
    assign read_hit_count = read_hit_count_reg;
    assign write_hit_count = write_hit_count_reg;
    assign read_miss_count = read_miss_count_reg;
    assign write_miss_count = write_miss_count_reg;
    assign total_accesses = total_count_reg;
    assign writeback_count = writeback_count_reg;
    assign hit_rate_percent = (total_count_reg > 0) ? 
                              ((read_hit_count_reg + write_hit_count_reg) * 100 / total_count_reg) : 8'h0;
    assign cache_utilization = (CACHE_LINES > 0) ? 
                               ((valid_lines_count * 100) / CACHE_LINES) : 8'h0;
    
    // Debug outputs
    assign debug_index = addr_index;
    assign debug_tag = addr_tag;
    assign debug_valid = cache_valid[addr_index];
    assign debug_dirty = cache_dirty[addr_index];
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
        if (state == CHECK && is_hit) begin
            if (access_was_write) begin
                $display("GP D-Cache WRITE HIT: Addr=0x%08X, Data=0x%08X, Index=%0d", 
                         cpu_addr, cpu_wdata, addr_index);
            end else begin
                $display("GP D-Cache READ HIT: Addr=0x%08X, Data=0x%08X, Index=%0d", 
                         cpu_addr, cache_data[addr_index][addr_offset], addr_index);
            end
        end
        if (state == CHECK && is_miss) begin
            if (access_was_write) begin
                $display("GP D-Cache WRITE MISS: Addr=0x%08X, Data=0x%08X, Index=%0d", 
                         cpu_addr, cpu_wdata, addr_index);
            end else begin
                $display("GP D-Cache READ MISS: Addr=0x%08X, Index=%0d", 
                         cpu_addr, addr_index);
            end
        end
        if (state == FILL && ram_ready) begin
            $display("GP D-Cache FILL: Index=%0d, Word=%0d, Data=0x%08X", 
                     fill_index, fill_word_count, ram_rdata);
        end
        if (state == WRITEBACK && ram_ready) begin
            $display("GP D-Cache WRITEBACK: Index=%0d, Word=%0d, Data=0x%08X", 
                     wb_index, wb_word_count, cache_data[wb_index][wb_word_count]);
        end
    end
    
    initial begin
        $display("GP D-Cache Controller Configuration:");
        $display("  Cache Size: 2KB (%0d lines x %0d words)", CACHE_LINES, WORDS_PER_LINE);
        $display("  Tag bits: %0d, Index bits: %0d, Offset bits: %0d", 
                 TAG_BITS, INDEX_BITS, OFFSET_BITS);
        $display("  Write-back and write-through capable: YES");
        $display("  Cache coherency support: YES");
        $display("  Clock frequency: 100MHz");
    end
    // synthesis translate_on

endmodule
