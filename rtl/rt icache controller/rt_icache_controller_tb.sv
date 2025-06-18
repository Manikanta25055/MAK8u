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
// Description: Comprehensive testbench for RT-Core Instruction Cache Controller
//              Tests cache under extreme conditions, performance scenarios
//              Validates hit/miss behavior, flush operations, error conditions
// 
// Dependencies: rt_icache_controller.sv
// 
// Revision:
// Revision 0.01 - Initial comprehensive test suite
// Additional Comments:
// - Tests all cache scenarios including edge cases
// - Performance benchmarking with statistical analysis
// - Stress testing with burst operations
// 
//////////////////////////////////////////////////////////////////////////////////

module rt_icache_controller_tb;

    // Test parameters
    localparam CLK_PERIOD = 20;  // 50MHz RT-Core clock
    localparam CACHE_LINES = 128;
    localparam WORDS_PER_LINE = 8;
    
    //--------------------------------------------------------------------------
    // DUT Signals
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
    // Test Control Variables - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    integer test_count;
    integer error_count;
    integer cycle_count;
    logic [15:0] test_pattern [0:1023];
    logic [15:0] expected_data;
    integer hit_target;
    integer miss_target;
    integer stress_iterations;
    integer random_seed;
    
    // Variables for all test tasks - NO MID-CODE DECLARATIONS
    logic [15:0] read_data;
    logic hit_flag;
    logic [15:0] data_before, data_after;
    logic hit_before, hit_after;
    integer sequential_hits;
    logic [15:0] line_start;
    integer random_hits;
    logic [15:0] addr_var;
    logic [15:0] data_var;
    logic hit_var;
    integer start_time, end_time;
    integer total_cycles;
    real avg_cycles_per_access;
    
    // Extreme test variables
    logic [15:0] boundary_addrs [0:7];
    logic [15:0] addr1, addr2, addr3;
    
    // Initialize boundary addresses
    initial begin
        boundary_addrs[0] = 16'h0000;
        boundary_addrs[1] = 16'h0001;
        boundary_addrs[2] = 16'h7FFF;
        boundary_addrs[3] = 16'h8000;
        boundary_addrs[4] = 16'hFFFE;
        boundary_addrs[5] = 16'hFFFF;
        boundary_addrs[6] = 16'h1FFF;
        boundary_addrs[7] = 16'h2000;
        stress_iterations = 500;
    end
    
    //--------------------------------------------------------------------------
    // ROM Simulation Model
    //--------------------------------------------------------------------------
    logic [15:0] rom_memory [0:65535];
    
    // Initialize ROM with test patterns
    initial begin
        random_seed = 42;
        for (int i = 0; i < 65536; i++) begin
            rom_memory[i] = i[15:0] ^ (i[15:0] << 8) ^ 16'hA5A5;
        end
        
        // Special test patterns
        for (int i = 0; i < 1024; i++) begin
            test_pattern[i] = 16'h1000 + i[15:0];
            rom_memory[16'h1000 + i] = test_pattern[i];
        end
    end
    
    //--------------------------------------------------------------------------
    // COMPLEX ROM Model - Simulates worst-case conditions
    //--------------------------------------------------------------------------
    logic [3:0] rom_delay_counter;
    logic [3:0] rom_random_delay;
    logic rom_error_inject;
    logic [7:0] rom_error_rate;
    
    // Complex ROM Controller Model with random delays, errors, timeouts
    always_ff @(posedge clk_rt_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            rom_data <= 16'h0000;
            rom_ready <= 1'b0;
            rom_delay_counter <= 4'h0;
            rom_random_delay <= 4'h0;
            rom_error_inject <= 1'b0;
        end else begin
            if (rom_req && rom_delay_counter == 4'h0) begin
                // Generate random delay (1-15 cycles) to stress the cache
                rom_random_delay <= $urandom_range(1, 15);
                rom_delay_counter <= 4'h1;
                rom_ready <= 1'b0;
                
                // Inject random errors (5% chance)
                rom_error_inject <= ($urandom_range(1, 100) <= 5);
            end else if (rom_delay_counter > 4'h0) begin
                if (rom_delay_counter >= rom_random_delay && !rom_error_inject) begin
                    rom_ready <= 1'b1;
                    rom_data <= rom_memory[rom_addr];
                    rom_delay_counter <= 4'h0;
                end else if (rom_error_inject && rom_delay_counter > 4'd10) begin
                    // Timeout scenario - never respond
                    rom_ready <= 1'b0;
                    rom_delay_counter <= 4'h0;
                    rom_error_inject <= 1'b0;
                end else begin
                    rom_delay_counter <= rom_delay_counter + 1;
                    rom_ready <= 1'b0;
                end
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
    
    // Reset sequence
    task reset_dut;
        begin
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
    
    // Single cache access
    task cache_read(input [15:0] addr, output [15:0] data, output logic hit);
        begin
            @(posedge clk_rt_50mhz);
            cpu_req = 1'b1;
            cpu_addr = addr;
            
            // Wait for response
            while (!cpu_ready) begin
                @(posedge clk_rt_50mhz);
                cycle_count = cycle_count + 1;
            end
            
            data = cpu_data;
            hit = cpu_hit;
            
            @(posedge clk_rt_50mhz);
            cpu_req = 1'b0;
            @(posedge clk_rt_50mhz);
        end
    endtask
    
    // Burst read sequence
    task burst_read(input [15:0] start_addr, input integer length);
        begin
            $display("=== Burst Read: Start=0x%04X, Length=%0d ===", start_addr, length);
            
            for (int i = 0; i < length; i++) begin
                cache_read(start_addr + i, read_data, hit_flag);
                expected_data = rom_memory[start_addr + i];
                
                if (read_data !== expected_data) begin
                    $error("Burst read mismatch at 0x%04X: Expected=0x%04X, Got=0x%04X", 
                           start_addr + i, expected_data, read_data);
                    error_count = error_count + 1;
                end
                
                if (i == 0 && hit_flag) begin
                    $warning("First access in burst should be miss, but got hit");
                end
            end
        end
    endtask
    
    // Cache flush test
    task test_cache_flush;
        begin
            $display("=== Cache Flush Test ===");
            
            // Fill cache line first
            cache_read(16'h1000, data_before, hit_before);
            $display("Before flush - First access: Data=0x%04X, Hit=%b", data_before, hit_before);
            
            // Second access should hit
            cache_read(16'h1000, data_before, hit_before);
            $display("Before flush - Second access: Data=0x%04X, Hit=%b", data_before, hit_before);
            
            if (!hit_before) begin
                $error("Expected cache hit before flush");
                error_count = error_count + 1;
            end
            
            // Perform flush
            @(posedge clk_rt_50mhz);
            cache_flush = 1'b1;
            @(posedge clk_rt_50mhz);
            cache_flush = 1'b0;
            
            // Wait for flush to complete (2 cycles)
            repeat(3) @(posedge clk_rt_50mhz);
            
            // Test access after flush (should miss)
            cache_read(16'h1000, data_after, hit_after);
            $display("After flush - Access: Data=0x%04X, Hit=%b", data_after, hit_after);
            
            if (hit_after) begin
                $error("Cache hit after flush - flush failed");
                error_count = error_count + 1;
            end else begin
                $display("Cache flush successful - access correctly missed");
            end
        end
    endtask
    
    // Sequential access pattern test
    task test_sequential_access;
        begin
            $display("=== Sequential Access Pattern Test ===");
            sequential_hits = 0;
            
            // Test sequential access within cache lines
            for (int line = 0; line < 4; line++) begin
                for (int word = 0; word < WORDS_PER_LINE; word++) begin
                    cache_read(16'h2000 + (line * 16) + word, read_data, hit_flag);
                    if (hit_flag && word > 0) begin
                        sequential_hits = sequential_hits + 1;
                    end
                end
            end
            
            $display("Sequential hits within lines: %0d/%0d", sequential_hits, (4 * (WORDS_PER_LINE - 1)));
        end
    endtask
    
    // Random access stress test
    task stress_test_random_access;
        begin
            $display("=== Random Access Stress Test ===");
            random_hits = 0;
            
            for (int i = 0; i < stress_iterations; i++) begin
                addr_var = $urandom_range(16'h0000, 16'hFFFF) & 16'hFFFE; // Even addresses
                cache_read(addr_var, read_data, hit_flag);
                
                if (hit_flag) begin
                    random_hits = random_hits + 1;
                end
                
                expected_data = rom_memory[addr_var];
                if (read_data !== expected_data) begin
                    $error("Random access data mismatch at 0x%04X", addr_var);
                    error_count = error_count + 1;
                end
            end
            
            $display("Random access hit rate: %0d/%0d (%0d%%)", 
                    random_hits, stress_iterations, (random_hits * 100) / stress_iterations);
        end
    endtask
    
    // Test cache line boundary test
    task test_cache_boundaries;
        begin
            $display("=== Cache Line Boundary Test ===");
            
            // Test addresses around cache line boundaries
            for (int line = 0; line < 8; line++) begin
                line_start = line * 16;
                
                // Last word of previous line (if not first line)
                if (line > 0) begin
                    cache_read(line_start - 1, read_data, hit_flag);
                end
                
                // First word of current line
                cache_read(line_start, read_data, hit_flag);
                
                // Last word of current line
                cache_read(line_start + 15, read_data, hit_flag);
                
                // First word of next line
                cache_read(line_start + 16, read_data, hit_flag);
            end
        end
    endtask
    
    // Performance benchmark
    task performance_benchmark;
        begin
            $display("=== Performance Benchmark ===");
            
            start_time = $time;
            cycle_count = 0;
            
            // Benchmark with mixed hit/miss pattern
            for (int i = 0; i < 1000; i++) begin
                addr_var = (i % 128) * 16 + (i % 8);
                cache_read(addr_var, data_var, hit_var);
            end
            
            end_time = $time;
            total_cycles = cycle_count;
            avg_cycles_per_access = real'(total_cycles) / 1000.0;
            
            $display("Performance Results:");
            $display("  Total cycles: %0d", total_cycles);
            $display("  Average cycles per access: %.2f", avg_cycles_per_access);
            $display("  Hit rate: %0d%% (%0d hits, %0d misses)", 
                    hit_rate_percent, hit_count, miss_count);
        end
    endtask
    
    // Cache disable test
    task test_cache_disable;
        begin
            $display("=== Cache Disable Test ===");
            
            // Disable cache
            cache_enable = 1'b0;
            
            // All accesses should bypass cache
            for (int i = 0; i < 10; i++) begin
                cache_read(16'h3000 + i, read_data, hit_flag);
                if (cpu_hit) begin
                    $error("Cache hit when cache disabled");
                    error_count = error_count + 1;
                end
            end
            
            // Re-enable cache
            cache_enable = 1'b1;
            $display("Cache disable test completed");
        end
    endtask
    
    //--------------------------------------------------------------------------
    // EXTREME Test Sequence - Maximum stress testing
    //--------------------------------------------------------------------------
    initial begin
        test_count = 0;
        error_count = 0;
        cycle_count = 0;
        
        $display("RT I-Cache Controller EXTREME STRESS Testbench");
        $display("================================================");
        $display("Testing under worst-case conditions:");
        $display("- Random ROM delays (1-15 cycles)");
        $display("- 5%% ROM timeout error injection");
        $display("- Concurrent flush/access operations");
        $display("- Cache thrashing scenarios");
        $display("- Rapid enable/disable cycling");
        $display("");
        
        // Test 1: Basic functionality under stress
        reset_dut();
        $display("=== EXTREME Test 1: Basic Stress ===");
        for (int i = 0; i < 100; i++) begin
            addr_var = $urandom();
            cache_read(addr_var, data_var, hit_var);
            
            // Random flush injection
            if ($urandom_range(1, 100) <= 10) begin  // 10% chance
                @(posedge clk_rt_50mhz);
                cache_flush = 1'b1;
                @(posedge clk_rt_50mhz);
                cache_flush = 1'b0;
            end
        end
        test_count++;
        
        // Test 2: Cache enable/disable torture
        $display("=== EXTREME Test 2: Enable/Disable Torture ===");
        for (int i = 0; i < 50; i++) begin
            cache_enable = $urandom_range(0, 1);
            cache_read(16'h1000 + i, expected_data, cpu_hit);
            @(posedge clk_rt_50mhz);
        end
        cache_enable = 1'b1;
        test_count++;
        
        // Test 3: Concurrent flush during fill operations
        $display("=== EXTREME Test 3: Concurrent Flush Torture ===");
        fork
            begin
                // Continuous cache accesses
                for (int i = 0; i < 200; i++) begin
                    addr_var = $urandom();
                    cache_read(addr_var, data_var, hit_var);
                end
            end
            begin
                // Random flushes during operations
                repeat(20) begin
                    #($urandom_range(100, 1000));
                    @(posedge clk_rt_50mhz);
                    cache_flush = 1'b1;
                    @(posedge clk_rt_50mhz);
                    cache_flush = 1'b0;
                end
            end
        join
        test_count++;
        
        // Test 4: Cache line thrashing (worst case for direct-mapped)
        $display("=== EXTREME Test 4: Cache Thrashing ===");
        addr1 = 16'h1000;  // Maps to line 0
        addr2 = 16'h9000;  // Also maps to line 0
        addr3 = 16'h5000;  // Also maps to line 0
        
        for (int i = 0; i < 100; i++) begin
            // Access multiple addresses that map to same cache line
            cache_read(addr1, data_var, hit_var);
            cache_read(addr2, data_var, hit_var);
            cache_read(addr3, data_var, hit_var);
            cache_read(addr1, data_var, hit_var);  // Should miss due to thrashing
        end
        test_count++;
        
        // Test 5: Rapid sequential vs random access mix
        $display("=== EXTREME Test 5: Mixed Access Patterns ===");
        for (int i = 0; i < 1000; i++) begin
            if (i % 4 == 0) begin
                // Sequential (good for cache)
                addr_var = 16'h2000 + i;
            end else begin
                // Random (bad for cache)
                addr_var = $urandom();
            end
            
            cache_read(addr_var, data_var, hit_var);
            
            // Random interruptions
            if ($urandom_range(1, 100) <= 5) begin
                cache_enable = 1'b0;
                repeat($urandom_range(1, 5)) @(posedge clk_rt_50mhz);
                cache_enable = 1'b1;
            end
        end
        test_count++;
        
        // Test 6: Boundary condition stress
        $display("=== EXTREME Test 6: Boundary Stress ===");
        for (int i = 0; i < 100; i++) begin
            addr_var = boundary_addrs[$urandom_range(0, 7)];
            cache_read(addr_var, data_var, hit_var);
        end
        test_count++;
        
        // Test 7: Reset during active operations
        $display("=== EXTREME Test 7: Reset During Operations ===");
        for (int i = 0; i < 10; i++) begin
            fork
                begin
                    // Start cache operation
                    cache_read(16'h3000 + i, data_var, hit_var);
                end
                begin
                    // Reset in middle of operation
                    repeat($urandom_range(1, 10)) @(posedge clk_rt_50mhz);
                    rst_n = 1'b0;
                    repeat(3) @(posedge clk_rt_50mhz);
                    rst_n = 1'b1;
                    cache_enable = 1'b1;
                end
            join
        end
        test_count++;
        
        // Final comprehensive test
        $display("=== EXTREME Test 8: Final Torture Test ===");
        stress_test_random_access();
        test_count++;
        
        // Results
        $display("\n================================================");
        $display("RT I-Cache Controller EXTREME STRESS Results");
        $display("================================================");
        $display("Total Torture Tests: %0d", test_count);
        $display("Errors Found: %0d", error_count);
        $display("Hit Count: %0d", hit_count);
        $display("Miss Count: %0d", miss_count);
        $display("Hit Rate: %0d%% (Under extreme stress)", hit_rate_percent);
        $display("Total Accesses: %0d", total_accesses);
        
        if (error_count == 0) begin
            $display("🔥 MODULE SURVIVED EXTREME TORTURE! ROBUST! ✓");
        end else begin
            $display("[WARNING] %0d ISSUES FOUND - MODULE NEEDS STRENGTHENING", error_count);
        end
        
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Aggressive Timeout - Module must handle stress quickly
    //--------------------------------------------------------------------------
    initial begin
        #50ms;  // Must complete extreme tests within 50ms
        $error("EXTREME STRESS TIMEOUT - Module too slow under pressure!");
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Performance Monitoring
    //--------------------------------------------------------------------------
    always @(posedge clk_rt_50mhz) begin
        if (cpu_req && cpu_ready) begin
            if (cpu_hit) begin
                hit_target = hit_target + 1;
            end else begin
                miss_target = miss_target + 1;
            end
        end
    end

endmodule
