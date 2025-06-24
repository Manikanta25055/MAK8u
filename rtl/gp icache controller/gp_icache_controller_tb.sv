`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: gp_icache_controller_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T (Simulation)
// Tool Versions: Vivado 2024.2
// Description: Comprehensive testbench for GP-Core Instruction Cache Controller
//              Tests 4KB cache with dual-issue capability and advanced features
//              Validates high-performance operation at 100MHz
// 
// Dependencies: gp_icache_controller.sv
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - Tests dual-issue instruction fetch capability
// - Validates cache coherency and invalidation
// - Comprehensive performance counter verification
// - Advanced cache management features testing
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_icache_controller_tb;

    //--------------------------------------------------------------------------
    // Test Parameters
    //--------------------------------------------------------------------------
    localparam CLK_PERIOD = 10;        // 100MHz GP-Core clock (10ns)
    localparam ADDR_WIDTH = 16;
    localparam DATA_WIDTH = 16;
    localparam CACHE_LINES = 256;
    localparam WORDS_PER_LINE = 8;
    localparam TEST_TIMEOUT = 100000;   // 1ms timeout
    
    //--------------------------------------------------------------------------
    // DUT Signals - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    logic                    clk_gp_100mhz;
    logic                    rst_n;
    
    // Primary CPU Interface
    logic                    cpu_req;
    logic [ADDR_WIDTH-1:0]   cpu_addr;
    logic [DATA_WIDTH-1:0]   cpu_data;
    logic                    cpu_ready;
    logic                    cpu_hit;
    
    // Dual-issue CPU Interface
    logic                    cpu_req_2;
    logic [ADDR_WIDTH-1:0]   cpu_addr_2;
    logic [DATA_WIDTH-1:0]   cpu_data_2;
    logic                    cpu_ready_2;
    logic                    cpu_hit_2;
    
    // ROM Controller Interface
    logic                    rom_req;
    logic [ADDR_WIDTH-1:0]   rom_addr;
    logic [DATA_WIDTH-1:0]   rom_data;
    logic                    rom_ready;
    
    // Control Interface
    logic                    cache_enable;
    logic                    cache_flush;
    logic                    cache_invalidate;
    logic [ADDR_WIDTH-1:0]   invalidate_addr;
    logic                    cache_ready;
    
    // Performance Monitoring
    logic [31:0]             hit_count;
    logic [31:0]             miss_count;
    logic [31:0]             total_accesses;
    logic [31:0]             dual_issue_count;
    logic [7:0]              hit_rate_percent;
    logic [7:0]              cache_utilization;
    
    // Debug Interface
    logic [7:0]              debug_index;
    logic [4:0]              debug_tag;
    logic                    debug_valid;
    logic [2:0]              debug_state;
    
    //--------------------------------------------------------------------------
    // Test Control Variables - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    integer test_errors;
    integer test_number;
    integer i, j, k;
    logic [15:0] test_addr;
    logic [15:0] test_addr_2;
    logic [15:0] test_data;
    logic [15:0] test_data_2;
    logic test_hit;
    logic test_hit_2;
    logic test_ready;
    logic test_ready_2;
    integer timeout_counter;
    integer hits_before;
    integer misses_before;
    integer total_before;
    integer dual_before;
    integer hits_after;
    integer misses_after;
    integer total_after;
    integer dual_after;
    
    //--------------------------------------------------------------------------
    // ROM Memory Model
    //--------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] rom_memory [0:65535];
    logic [1:0] rom_delay_counter;
    
    // Initialize ROM with test patterns
    initial begin
        for (int m = 0; m < 65536; m++) begin
            rom_memory[m] = m[15:0] ^ 16'hA5A5;  // XOR pattern for verification
        end
    end
    
    // ROM model with realistic timing (2-3 cycle latency)
    always_ff @(posedge clk_gp_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            rom_data <= 16'h0000;
            rom_ready <= 1'b0;
            rom_delay_counter <= 2'h0;
        end else begin
            if (rom_req && rom_delay_counter == 2'h0) begin
                rom_delay_counter <= 2'h2;  // 2 cycle delay
                rom_ready <= 1'b0;
            end else if (rom_delay_counter > 2'h0) begin
                rom_delay_counter <= rom_delay_counter - 1;
                if (rom_delay_counter == 2'h1) begin
                    rom_data <= rom_memory[rom_addr];
                    rom_ready <= 1'b1;
                end
            end else begin
                rom_ready <= 1'b0;
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
    gp_icache_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CACHE_SIZE(4096),
        .WORDS_PER_LINE(WORDS_PER_LINE),
        .CACHE_LINES(CACHE_LINES),
        .TAG_BITS(5),
        .INDEX_BITS(8),
        .OFFSET_BITS(3)
    ) dut (
        .clk_gp_100mhz(clk_gp_100mhz),
        .rst_n(rst_n),
        .cpu_req(cpu_req),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_ready(cpu_ready),
        .cpu_hit(cpu_hit),
        .cpu_req_2(cpu_req_2),
        .cpu_addr_2(cpu_addr_2),
        .cpu_data_2(cpu_data_2),
        .cpu_ready_2(cpu_ready_2),
        .cpu_hit_2(cpu_hit_2),
        .rom_req(rom_req),
        .rom_addr(rom_addr),
        .rom_data(rom_data),
        .rom_ready(rom_ready),
        .cache_enable(cache_enable),
        .cache_flush(cache_flush),
        .cache_invalidate(cache_invalidate),
        .invalidate_addr(invalidate_addr),
        .cache_ready(cache_ready),
        .hit_count(hit_count),
        .miss_count(miss_count),
        .total_accesses(total_accesses),
        .dual_issue_count(dual_issue_count),
        .hit_rate_percent(hit_rate_percent),
        .cache_utilization(cache_utilization),
        .debug_index(debug_index),
        .debug_tag(debug_tag),
        .debug_valid(debug_valid),
        .debug_state(debug_state)
    );
    
    //--------------------------------------------------------------------------
    // Test Tasks
    //--------------------------------------------------------------------------
    
    // Reset system
    task reset_system;
        begin
            $display("===============================================");
            $display("GP I-Cache Controller Testbench");
            $display("MAK8u Microcontroller Project");
            $display("Author: Manikanta Gonugondla");
            $display("===============================================");
            $display("=== Resetting System ===");
            rst_n = 1'b0;
            cpu_req = 1'b0;
            cpu_req_2 = 1'b0;
            cpu_addr = 16'h0000;
            cpu_addr_2 = 16'h0000;
            cache_enable = 1'b1;
            cache_flush = 1'b0;
            cache_invalidate = 1'b0;
            invalidate_addr = 16'h0000;
            repeat(5) @(posedge clk_gp_100mhz);
            rst_n = 1'b1;
            repeat(3) @(posedge clk_gp_100mhz);
            $display("Reset completed");
        end
    endtask
    
    // Single instruction cache read
    task cache_read(input [15:0] addr, output [15:0] data, output logic hit, output logic ready);
        begin
            cpu_req = 1'b1;
            cpu_req_2 = 1'b0;
            cpu_addr = addr;
            timeout_counter = 0;
            
            // Wait for response
            do begin
                @(posedge clk_gp_100mhz);
                timeout_counter++;
                if (timeout_counter > 100) begin
                    $error("Timeout waiting for cache response");
                    ready = 1'b0;
                    hit = 1'b0;
                    data = 16'h0000;
                    break;
                end
            end while (!cpu_ready);
            
            data = cpu_data;
            hit = cpu_hit;
            ready = cpu_ready;
            cpu_req = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    // Dual-issue instruction cache read
    task dual_cache_read(input [15:0] addr1, input [15:0] addr2, 
                        output [15:0] data1, output [15:0] data2,
                        output logic hit1, output logic hit2,
                        output logic ready1, output logic ready2);
        begin
            cpu_req = 1'b1;
            cpu_req_2 = 1'b1;
            cpu_addr = addr1;
            cpu_addr_2 = addr2;
            timeout_counter = 0;
            
            // Wait for response
            do begin
                @(posedge clk_gp_100mhz);
                timeout_counter++;
                if (timeout_counter > 100) begin
                    $error("Timeout waiting for dual cache response");
                    ready1 = cpu_ready;
                    ready2 = cpu_ready_2;
                    hit1 = cpu_hit;
                    hit2 = cpu_hit_2;
                    data1 = cpu_data;
                    data2 = cpu_data_2;
                    break;
                end
            end while (!cpu_ready);  // Only wait for primary ready
            
            data1 = cpu_data;
            data2 = cpu_data_2;
            hit1 = cpu_hit;
            hit2 = cpu_hit_2;
            ready1 = cpu_ready;
            ready2 = cpu_ready_2;
            cpu_req = 1'b0;
            cpu_req_2 = 1'b0;
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
                if (timeout_counter > 1000) begin
                    $error("Timeout waiting for cache flush");
                    break;
                end
            end while (!cache_ready);
        end
    endtask
    
    // Cache line invalidation
    task invalidate_cache_line(input [15:0] addr);
        begin
            invalidate_addr = addr;
            cache_invalidate = 1'b1;
            @(posedge clk_gp_100mhz);
            cache_invalidate = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Test Procedures
    //--------------------------------------------------------------------------
    
    // Test 1: Basic single instruction cache operations
    task test_basic_operations;
        begin
            $display("=== Test 1: Basic Cache Operations ===");
            test_number = 1;
            
            // First access should miss
            cache_read(16'h1000, test_data, test_hit, test_ready);
            if (!test_ready) begin
                $error("Test 1: Cache read failed");
                test_errors++;
            end
            if (test_hit) begin
                $error("Test 1: Expected miss but got hit");
                test_errors++;
            end
            if (test_data != (16'h1000 ^ 16'hA5A5)) begin
                $error("Test 1: Data mismatch - Expected 0x%04X, Got 0x%04X", 
                       (16'h1000 ^ 16'hA5A5), test_data);
                test_errors++;
            end
            
            // Second access to same address should hit
            cache_read(16'h1000, test_data, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 1: Expected hit but got miss");
                test_errors++;
            end
            if (test_data != (16'h1000 ^ 16'hA5A5)) begin
                $error("Test 1: Hit data mismatch");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 1: Basic operations - PASS");
            end
        end
    endtask
    
    // Test 2: Dual-issue capability
    task test_dual_issue;
        begin
            $display("=== Test 2: Dual-Issue Operations ===");
            test_number = 2;
            
            // Load two different cache lines first
            cache_read(16'h2000, test_data, test_hit, test_ready);
            cache_read(16'h2100, test_data, test_hit, test_ready);
            
            // Now test dual-issue from same cache lines
            dual_cache_read(16'h2000, 16'h2004, test_data, test_data_2, 
                           test_hit, test_hit_2, test_ready, test_ready_2);
            
            if (!test_ready) begin
                $error("Test 2: Primary dual-issue read failed");
                test_errors++;
            end
            if (!test_hit) begin
                $error("Test 2: Expected primary hit in dual-issue");
                test_errors++;
            end
            if (test_data != (16'h2000 ^ 16'hA5A5)) begin
                $error("Test 2: Primary dual-issue data mismatch");
                test_errors++;
            end
            if (!test_ready_2) begin
                $error("Test 2: Secondary dual-issue read failed");
                test_errors++;
            end
            if (!test_hit_2) begin
                $error("Test 2: Expected secondary hit in dual-issue");
                test_errors++;
            end
            if (test_data_2 != (16'h2004 ^ 16'hA5A5)) begin
                $error("Test 2: Secondary dual-issue data mismatch");
                test_errors++;
            end
            
            // Test dual-issue from different cache lines
            dual_cache_read(16'h2008, 16'h2108, test_data, test_data_2, 
                           test_hit, test_hit_2, test_ready, test_ready_2);
            
            // This should handle as single instruction since one misses
            if (!test_ready) begin
                $error("Test 2: Should handle mixed hit/miss as single instruction");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 2: Dual-issue operations - PASS");
            end
        end
    endtask
    
    // Test 3: Cache flush functionality
    task test_cache_flush;
        begin
            $display("=== Test 3: Cache Flush ===");
            test_number = 3;
            
            // Load some cache lines
            cache_read(16'h3000, test_data, test_hit, test_ready);
            cache_read(16'h3100, test_data, test_hit, test_ready);
            
            // Verify they're cached (should hit)
            cache_read(16'h3000, test_data, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 3: Cache line not present before flush");
                test_errors++;
            end
            
            // Flush cache
            flush_cache();
            
            // Verify cache is empty (should miss)
            cache_read(16'h3000, test_data, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 3: Cache hit after flush - flush failed");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 3: Cache flush - PASS");
            end
        end
    endtask
    
    // Test 4: Cache invalidation
    task test_cache_invalidation;
        begin
            $display("=== Test 4: Cache Invalidation ===");
            test_number = 4;
            
            // Load cache lines
            cache_read(16'h4000, test_data, test_hit, test_ready);
            cache_read(16'h4100, test_data, test_hit, test_ready);
            
            // Verify both are cached
            cache_read(16'h4000, test_data, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 4: First cache line not present");
                test_errors++;
            end
            
            cache_read(16'h4100, test_data, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 4: Second cache line not present");
                test_errors++;
            end
            
            // Invalidate first line only
            invalidate_cache_line(16'h4000);
            
            // First should miss, second should hit
            cache_read(16'h4000, test_data, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 4: Invalidated line still hits");
                test_errors++;
            end
            
            cache_read(16'h4100, test_data, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 4: Non-invalidated line missing");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 4: Cache invalidation - PASS");
            end
        end
    endtask
    
    // Test 5: Performance counters
    task test_performance_counters;
        begin
            $display("=== Test 5: Performance Counters ===");
            test_number = 5;
            
            // Record initial values
            hits_before = hit_count;
            misses_before = miss_count;
            total_before = total_accesses;
            dual_before = dual_issue_count;
            
            // Perform operations
            cache_read(16'h5000, test_data, test_hit, test_ready);  // Miss
            cache_read(16'h5000, test_data, test_hit, test_ready);  // Hit
            cache_read(16'h5008, test_data, test_hit, test_ready);  // Miss (different cache line)
            
            // Load another line for dual-issue
            cache_read(16'h5100, test_data, test_hit, test_ready);  // Miss
            dual_cache_read(16'h5000, 16'h5100, test_data, test_data_2, 
                           test_hit, test_hit_2, test_ready, test_ready_2);  // Dual hit
            
            // Record final values
            hits_after = hit_count;
            misses_after = miss_count;
            total_after = total_accesses;
            dual_after = dual_issue_count;
            
            // Verify counters
            if ((hits_after - hits_before) != 3) begin  // 1+1+1 = 3 hits
                $error("Test 5: Hit count incorrect - Expected 3, Got %0d", 
                       (hits_after - hits_before));
                test_errors++;
            end
            
            if ((misses_after - misses_before) != 3) begin  // 3 misses (0x5000, 0x5008, 0x5100)
                $error("Test 5: Miss count incorrect - Expected 3, Got %0d", 
                       (misses_after - misses_before));
                test_errors++;
            end
            
            if ((total_after - total_before) != 5) begin  // 5 total accesses
                $error("Test 5: Total count incorrect - Expected 5, Got %0d", 
                       (total_after - total_before));
                test_errors++;
            end
            
            if ((dual_after - dual_before) != 1) begin  // 1 dual-issue
                $error("Test 5: Dual-issue count incorrect - Expected 1, Got %0d", 
                       (dual_after - dual_before));
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 5: Performance counters - PASS");
                $display("  Hit rate: %0d%%", hit_rate_percent);
                $display("  Cache utilization: %0d%%", cache_utilization);
            end
        end
    endtask
    
    // Test 6: Cache boundary testing
    task test_cache_boundaries;
        begin
            $display("=== Test 6: Cache Boundary Testing ===");
            test_number = 6;
            
            // Test first cache line
            cache_read(16'h0000, test_data, test_hit, test_ready);
            if (test_data != (16'h0000 ^ 16'hA5A5)) begin
                $error("Test 6: First address data incorrect");
                test_errors++;
            end
            
            // Test last word in first cache line
            cache_read(16'h0007, test_data, test_hit, test_ready);
            if (!test_hit) begin
                $error("Test 6: Last word in cache line should hit");
                test_errors++;
            end
            if (test_data != (16'h0007 ^ 16'hA5A5)) begin
                $error("Test 6: Last word data incorrect");
                test_errors++;
            end
            
            // Test maximum address
            cache_read(16'hFFFE, test_data, test_hit, test_ready);
            if (test_data != (16'hFFFE ^ 16'hA5A5)) begin
                $error("Test 6: Maximum address data incorrect");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 6: Cache boundaries - PASS");
            end
        end
    endtask
    
    // Test 7: Stress test with sequential access pattern
    task test_sequential_access;
        begin
            $display("=== Test 7: Sequential Access Pattern ===");
            test_number = 7;
            
            // Sequential access pattern
            for (i = 0; i < 64; i++) begin
                test_addr = 16'h6000 + (i * 2);
                cache_read(test_addr, test_data, test_hit, test_ready);
                if (test_data != (test_addr ^ 16'hA5A5)) begin
                    $error("Test 7: Sequential access data mismatch at iteration %0d", i);
                    test_errors++;
                    break;
                end
            end
            
            // Now read same pattern - should all hit
            for (i = 0; i < 64; i++) begin
                test_addr = 16'h6000 + (i * 2);
                cache_read(test_addr, test_data, test_hit, test_ready);
                if (!test_hit) begin
                    $error("Test 7: Sequential access should hit at iteration %0d", i);
                    test_errors++;
                    break;
                end
            end
            
            if (test_errors == 0) begin
                $display("Test 7: Sequential access pattern - PASS");
            end
        end
    endtask
    
    // Test 8: Cache disable functionality
    task test_cache_disable;
        begin
            $display("=== Test 8: Cache Disable ===");
            test_number = 8;
            
            // Disable cache
            cache_enable = 1'b0;
            
            // All accesses should bypass cache
            cache_read(16'h8000, test_data, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 8: Cache hit when disabled");
                test_errors++;
            end
            
            cache_read(16'h8000, test_data, test_hit, test_ready);
            if (test_hit) begin
                $error("Test 8: Cache hit on repeat access when disabled");
                test_errors++;
            end
            
            // Re-enable cache
            cache_enable = 1'b1;
            
            if (test_errors == 0) begin
                $display("Test 8: Cache disable - PASS");
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        test_errors = 0;
        
        reset_system();
        
        test_basic_operations();
        test_dual_issue();
        test_cache_flush();
        test_cache_invalidation();
        test_performance_counters();
        test_cache_boundaries();
        test_sequential_access();
        test_cache_disable();
        
        // Final results
        $display("===============================================");
        $display("Test Results Summary:");
        $display("  Tests completed: 8");
        $display("  Total errors: %0d", test_errors);
        $display("  Final hit count: %0d", hit_count);
        $display("  Final miss count: %0d", miss_count);
        $display("  Final dual-issue count: %0d", dual_issue_count);
        $display("  Hit rate: %0d%%", hit_rate_percent);
        $display("  Cache utilization: %0d%%", cache_utilization);
        $display("  Cache ready status: %0d", cache_ready);
        
        if (test_errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("GP I-Cache Controller is working correctly");
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
