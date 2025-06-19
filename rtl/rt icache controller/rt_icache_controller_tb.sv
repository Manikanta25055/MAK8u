`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: rt_icache_controller_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T (Simulation)
// Tool Versions: Vivado 2024.2
// Description: Simple, functional testbench for RT-Core Instruction Cache Controller
//              Tests basic cache functionality without extreme stress
// 
// Dependencies: rt_icache_controller.sv
// 
// Revision:
// Revision 0.03 - Simplified functional testbench
// Additional Comments:
// - Basic functional tests only
// - Simple ROM model with minimal delay
// - Comprehensive verification without stress
// 
//////////////////////////////////////////////////////////////////////////////////

module rt_icache_controller_tb;

    // Test parameters
    localparam CLK_PERIOD = 20;  // 50MHz RT-Core clock
    
    //--------------------------------------------------------------------------
    // DUT Signals - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    logic        clk_rt_50mhz;
    logic        rst_n;
    logic        cpu_req;
    logic [15:0] cpu_addr;
    logic [15:0] cpu_data;
    logic        cpu_ready;
    logic        cpu_hit;
    logic        rom_req;
    logic [15:0] rom_addr;
    logic [15:0] rom_data;
    logic        rom_ready;
    logic        cache_enable;
    logic        cache_flush;
    logic        cache_ready;
    logic [31:0] hit_count;
    logic [31:0] miss_count;
    logic [31:0] total_accesses;
    logic [7:0]  hit_rate_percent;
    
    //--------------------------------------------------------------------------
    // Test Variables - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    integer test_errors;
    integer test_number;
    logic [15:0] test_addr;
    logic [15:0] test_data;
    logic test_hit;
    integer i, j;
    
    //--------------------------------------------------------------------------
    // ROM Memory Model - SIMPLE
    //--------------------------------------------------------------------------
    logic [15:0] rom_memory [0:65535];
    
    // Initialize ROM with test data
    initial begin
        for (int k = 0; k < 65536; k++) begin
            rom_memory[k] = k[15:0] + 16'h1000;  // Simple test pattern
        end
    end
    
    // Simple ROM model - 2 cycle delay
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            rom_data <= 16'h0000;
            rom_ready <= 1'b0;
        end else begin
            if (rom_req) begin
                rom_ready <= 1'b1;  // 1 cycle delay
                rom_data <= rom_memory[rom_addr];
            end else begin
                rom_ready <= 1'b0;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial clk_rt_50mhz = 0;
    always #(CLK_PERIOD/2) clk_rt_50mhz = ~clk_rt_50mhz;
    
    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    rt_icache_controller dut (
        .clk_rt_50mhz(clk_rt_50mhz),
        .rst_n(rst_n),
        .cpu_req(cpu_req),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_ready(cpu_ready),
        .cpu_hit(cpu_hit),
        .rom_req(rom_req),
        .rom_addr(rom_addr),
        .rom_data(rom_data),
        .rom_ready(rom_ready),
        .cache_enable(cache_enable),
        .cache_flush(cache_flush),
        .cache_ready(cache_ready),
        .hit_count(hit_count),
        .miss_count(miss_count),
        .total_accesses(total_accesses),
        .hit_rate_percent(hit_rate_percent)
    );
    
    //--------------------------------------------------------------------------
    // Test Tasks
    //--------------------------------------------------------------------------
    
    // Reset system
    task reset_system;
        begin
            $display("=== Resetting System ===");
            rst_n = 1'b0;
            cpu_req = 1'b0;
            cpu_addr = 16'h0000;
            cache_enable = 1'b1;
            cache_flush = 1'b0;
            repeat(5) @(posedge clk_rt_50mhz);
            rst_n = 1'b1;
            repeat(3) @(posedge clk_rt_50mhz);
            $display("Reset completed");
        end
    endtask
    
    // Perform cache read
    task cache_read(input [15:0] addr, output [15:0] data, output logic hit);
        integer timeout;
        begin
            timeout = 0;
            @(posedge clk_rt_50mhz);
            cpu_req = 1'b1;
            cpu_addr = addr;
            
            // Wait for ready
            while (!cpu_ready && timeout < 50) begin
                @(posedge clk_rt_50mhz);
                timeout = timeout + 1;
            end
            
            if (timeout >= 50) begin
                $error("Cache read timeout for address 0x%04X", addr);
                test_errors = test_errors + 1;
            end
            
            data = cpu_data;
            hit = cpu_hit;
            
            cpu_req = 1'b0;
            @(posedge clk_rt_50mhz);
        end
    endtask
    
    // Flush cache
    task flush_cache;
        begin
            $display("=== Flushing Cache ===");
            cache_flush = 1'b1;
            @(posedge clk_rt_50mhz);
            cache_flush = 1'b0;
            
            // Wait for flush to complete
            while (!cache_ready) begin
                @(posedge clk_rt_50mhz);
            end
            $display("Cache flush completed");
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Test Procedures
    //--------------------------------------------------------------------------
    
    // Test 1: Basic cache miss and hit
    task test_basic_operation;
        begin
            $display("=== Test 1: Basic Operation ===");
            test_number = 1;
            
            // First access - should miss
            cache_read(16'h1000, test_data, test_hit);
            if (test_hit) begin
                $error("Test 1: First access should be miss");
                test_errors = test_errors + 1;
            end else begin
                $display("Test 1: First access MISS - PASS");
            end
            
            // Second access to same address - should hit
            cache_read(16'h1000, test_data, test_hit);
            if (!test_hit) begin
                $error("Test 1: Second access should be hit");
                test_errors = test_errors + 1;
            end else begin
                $display("Test 1: Second access HIT - PASS");
            end
            
            // Verify data is correct
            if (test_data != rom_memory[16'h1000]) begin
                $error("Test 1: Data mismatch - Expected 0x%04X, Got 0x%04X", 
                       rom_memory[16'h1000], test_data);
                test_errors = test_errors + 1;
            end else begin
                $display("Test 1: Data correct - PASS");
            end
        end
    endtask
    
    // Test 2: Same cache line, different words
    task test_cache_line_words;
        begin
            $display("=== Test 2: Cache Line Words ===");
            test_number = 2;
            
            // Access different words in same cache line
            cache_read(16'h2000, test_data, test_hit); // Should miss (first time)
            cache_read(16'h2002, test_data, test_hit); // Should hit (same line)
            if (!test_hit) begin
                $error("Test 2: Same line access should hit");
                test_errors = test_errors + 1;
            end else begin
                $display("Test 2: Same line HIT - PASS");
            end
            
            cache_read(16'h2004, test_data, test_hit); // Should hit (same line)
            if (!test_hit) begin
                $error("Test 2: Same line access should hit");
                test_errors = test_errors + 1;
            end else begin
                $display("Test 2: Same line HIT - PASS");
            end
        end
    endtask
    
    // Test 3: Cache line replacement
    task test_cache_replacement;
        begin
            $display("=== Test 3: Cache Replacement ===");
            test_number = 3;
            
            // Fill a cache line
            cache_read(16'h3000, test_data, test_hit); // Miss - fills line
            cache_read(16'h3000, test_data, test_hit); // Hit
            
            // Access different tag, same index (should replace)
            cache_read(16'h7000, test_data, test_hit); // Miss - replaces line
            
            // Go back to original - should miss now
            cache_read(16'h3000, test_data, test_hit);
            if (test_hit) begin
                $error("Test 3: Replaced line should miss");
                test_errors = test_errors + 1;
            end else begin
                $display("Test 3: Line replacement MISS - PASS");
            end
        end
    endtask
    
    // Test 4: Sequential accesses
    task test_sequential_access;
        integer hits, misses;
        begin
            $display("=== Test 4: Sequential Access ===");
            test_number = 4;
            hits = 0;
            misses = 0;
            
            // Access sequential addresses
            for (i = 0; i < 32; i++) begin
                test_addr = 16'h4000 + (i * 2);
                cache_read(test_addr, test_data, test_hit);
                if (test_hit) begin
                    hits = hits + 1;
                end else begin
                    misses = misses + 1;
                end
            end
            
            $display("Test 4: Sequential - Hits=%0d, Misses=%0d", hits, misses);
            
            // Should have some hits due to spatial locality
            if (hits == 0) begin
                $error("Test 4: Should have some hits in sequential access");
                test_errors = test_errors + 1;
            end else begin
                $display("Test 4: Sequential locality - PASS");
            end
        end
    endtask
    
    // Test 5: Cache flush
    task test_cache_flush;
        begin
            $display("=== Test 5: Cache Flush ===");
            test_number = 5;
            
            // Fill cache with some data
            cache_read(16'h5000, test_data, test_hit); // Miss
            cache_read(16'h5000, test_data, test_hit); // Hit
            if (!test_hit) begin
                $error("Test 5: Pre-flush should hit");
                test_errors = test_errors + 1;
            end
            
            // Flush cache
            flush_cache();
            
            // Access same address - should miss now
            cache_read(16'h5000, test_data, test_hit);
            if (test_hit) begin
                $error("Test 5: Post-flush should miss");
                test_errors = test_errors + 1;
            end else begin
                $display("Test 5: Cache flush - PASS");
            end
        end
    endtask
    
    // Test 6: Performance counters
    task test_performance_counters;
        integer start_hits, start_misses, start_total;
        integer end_hits, end_misses, end_total;
        begin
            $display("=== Test 6: Performance Counters ===");
            test_number = 6;
            
            start_hits = hit_count;
            start_misses = miss_count;
            start_total = total_accesses;
            
            // Perform some accesses
            cache_read(16'h6000, test_data, test_hit); // Miss
            cache_read(16'h6000, test_data, test_hit); // Hit
            cache_read(16'h6002, test_data, test_hit); // Hit
            
            end_hits = hit_count;
            end_misses = miss_count;
            end_total = total_accesses;
            
            if ((end_total - start_total) != 3) begin
                $error("Test 6: Total count should increase by 3");
                test_errors = test_errors + 1;
            end
            
            if ((end_hits - start_hits) != 2) begin
                $error("Test 6: Hit count should increase by 2");
                test_errors = test_errors + 1;
            end
            
            if ((end_misses - start_misses) != 1) begin
                $error("Test 6: Miss count should increase by 1");
                test_errors = test_errors + 1;
            end
            
            if (test_errors == 0) begin
                $display("Test 6: Performance counters - PASS");
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Execution
    //--------------------------------------------------------------------------
    
    initial begin
        $display("=============================================");
        $display("RT I-Cache Controller Testbench");
        $display("MAK8u Microcontroller Project");
        $display("Author: Manikanta Gonugondla");
        $display("=============================================");
        
        test_errors = 0;
        
        // Reset and initialize
        reset_system();
        
        // Run all tests
        test_basic_operation();
        test_cache_line_words();
        test_cache_replacement();
        test_sequential_access();
        test_cache_flush();
        test_performance_counters();
        
        // Wait a few cycles
        repeat(10) @(posedge clk_rt_50mhz);
        
        // Final report
        $display("=============================================");
        $display("Test Results Summary:");
        $display("  Tests completed: 6");
        $display("  Total errors: %0d", test_errors);
        $display("  Final hit count: %0d", hit_count);
        $display("  Final miss count: %0d", miss_count);
        $display("  Final total accesses: %0d", total_accesses);
        $display("  Final hit rate: %0d%%", hit_rate_percent);
        
        if (test_errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("RT I-Cache Controller is WORKING CORRECTLY!");
        end else begin
            $display("*** %0d TESTS FAILED ***", test_errors);
            $display("Module needs debugging");
        end
        
        $display("=============================================");
        $finish;
    end
    
    // Simple timeout
    initial begin
        #200000; // 200us timeout
        $error("Simulation timeout");
        $finish;
    end

endmodule
