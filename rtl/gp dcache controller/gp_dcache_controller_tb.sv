`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: gp_dcache_controller_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T (Simulation)
// Tool Versions: Vivado 2024.2
// Description: Comprehensive testbench for GP-Core Data Cache Controller
//              Tests 2KB cache with write-back/write-through modes
//              Validates cache coherency and advanced memory management
// 
// Dependencies: gp_dcache_controller.sv
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - Tests read/write operations with cache coherency
// - Validates write-back and write-through modes
// - Comprehensive performance counter verification
// - Advanced cache management features testing
// - Byte-level write enable testing
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_dcache_controller_tb;

    //--------------------------------------------------------------------------
    // Test Parameters
    //--------------------------------------------------------------------------
    localparam CLK_PERIOD = 10;        // 100MHz GP-Core clock (10ns)
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam CACHE_LINES = 128;
    localparam WORDS_PER_LINE = 4;
    localparam TEST_TIMEOUT = 200000;   // 2ms timeout
    
    //--------------------------------------------------------------------------
    // DUT Signals - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    logic                    clk_gp_100mhz;
    logic                    rst_n;
    
    // CPU Interface
    logic                    cpu_req;
    logic                    cpu_we;
    logic [3:0]              cpu_be;
    logic [ADDR_WIDTH-1:0]   cpu_addr;
    logic [DATA_WIDTH-1:0]   cpu_wdata;
    logic [DATA_WIDTH-1:0]   cpu_rdata;
    logic                    cpu_ready;
    logic                    cpu_hit;
    
    // RAM Interface
    logic                    ram_req;
    logic                    ram_we;
    logic [ADDR_WIDTH-1:0]   ram_addr;
    logic [DATA_WIDTH-1:0]   ram_wdata;
    logic [DATA_WIDTH-1:0]   ram_rdata;
    logic                    ram_ready;
    
    // Control Interface
    logic                    cache_enable;
    logic                    cache_flush;
    logic                    cache_invalidate;
    logic [ADDR_WIDTH-1:0]   invalidate_addr;
    logic                    write_through_mode;
    logic                    cache_ready;
    
    // Cache Coherency Interface
    logic                    coherency_invalidate;
    logic [ADDR_WIDTH-1:0]   coherency_addr;
    logic                    coherency_hit;
    logic                    writeback_pending;
    
    // Performance Monitoring
    logic [31:0]             read_hit_count;
    logic [31:0]             write_hit_count;
    logic [31:0]             read_miss_count;
    logic [31:0]             write_miss_count;
    logic [31:0]             total_accesses;
    logic [31:0]             writeback_count;
    logic [7:0]              hit_rate_percent;
    logic [7:0]              cache_utilization;
    
    // Debug Interface
    logic [6:0]              debug_index;
    logic [23:0]             debug_tag;
    logic                    debug_valid;
    logic                    debug_dirty;
    logic [2:0]              debug_state;
    
    //--------------------------------------------------------------------------
    // Test Control Variables - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    integer test_errors;
    integer test_number;
    integer i, j, k;
    logic [31:0] test_addr;
    logic [31:0] test_wdata;
    logic [31:0] test_rdata;
    logic [3:0] test_be;
    logic test_hit;
    logic test_ready;
    integer timeout_counter;
    integer read_hits_before, write_hits_before;
    integer read_misses_before, write_misses_before;
    integer total_before, wb_before;
    integer read_hits_after, write_hits_after;
    integer read_misses_after, write_misses_after;
    integer total_after, wb_after;
    
    //--------------------------------------------------------------------------
    // RAM Memory Model
    //--------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] ram_memory [0:65535];  // 256KB memory model
    logic [1:0] ram_delay_counter;
    
    // Initialize RAM with test patterns
    initial begin
        for (int m = 0; m < 65536; m++) begin
            ram_memory[m] = m[31:0] ^ 32'h5A5A5A5A;  // XOR pattern for verification
        end
    end
    
    // RAM model with realistic timing (2-3 cycle latency)
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            ram_rdata <= 32'h0000_0000;
            ram_ready <= 1'b0;
            ram_delay_counter <= 2'h0;
        end else begin
            if (ram_req && ram_delay_counter == 2'h0) begin
                ram_delay_counter <= 2'h2;  // 2 cycle delay
                ram_ready <= 1'b0;
            end else if (ram_delay_counter > 2'h0) begin
                ram_delay_counter <= ram_delay_counter - 1;
                if (ram_delay_counter == 2'h1) begin
                    if (ram_we) begin
                        // Write operation
                        ram_memory[ram_addr[17:2]] <= ram_wdata;  // Word-aligned access
                        ram_rdata <= ram_wdata;
                    end else begin
                        // Read operation
                        ram_rdata <= ram_memory[ram_addr[17:2]];
                    end
                    ram_ready <= 1'b1;
                end
            end else begin
                ram_ready <= 1'b0;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial clk_gp_100mhz = 0;
    always #(CLK_PERIOD/2) clk_gp_100mhz = ~clk_gp_100mhz;
    
    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    gp_dcache_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CACHE_SIZE(2048),
        .WORDS_PER_LINE(WORDS_PER_LINE),
        .CACHE_LINES(CACHE_LINES),
        .TAG_BITS(24),
        .INDEX_BITS(7),
        .OFFSET_BITS(2)
    ) dut (
        .clk_gp_100mhz(clk_gp_100mhz),
        .rst_n(rst_n),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_be(cpu_be),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .cpu_hit(cpu_hit),
        .ram_req(ram_req),
        .ram_we(ram_we),
        .ram_addr(ram_addr),
        .ram_wdata(ram_wdata),
        .ram_rdata(ram_rdata),
        .ram_ready(ram_ready),
        .cache_enable(cache_enable),
        .cache_flush(cache_flush),
        .cache_invalidate(cache_invalidate),
        .invalidate_addr(invalidate_addr),
        .write_through_mode(write_through_mode),
        .cache_ready(cache_ready),
        .coherency_invalidate(coherency_invalidate),
        .coherency_addr(coherency_addr),
        .coherency_hit(coherency_hit),
        .writeback_pending(writeback_pending),
        .read_hit_count(read_hit_count),
        .write_hit_count(write_hit_count),
        .read_miss_count(read_miss_count),
        .write_miss_count(write_miss_count),
        .total_accesses(total_accesses),
        .writeback_count(writeback_count),
        .hit_rate_percent(hit_rate_percent),
        .cache_utilization(cache_utilization),
        .debug_index(debug_index),
        .debug_tag(debug_tag),
        .debug_valid(debug_valid),
        .debug_dirty(debug_dirty),
        .debug_state(debug_state)
    );
    
    //--------------------------------------------------------------------------
    // Test Tasks
    //--------------------------------------------------------------------------
    
    // Reset system
    task reset_system;
        begin
            $display("===============================================");
            $display("GP D-Cache Controller Testbench");
            $display("MAK8u Microcontroller Project");
            $display("Author: Manikanta Gonugondla");
            $display("===============================================");
            $display("=== Resetting System ===");
            rst_n = 1'b0;
            cpu_req = 1'b0;
            cpu_we = 1'b0;
            cpu_be = 4'hF;
            cpu_addr = 32'h0000_0000;
            cpu_wdata = 32'h0000_0000;
            cache_enable = 1'b1;
            cache_flush = 1'b0;
            cache_invalidate = 1'b0;
            invalidate_addr = 32'h0000_0000;
            write_through_mode = 1'b0;  // Default to write-back
            coherency_invalidate = 1'b0;
            coherency_addr = 32'h0000_0000;
            repeat(5) @(posedge clk_gp_100mhz);
            rst_n = 1'b1;
            repeat(3) @(posedge clk_gp_100mhz);
            $display("Reset completed");
        end
    endtask
    
    // Cache read operation
    task cache_read(input [31:0] addr, output [31:0] data, output logic hit, output logic ready);
        begin
            cpu_req = 1'b1;
            cpu_we = 1'b0;
            cpu_be = 4'hF;
            cpu_addr = addr;
            timeout_counter = 0;
            
            // Wait for response
            do begin
                @(posedge clk_gp_100mhz);
                timeout_counter++;
                if (timeout_counter > 200) begin
                    $error("Timeout waiting for cache read response");
                    ready = 1'b0;
                    hit = 1'b0;
                    data = 32'h0000_0000;
                    break;
                end
            end while (!cpu_ready);
            
            data = cpu_rdata;
            hit = cpu_hit;
            ready = cpu_ready;
            cpu_req = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    // Cache write operation
    task cache_write(input [31:0] addr, input [31:0] data, input [3:0] be,
                    output logic hit, output logic ready);
        begin
            cpu_req = 1'b1;
            cpu_we = 1'b1;
            cpu_be = be;
            cpu_addr = addr;
            cpu_wdata = data;
            timeout_counter = 0;
            
            // Wait for response
            do begin
                @(posedge clk_gp_100mhz);
                timeout_counter++;
                if (timeout_counter > 200) begin
                    $error("Timeout waiting for cache write response");
                    ready = 1'b0;
                    hit = 1'b0;
                    break;
                end
            end while (!cpu_ready);
            
            hit = cpu_hit;
            ready = cpu_ready;
            cpu_req = 1'b0;
            cpu_we = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    // Cache flush
    task flush_cache;
        begin
            cache_flush = 1'b1;
            @(posedge clk_gp_100mhz);
            cache_flush = 1'b0;
            
            // Wait for flush completion
            timeout_counter = 0;
            do begin
                @(posedge clk_gp_100mhz);
                timeout_counter++;
                if (timeout_counter > 2000) begin
                    $error("Timeout waiting for cache flush");
                    break;
                end
            end while (!cache_ready);
        end
    endtask
    
    // Cache line invalidation
    task invalidate_cache_line(input [31:0] addr);
        begin
            invalidate_addr = addr;
            cache_invalidate = 1'b1;
            @(posedge clk_gp_100mhz);
            cache_invalidate = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    // Coherency invalidation
    task coherency_invalidate_line(input [31:0] addr);
        begin
            coherency_addr = addr;
            coherency_invalidate = 1'b1;
            @(posedge clk_gp_100mhz);
            coherency_invalidate = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Test Procedures
    //--------------------------------------------------------------------------
    
    // Test 1: Basic read operations
    task test_basic_reads;
        begin
            $display("=== Test 1: Basic Read Operations ===");
            test_number = 1;
            
            // First read should miss
            cache_read(32'h0001_0000, test_rdata, test_hit, test_ready);
            if (!test_ready) begin
                $error("Test 1: Cache read failed");
                test_errors++;
            end
            if (test_hit) begin
                $error("Test 1: Expected miss but got hit");
                test_errors++;
            end
            if (test_rdata != (32'h0001_0000 ^ 32'h5A5A5A5A)) begin
                $error("Test 1: Data mismatch - Expected 0x%08X, Got 0x%08X", 
                       (32'h0001_0000 ^ 32'h5A5A5A5A), test_rdata);
                test_errors++;
            end
            
            // Second read to same cache line should hit
            cache_read(32'h0001_0004, test_rdata, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 1: Expected hit but got miss");
                test_errors++;
            end
            if (test_rdata != (32'h0001_0004 ^ 32'h5A5A5A5A)) begin
                $error("Test 1: Hit data mismatch");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 1: Basic read operations - PASS");
            end
        end
    endtask
    
    // Test 2: Basic write operations
    task test_basic_writes;
        begin
            $display("=== Test 2: Basic Write Operations ===");
            test_number = 2;
            
            // Write to new cache line (should miss)
            cache_write(32'h0002_0000, 32'hDEAD_BEEF, 4'hF, test_hit, test_ready);
            if (!test_ready) begin
                $error("Test 2: Cache write failed");
                test_errors++;
            end
            if (test_hit) begin
                $error("Test 2: Expected write miss but got hit");
                test_errors++;
            end
            
            // Read back should hit
            cache_read(32'h0002_0000, test_rdata, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 2: Expected read hit after write");
                test_errors++;
            end
            if (test_rdata != 32'hDEAD_BEEF) begin
                $error("Test 2: Write data mismatch - Expected 0x%08X, Got 0x%08X", 
                       32'hDEAD_BEEF, test_rdata);
                test_errors++;
            end
            
            // Write to same cache line (should hit)
            cache_write(32'h0002_0004, 32'hCAFE_BABE, 4'hF, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 2: Expected write hit but got miss");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 2: Basic write operations - PASS");
            end
        end
    endtask
    
    // Test 3: Byte enable functionality
    task test_byte_enables;
        begin
            $display("=== Test 3: Byte Enable Testing ===");
            test_number = 3;
            
            // Write full word first
            cache_write(32'h0003_0000, 32'h1234_5678, 4'hF, test_hit, test_ready);
            
            // Read back to verify
            cache_read(32'h0003_0000, test_rdata, test_hit, test_ready);
            if (test_rdata != 32'h1234_5678) begin
                $error("Test 3: Full word write failed");
                test_errors++;
            end
            
            // Write only lower byte
            cache_write(32'h0003_0000, 32'hXXXX_XXAA, 4'h1, test_hit, test_ready);
            cache_read(32'h0003_0000, test_rdata, test_hit, test_ready);
            if (test_rdata != 32'h1234_56AA) begin
                $error("Test 3: Byte 0 write failed - Expected 0x123456AA, Got 0x%08X", test_rdata);
                test_errors++;
            end
            
            // Write only upper byte
            cache_write(32'h0003_0000, 32'hBBXX_XXXX, 4'h8, test_hit, test_ready);
            cache_read(32'h0003_0000, test_rdata, test_hit, test_ready);
            if (test_rdata != 32'hBB34_56AA) begin
                $error("Test 3: Byte 3 write failed - Expected 0xBB3456AA, Got 0x%08X", test_rdata);
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 3: Byte enable testing - PASS");
            end
        end
    endtask
    
    // Test 4: Write-through mode
    task test_write_through;
        begin
            $display("=== Test 4: Write-Through Mode ===");
            test_number = 4;
            
            // Enable write-through mode
            write_through_mode = 1'b1;
            
            // Write data (should go directly to RAM)
            cache_write(32'h0004_0000, 32'h1111_2222, 4'hF, test_hit, test_ready);
            
            // Verify data is in RAM
            if (ram_memory[32'h0004_0000 >> 2] != 32'h1111_2222) begin
                $error("Test 4: Write-through failed - data not in RAM");
                test_errors++;
            end
            
            // Read back should hit cache
            cache_read(32'h0004_0000, test_rdata, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 4: Expected cache hit in write-through mode");
                test_errors++;
            end
            if (test_rdata != 32'h1111_2222) begin
                $error("Test 4: Write-through read mismatch");
                test_errors++;
            end
            
            // Return to write-back mode
            write_through_mode = 1'b0;
            
            if (test_errors == 0) begin
                $display("Test 4: Write-through mode - PASS");
            end
        end
    endtask
    
    // Test 5: Cache flush with dirty lines
    task test_cache_flush;
        begin
            $display("=== Test 5: Cache Flush with Dirty Lines ===");
            test_number = 5;
            
            // Write data to create dirty lines
            cache_write(32'h0005_0000, 32'h3333_4444, 4'hF, test_hit, test_ready);
            cache_write(32'h0005_1000, 32'h5555_6666, 4'hF, test_hit, test_ready);
            
            // Verify cache hits
            cache_read(32'h0005_0000, test_rdata, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 5: Cache line not present before flush");
                test_errors++;
            end
            
            // Flush cache
            flush_cache();
            
            // Verify cache is empty (should miss)
            cache_read(32'h0005_0000, test_rdata, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 5: Cache hit after flush - flush failed");
                test_errors++;
            end
            
            // Verify data was written back to RAM
            if (ram_memory[32'h0005_0000 >> 2] != 32'h3333_4444) begin
                $error("Test 5: Dirty line not written back during flush");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 5: Cache flush with dirty lines - PASS");
            end
        end
    endtask
    
    // Test 6: Cache invalidation
    task test_cache_invalidation;
        begin
            $display("=== Test 6: Cache Invalidation ===");
            test_number = 6;
            
            // Load cache lines
            cache_write(32'h0006_0000, 32'h7777_8888, 4'hF, test_hit, test_ready);
            cache_write(32'h0006_1000, 32'h9999_AAAA, 4'hF, test_hit, test_ready);
            
            // Verify both are cached
            cache_read(32'h0006_0000, test_rdata, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 6: First cache line not present");
                test_errors++;
            end
            
            cache_read(32'h0006_1000, test_rdata, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 6: Second cache line not present");
                test_errors++;
            end
            
            // Invalidate first line only
            invalidate_cache_line(32'h0006_0000);
            
            // First should miss, second should hit
            cache_read(32'h0006_0000, test_rdata, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 6: Invalidated line still hits");
                test_errors++;
            end
            
            cache_read(32'h0006_1000, test_rdata, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 6: Non-invalidated line missing");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 6: Cache invalidation - PASS");
            end
        end
    endtask
    
    // Test 7: Cache coherency
    task test_cache_coherency;
        begin
            $display("=== Test 7: Cache Coherency ===");
            test_number = 7;
            
            // Load data into cache
            cache_write(32'h0007_0000, 32'hBBBB_CCCC, 4'hF, test_hit, test_ready);
            
            // Verify coherency hit detection
            coherency_addr = 32'h0007_0000;
            @(posedge clk_gp_100mhz);
            if (!coherency_hit) begin
                $error("Test 7: Coherency hit detection failed");
                test_errors++;
            end
            
            // Test coherency invalidation
            coherency_invalidate_line(32'h0007_0000);
            
            // Should miss after coherency invalidation
            cache_read(32'h0007_0000, test_rdata, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 7: Cache hit after coherency invalidation");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 7: Cache coherency - PASS");
            end
        end
    endtask
    
    // Test 8: Performance counters
    task test_performance_counters;
        begin
            $display("=== Test 8: Performance Counters ===");
            test_number = 8;
            
            // Record initial values
            read_hits_before = read_hit_count;
            write_hits_before = write_hit_count;
            read_misses_before = read_miss_count;
            write_misses_before = write_miss_count;
            total_before = total_accesses;
            wb_before = writeback_count;
            
            // Perform operations
            cache_read(32'h0008_0000, test_rdata, test_hit, test_ready);   // Read miss
            cache_write(32'h0008_0000, 32'hDDDD_EEEE, 4'hF, test_hit, test_ready); // Write hit
            cache_read(32'h0008_0000, test_rdata, test_hit, test_ready);   // Read hit
            cache_write(32'h0008_1000, 32'hFFFF_0000, 4'hF, test_hit, test_ready); // Write miss
            
            // Record final values
            read_hits_after = read_hit_count;
            write_hits_after = write_hit_count;
            read_misses_after = read_miss_count;
            write_misses_after = write_miss_count;
            total_after = total_accesses;
            wb_after = writeback_count;
            
            // Verify counters
            if ((read_hits_after - read_hits_before) != 1) begin
                $error("Test 8: Read hit count incorrect - Expected 1, Got %0d", 
                       (read_hits_after - read_hits_before));
                test_errors++;
            end
            
            if ((write_hits_after - write_hits_before) != 1) begin
                $error("Test 8: Write hit count incorrect - Expected 1, Got %0d", 
                       (write_hits_after - write_hits_before));
                test_errors++;
            end
            
            if ((read_misses_after - read_misses_before) != 1) begin
                $error("Test 8: Read miss count incorrect - Expected 1, Got %0d", 
                       (read_misses_after - read_misses_before));
                test_errors++;
            end
            
            if ((write_misses_after - write_misses_before) != 1) begin
                $error("Test 8: Write miss count incorrect - Expected 1, Got %0d", 
                       (write_misses_after - write_misses_before));
                test_errors++;
            end
            
            if ((total_after - total_before) != 4) begin
                $error("Test 8: Total access count incorrect - Expected 4, Got %0d", 
                       (total_after - total_before));
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 8: Performance counters - PASS");
                $display("  Hit rate: %0d%%", hit_rate_percent);
                $display("  Cache utilization: %0d%%", cache_utilization);
                $display("  Writeback count: %0d", writeback_count);
            end
        end
    endtask
    
    // Test 9: Cache disable functionality
    task test_cache_disable;
        begin
            $display("=== Test 9: Cache Disable ===");
            test_number = 9;
            
            // Disable cache
            cache_enable = 1'b0;
            
            // All accesses should bypass cache
            cache_write(32'h0009_0000, 32'h1111_1111, 4'hF, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 9: Cache hit when disabled");
                test_errors++;
            end
            
            cache_read(32'h0009_0000, test_rdata, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 9: Cache hit on read when disabled");
                test_errors++;
            end
            if (test_rdata != 32'h1111_1111) begin
                $error("Test 9: Bypass mode data mismatch");
                test_errors++;
            end
            
            // Re-enable cache
            cache_enable = 1'b1;
            
            if (test_errors == 0) begin
                $display("Test 9: Cache disable - PASS");
            end
        end
    endtask
    
    // Test 10: Stress test with writeback scenarios
    task test_writeback_stress;
        begin
            $display("=== Test 10: Writeback Stress Test ===");
            test_number = 10;
            
            // Fill cache with dirty lines
            for (i = 0; i < 32; i++) begin
                test_addr = 32'h000A_0000 + (i * 32'h1000);  // Different cache lines
                test_wdata = 32'hA000_0000 + i;
                cache_write(test_addr, test_wdata, 4'hF, test_hit, test_ready);
            end
            
            // Force evictions by accessing new lines
            for (i = 0; i < 16; i++) begin
                test_addr = 32'h001A_0000 + (i * 32'h1000);  // Map to same cache indices
                cache_read(test_addr, test_rdata, test_hit, test_ready);
                if (test_hit) begin
                    $error("Test 10: Unexpected cache hit during eviction test");
                    test_errors++;
                    break;
                end
            end
            
            // Verify some writebacks occurred
            if (writeback_count == 0) begin
                $error("Test 10: No writebacks detected during stress test");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 10: Writeback stress test - PASS");
                $display("  Total writebacks: %0d", writeback_count);
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        test_errors = 0;
        
        reset_system();
        
        test_basic_reads();
        test_basic_writes();
        test_byte_enables();
        test_write_through();
        test_cache_flush();
        test_cache_invalidation();
        test_cache_coherency();
        test_performance_counters();
        test_cache_disable();
        test_writeback_stress();
        
        // Final results
        $display("===============================================");
        $display("Test Results Summary:");
        $display("  Tests completed: 10");
        $display("  Total errors: %0d", test_errors);
        $display("  Final read hit count: %0d", read_hit_count);
        $display("  Final write hit count: %0d", write_hit_count);
        $display("  Final read miss count: %0d", read_miss_count);
        $display("  Final write miss count: %0d", write_miss_count);
        $display("  Final writeback count: %0d", writeback_count);
        $display("  Hit rate: %0d%%", hit_rate_percent);
        $display("  Cache utilization: %0d%%", cache_utilization);
        $display("  Cache ready status: %0d", cache_ready);
        
        if (test_errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("GP D-Cache Controller is working correctly");
        end else begin
            $display("*** %0d TESTS FAILED ***", test_errors);
            $display("Module needs debugging");
        end
        $display("===============================================");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #TEST_TIMEOUT;
        $error("Testbench timeout after %0d ns", TEST_TIMEOUT);
        $finish;
    end

endmodule
