`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: MAKu Development Team
// 
// Create Date: 12/29/2024
// Design Name: MAKu Microcontroller
// Module Name: clock_management_unit_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T (Simulation)
// Tool Versions: Vivado 2024.2
// Description: Comprehensive testbench for Clock Management Unit
//              Tests PLL lock, reset sync, power management, stress conditions
// 
// Dependencies: clock_management_unit.sv
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - SystemVerilog 2012 compliant
// - Tests all clock domains and reset synchronization
// - Validates power management and clock enables
// 
//////////////////////////////////////////////////////////////////////////////////

module clock_management_unit_tb;

    // Test parameters
    localparam CLK_PERIOD_100M = 10;   // 100MHz = 10ns period
    localparam CLK_PERIOD_50M = 20;    // 50MHz = 20ns period
    localparam CLK_PERIOD_25M = 40;    // 25MHz = 40ns period
    localparam CLK_PERIOD_10M = 100;   // 10MHz = 100ns period
    
    // All testbench signals declared at top
    logic        clk_in_100mhz;
    logic        ext_reset_n;
    logic        clk_rt_50mhz;
    logic        clk_gp_100mhz;
    logic        clk_periph_25mhz;
    logic        clk_debug_10mhz;
    logic        clk_en_rt;
    logic        clk_en_gp;
    logic        clk_en_periph;
    logic        clk_en_debug;
    logic        rst_n_rt;
    logic        rst_n_gp;
    logic        rst_n_periph;
    logic        rst_n_debug;
    logic        pll_locked;
    logic        clocks_stable;
    logic        power_down_rt;
    logic        power_down_gp;
    logic        power_down_periph;
    logic [31:0] rt_clk_count;
    logic [31:0] gp_clk_count;
    
    // Test control variables
    integer test_count;
    integer error_count;
    integer i, j;
    logic [31:0] rt_count_start;
    logic [31:0] gp_count_start;
    logic [31:0] rt_count_end;
    logic [31:0] gp_count_end;
    real rt_freq_measured;
    real gp_freq_measured;
    logic pll_lock_detected;
    logic clocks_stable_detected;
    integer reset_test_cycles;
    integer power_test_cycles;
    
    //--------------------------------------------------------------------------
    // Device Under Test Instantiation
    //--------------------------------------------------------------------------
    clock_management_unit dut (
        .clk_in_100mhz(clk_in_100mhz),
        .ext_reset_n(ext_reset_n),
        .clk_rt_50mhz(clk_rt_50mhz),
        .clk_gp_100mhz(clk_gp_100mhz),
        .clk_periph_25mhz(clk_periph_25mhz),
        .clk_debug_10mhz(clk_debug_10mhz),
        .clk_en_rt(clk_en_rt),
        .clk_en_gp(clk_en_gp),
        .clk_en_periph(clk_en_periph),
        .clk_en_debug(clk_en_debug),
        .rst_n_rt(rst_n_rt),
        .rst_n_gp(rst_n_gp),
        .rst_n_periph(rst_n_periph),
        .rst_n_debug(rst_n_debug),
        .pll_locked(pll_locked),
        .clocks_stable(clocks_stable),
        .power_down_rt(power_down_rt),
        .power_down_gp(power_down_gp),
        .power_down_periph(power_down_periph),
        .rt_clk_count(rt_clk_count),
        .gp_clk_count(gp_clk_count)
    );
    
    //--------------------------------------------------------------------------
    // Initialization
    //--------------------------------------------------------------------------
    initial begin
        test_count = 0;
        error_count = 0;
        reset_test_cycles = 100;
        power_test_cycles = 50;
        pll_lock_detected = 1'b0;
        clocks_stable_detected = 1'b0;
        rt_freq_measured = 0.0;
        gp_freq_measured = 0.0;
    end
    
    //--------------------------------------------------------------------------
    // Input Clock Generation (100MHz)
    //--------------------------------------------------------------------------
    initial begin
        clk_in_100mhz = 1'b0;
        forever #(CLK_PERIOD_100M/2) clk_in_100mhz = ~clk_in_100mhz;
    end
    
    //--------------------------------------------------------------------------
    // Test Tasks
    //--------------------------------------------------------------------------
    
    task reset_system;
        begin
            $display("=== RESET: System Reset ===");
            power_down_rt = 1'b0;
            power_down_gp = 1'b0;
            power_down_periph = 1'b0;
            ext_reset_n = 1'b0;
            
            repeat(10) @(posedge clk_in_100mhz);
            ext_reset_n = 1'b1;
            
            $display("Reset released, waiting for PLL lock...");
        end
    endtask
    
    task wait_for_pll_lock;
        begin
            $display("=== PLL_LOCK: Waiting for PLL Lock ===");
            
            fork
                begin
                    wait(pll_locked);
                    pll_lock_detected = 1'b1;
                    $display("PLL locked at time %0t", $time);
                end
                begin
                    #10us;  // 10 microsecond timeout
                    if (!pll_locked) begin
                        $error("PLL failed to lock within timeout");
                        error_count = error_count + 1;
                    end
                end
            join_any
            disable fork;
            
            test_count = test_count + 1;
        end
    endtask
    
    task wait_for_clocks_stable;
        begin
            $display("=== STABLE: Waiting for Clock Stability ===");
            
            fork
                begin
                    wait(clocks_stable);
                    clocks_stable_detected = 1'b1;
                    $display("Clocks stable at time %0t", $time);
                end
                begin
                    #15us;  // 15 microsecond timeout
                    if (!clocks_stable) begin
                        $error("Clocks failed to stabilize within timeout");
                        error_count = error_count + 1;
                    end
                end
            join_any
            disable fork;
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_reset_synchronization;
        begin
            $display("=== RESET_SYNC: Reset Synchronization Test ===");
            
            // Check that all resets are initially deasserted when clocks stable
            if (!clocks_stable) begin
                $error("Clocks not stable before reset sync test");
                error_count = error_count + 1;
                return;
            end
            
            // Wait longer for all domain synchronizers to complete
            // 10MHz domain is slowest, needs more cycles (10x slower than 100MHz)
            repeat(50) @(posedge clk_gp_100mhz);
            
            if (!rst_n_rt || !rst_n_gp || !rst_n_periph || !rst_n_debug) begin
                $error("Not all resets synchronized properly");
                $display("  rst_n_rt=%b, rst_n_gp=%b, rst_n_periph=%b, rst_n_debug=%b",
                        rst_n_rt, rst_n_gp, rst_n_periph, rst_n_debug);
                error_count = error_count + 1;
            end else begin
                $display("All domain resets synchronized correctly");
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_clock_frequencies;
        begin
            $display("=== FREQ: Clock Frequency Verification ===");
            
            if (!clocks_stable) begin
                $error("Clocks not stable for frequency test");
                error_count = error_count + 1;
                return;
            end
            
            // Sample RT-Core clock frequency
            rt_count_start = rt_clk_count;
            #1us;  // Wait 1 microsecond
            rt_count_end = rt_clk_count;
            rt_freq_measured = real'(rt_count_end - rt_count_start) * 1.0e6;  // Convert to Hz
            
            // Sample GP-Core clock frequency  
            gp_count_start = gp_clk_count;
            #1us;  // Wait 1 microsecond
            gp_count_end = gp_clk_count;
            gp_freq_measured = real'(gp_count_end - gp_count_start) * 1.0e6;  // Convert to Hz
            
            $display("Measured RT-Core frequency: %0.1f MHz", rt_freq_measured / 1.0e6);
            $display("Measured GP-Core frequency: %0.1f MHz", gp_freq_measured / 1.0e6);
            
            // Check RT-Core frequency (50MHz ±5%)
            if (rt_freq_measured < 47.5e6 || rt_freq_measured > 52.5e6) begin
                $error("RT-Core frequency out of range: %0.1f MHz", rt_freq_measured / 1.0e6);
                error_count = error_count + 1;
            end
            
            // Check GP-Core frequency (100MHz ±5%)
            if (gp_freq_measured < 95.0e6 || gp_freq_measured > 105.0e6) begin
                $error("GP-Core frequency out of range: %0.1f MHz", gp_freq_measured / 1.0e6);
                error_count = error_count + 1;
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_clock_enables;
        begin
            $display("=== CLK_EN: Clock Enable Verification ===");
            
            // All clock enables should be high when PLL locked and no power down
            if (!clk_en_rt || !clk_en_gp || !clk_en_periph || !clk_en_debug) begin
                $error("Clock enables not asserted correctly");
                $display("  clk_en_rt=%b, clk_en_gp=%b, clk_en_periph=%b, clk_en_debug=%b",
                        clk_en_rt, clk_en_gp, clk_en_periph, clk_en_debug);
                error_count = error_count + 1;
            end else begin
                $display("All clock enables working correctly");
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_power_management;
        begin
            $display("=== POWER: Power Management Test ===");
            
            // Test RT-Core power down
            rt_count_start = rt_clk_count;
            power_down_rt = 1'b1;
            repeat(10) @(posedge clk_gp_100mhz);
            
            if (clk_en_rt) begin
                $error("RT-Core clock enable not disabled during power down");
                error_count = error_count + 1;
            end else begin
                $display("RT-Core power down working");
            end
            
            power_down_rt = 1'b0;
            repeat(5) @(posedge clk_gp_100mhz);
            
            // Test GP-Core power down
            gp_count_start = gp_clk_count;
            power_down_gp = 1'b1;
            repeat(10) @(posedge clk_rt_50mhz);
            
            if (clk_en_gp) begin
                $error("GP-Core clock enable not disabled during power down");
                error_count = error_count + 1;
            end else begin
                $display("GP-Core power down working");
            end
            
            power_down_gp = 1'b0;
            repeat(5) @(posedge clk_rt_50mhz);
            
            // Test peripheral power down
            power_down_periph = 1'b1;
            repeat(10) @(posedge clk_gp_100mhz);
            
            if (clk_en_periph) begin
                $error("Peripheral clock enable not disabled during power down");
                error_count = error_count + 1;
            end else begin
                $display("Peripheral power down working");
            end
            
            power_down_periph = 1'b0;
            repeat(5) @(posedge clk_gp_100mhz);
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_clock_counters;
        begin
            $display("=== COUNTERS: Clock Counter Test ===");
            
            rt_count_start = rt_clk_count;
            gp_count_start = gp_clk_count;
            
            repeat(100) @(posedge clk_gp_100mhz);
            
            rt_count_end = rt_clk_count;
            gp_count_end = gp_clk_count;
            
            $display("RT counter increased by: %0d", rt_count_end - rt_count_start);
            $display("GP counter increased by: %0d", gp_count_end - gp_count_start);
            
            // GP should increment ~2x faster than RT (100MHz vs 50MHz)
            if ((gp_count_end - gp_count_start) < (rt_count_end - rt_count_start)) begin
                $error("Clock counters not incrementing at expected rates");
                error_count = error_count + 1;
            end else begin
                $display("Clock counters working correctly");
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task stress_test_reset_cycles;
        begin
            $display("=== STRESS_RESET: Reset Cycle Stress Test ===");
            
            for (i = 0; i < reset_test_cycles; i = i + 1) begin
                ext_reset_n = 1'b0;
                repeat($random % 10 + 1) @(posedge clk_in_100mhz);
                ext_reset_n = 1'b1;
                repeat($random % 20 + 10) @(posedge clk_in_100mhz);
                
                if ((i % 10) == 0) begin
                    $display("Reset stress progress: %0d/%0d", i, reset_test_cycles);
                end
            end
            
            // Final stabilization
            repeat(100) @(posedge clk_in_100mhz);
            wait(clocks_stable);
            
            $display("Reset stress test completed");
            test_count = test_count + 1;
        end
    endtask
    
    task stress_test_power_cycles;
        begin
            $display("=== STRESS_POWER: Power Cycle Stress Test ===");
            
            for (i = 0; i < power_test_cycles; i = i + 1) begin
                // Random power down combinations
                power_down_rt = $random % 2;
                power_down_gp = $random % 2;
                power_down_periph = $random % 2;
                
                repeat($random % 20 + 5) @(posedge clk_gp_100mhz);
                
                // All power on
                power_down_rt = 1'b0;
                power_down_gp = 1'b0;
                power_down_periph = 1'b0;
                
                repeat(10) @(posedge clk_gp_100mhz);
                
                if ((i % 5) == 0) begin
                    $display("Power stress progress: %0d/%0d", i, power_test_cycles);
                end
            end
            
            $display("Power stress test completed");
            test_count = test_count + 1;
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("MAKu Clock Management Unit Testbench");
        $display("====================================");
        
        // Test 1: Reset and PLL lock
        reset_system();
        wait_for_pll_lock();
        wait_for_clocks_stable();
        
        // Test 2: Reset synchronization
        test_reset_synchronization();
        
        // Test 3: Clock frequency verification
        test_clock_frequencies();
        
        // Test 4: Clock enables
        test_clock_enables();
        
        // Test 5: Power management
        test_power_management();
        
        // Test 6: Clock counters
        test_clock_counters();
        
        // Test 7: Stress testing
        stress_test_reset_cycles();
        stress_test_power_cycles();
        
        // Final Results
        $display("====================================");
        $display("Test Results Summary");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        $display("PLL Locked: %b", pll_locked);
        $display("Clocks Stable: %b", clocks_stable);
        $display("RT Clock Count: %0d", rt_clk_count);
        $display("GP Clock Count: %0d", gp_clk_count);
        
        if (error_count == 0) begin
            $display("ALL TESTS PASSED! Clock Management Unit ready.");
        end else begin
            $display("%0d TESTS FAILED!", error_count);
        end
        
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Monitoring and Assertions
    //--------------------------------------------------------------------------
    
    // Monitor PLL lock transitions
    always @(posedge pll_locked) begin
        $display("INFO: PLL locked at time %0t", $time);
    end
    
    always @(negedge pll_locked) begin
        $display("WARNING: PLL lost lock at time %0t", $time);
    end
    
    // Monitor clock stability
    always @(posedge clocks_stable) begin
        $display("INFO: Clocks stabilized at time %0t", $time);
    end
    
    //--------------------------------------------------------------------------
    // Timeout Protection
    //--------------------------------------------------------------------------
    initial begin
        #50ms;  // 50 millisecond timeout
        $error("Testbench timeout!");
        $finish;
    end

endmodule
