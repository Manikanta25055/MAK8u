`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/29/2024
// Design Name: MAKu Microcontroller
// Module Name: reset_controller_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T (Simulation)
// Tool Versions: Vivado 2024.2
// Description: Comprehensive testbench for Reset Controller
//              Tests reset sequencing, cause detection, timing
// 
// Dependencies: reset_controller.sv
// 
// Revision:
// Revision 0.02 - Fixed timing and sequence testing
// Additional Comments:
// - SystemVerilog 2012 compliant
// - Tests all reset sources and sequencing
// 
//////////////////////////////////////////////////////////////////////////////////

module reset_controller_tb;

    // Test parameters
    localparam CLK_PERIOD_100M = 10;
    localparam CLK_PERIOD_50M = 20;
    localparam CLK_PERIOD_25M = 40;
    localparam CLK_PERIOD_10M = 100;
    
    // All testbench signals declared at top
    logic        clk_rt_50mhz;
    logic        clk_gp_100mhz;
    logic        clk_periph_25mhz;
    logic        clk_debug_10mhz;
    logic        ext_reset_n;
    logic        por_reset_n;
    logic        pll_locked;
    logic        clocks_stable;
    logic        sw_reset_req;
    logic        rt_core_reset_req;
    logic        gp_core_reset_req;
    logic        periph_reset_req;
    logic        watchdog_reset;
    logic        watchdog_en;
    logic        rt_core_halted;
    logic        gp_core_halted;
    logic        rst_n_system;
    logic        rst_n_rt_core;
    logic        rst_n_gp_core;
    logic        rst_n_peripherals;
    logic        rst_n_memory;
    logic        rst_n_debug;
    logic [2:0]  reset_cause;
    logic        reset_sequence_done;
    logic        cores_ready;
    logic [7:0]  reset_hold_cycles;
    logic        quick_reset_en;
    logic [15:0] reset_counter;
    logic [31:0] uptime_counter;
    
    // Test control variables
    integer test_count;
    integer error_count;
    integer i, j;
    logic [2:0] expected_cause;
    logic [31:0] uptime_start;
    logic [31:0] uptime_end;
    integer sequence_test_count;
    integer reset_type;
    
    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial clk_gp_100mhz = 0;
    always #(CLK_PERIOD_100M/2) clk_gp_100mhz = ~clk_gp_100mhz;
    
    initial clk_rt_50mhz = 0;
    always #(CLK_PERIOD_50M/2) clk_rt_50mhz = ~clk_rt_50mhz;
    
    initial clk_periph_25mhz = 0;
    always #(CLK_PERIOD_25M/2) clk_periph_25mhz = ~clk_periph_25mhz;
    
    initial clk_debug_10mhz = 0;
    always #(CLK_PERIOD_10M/2) clk_debug_10mhz = ~clk_debug_10mhz;
    
    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    reset_controller dut (
        .clk_rt_50mhz(clk_rt_50mhz),
        .clk_gp_100mhz(clk_gp_100mhz),
        .clk_periph_25mhz(clk_periph_25mhz),
        .clk_debug_10mhz(clk_debug_10mhz),
        .ext_reset_n(ext_reset_n),
        .por_reset_n(por_reset_n),
        .pll_locked(pll_locked),
        .clocks_stable(clocks_stable),
        .sw_reset_req(sw_reset_req),
        .rt_core_reset_req(rt_core_reset_req),
        .gp_core_reset_req(gp_core_reset_req),
        .periph_reset_req(periph_reset_req),
        .watchdog_reset(watchdog_reset),
        .watchdog_en(watchdog_en),
        .rt_core_halted(rt_core_halted),
        .gp_core_halted(gp_core_halted),
        .rst_n_system(rst_n_system),
        .rst_n_rt_core(rst_n_rt_core),
        .rst_n_gp_core(rst_n_gp_core),
        .rst_n_peripherals(rst_n_peripherals),
        .rst_n_memory(rst_n_memory),
        .rst_n_debug(rst_n_debug),
        .reset_cause(reset_cause),
        .reset_sequence_done(reset_sequence_done),
        .cores_ready(cores_ready),
        .reset_hold_cycles(reset_hold_cycles),
        .quick_reset_en(quick_reset_en),
        .reset_counter(reset_counter),
        .uptime_counter(uptime_counter)
    );
    
    //--------------------------------------------------------------------------
    // Test Tasks
    //--------------------------------------------------------------------------
    task reset_all_inputs;
        begin
            ext_reset_n = 1'b1;
            por_reset_n = 1'b1;
            pll_locked = 1'b0;
            clocks_stable = 1'b0;
            sw_reset_req = 1'b0;
            rt_core_reset_req = 1'b0;
            gp_core_reset_req = 1'b0;
            periph_reset_req = 1'b0;
            watchdog_reset = 1'b0;
            watchdog_en = 1'b0;
            rt_core_halted = 1'b0;
            gp_core_halted = 1'b0;
            reset_hold_cycles = 8'h20;  // Default hold cycles
            quick_reset_en = 1'b0;
            
            // Initialize counters
            test_count = 0;
            error_count = 0;
        end
    endtask
    
    task simulate_pll_lock_sequence;
        begin
            // Simulate typical PLL lock and clock stability timing
            repeat(5) @(posedge clk_gp_100mhz);
            pll_locked = 1'b1;
            repeat(5) @(posedge clk_gp_100mhz);
            clocks_stable = 1'b1;
        end
    endtask
    
    task wait_for_reset_completion;
        begin
            // Wait for reset sequence to complete with timeout
            fork
                begin
                    wait(reset_sequence_done);
                end
                begin
                    repeat(500) @(posedge clk_gp_100mhz);  // Shorter timeout
                    $error("Reset sequence timeout");
                    error_count = error_count + 1;
                end
            join_any
            disable fork;
        end
    endtask
    
    task test_reset_cause(input [2:0] expected, input string reset_name);
        begin
            $display("=== CAUSE: Testing %s Reset ===", reset_name);
            
            reset_all_inputs();
            repeat(10) @(posedge clk_gp_100mhz);
            
            // Apply specific reset
            case (expected)
                3'b000: por_reset_n = 1'b0;     // Power-on
                3'b001: ext_reset_n = 1'b0;     // External
                3'b010: sw_reset_req = 1'b1;    // Software
                3'b100: rt_core_reset_req = 1'b1; // Core request
                default: begin
                    $error("Unknown reset type: %0d", expected);
                    error_count = error_count + 1;
                    return;
                end
            endcase
            
            // Wait for reset detection
            repeat(5) @(posedge clk_gp_100mhz);
            
            // Release reset source
            por_reset_n = 1'b1;
            ext_reset_n = 1'b1;
            sw_reset_req = 1'b0;
            rt_core_reset_req = 1'b0;
            
            // Simulate PLL lock sequence
            fork
                simulate_pll_lock_sequence();
            join_none
            
            // Wait for completion
            wait_for_reset_completion();
            
            // Check reset cause after sequence completion
            repeat(5) @(posedge clk_gp_100mhz);
            
            if (reset_cause !== expected) begin
                $error("%s reset cause incorrect: Expected %0d, Got %0d", 
                       reset_name, expected, reset_cause);
                error_count = error_count + 1;
            end else begin
                $display("%s reset cause correct: %0d", reset_name, reset_cause);
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_watchdog_reset;
        begin
            $display("=== WATCHDOG: Watchdog Reset Test ===");
            
            reset_all_inputs();
            watchdog_en = 1'b1;
            repeat(10) @(posedge clk_gp_100mhz);
            
            // Trigger watchdog reset
            watchdog_reset = 1'b1;
            repeat(5) @(posedge clk_gp_100mhz);
            watchdog_reset = 1'b0;
            
            // Simulate PLL lock sequence
            fork
                simulate_pll_lock_sequence();
            join_none
            
            // Wait for completion
            wait_for_reset_completion();
            
            // Check reset cause
            repeat(5) @(posedge clk_gp_100mhz);
            
            if (reset_cause !== 3'b011) begin  // WATCHDOG
                $error("Watchdog reset cause not detected correctly: Expected 3, Got %0d", reset_cause);
                error_count = error_count + 1;
            end else begin
                $display("Watchdog reset working correctly");
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_reset_sequencing;
        begin
            $display("=== SEQUENCE: Reset Sequencing Test ===");
            
            reset_all_inputs();
            por_reset_n = 1'b0;  // Start with POR
            
            repeat(5) @(posedge clk_gp_100mhz);
            por_reset_n = 1'b1;
            
            // Monitor reset release sequence
            fork begin
                // Memory reset release check
                wait(!rst_n_memory);
                wait(rst_n_memory);
                $display("Memory reset released");
                
                // Debug reset release check
                wait(rst_n_debug);
                $display("Debug reset released");
                
                // Peripheral reset release check
                wait(rst_n_peripherals);
                $display("Peripheral reset released");
                
                // RT-Core reset release check
                wait(rst_n_rt_core);
                $display("RT-Core reset released");
                
                // GP-Core reset release check
                wait(rst_n_gp_core);
                $display("GP-Core reset released");
                
                // Final completion check
                wait(reset_sequence_done);
                $display("Reset sequence completed successfully");
            end join_none
            
            // Simulate PLL lock sequence
            fork
                simulate_pll_lock_sequence();
            join_none
            
            // Wait for completion
            wait_for_reset_completion();
            
            // Allow time for reset synchronizers to release (3 cycles per domain)
            repeat(10) @(posedge clk_gp_100mhz);
            
            // Verify all resets are released
            if (!rst_n_memory || !rst_n_debug || !rst_n_peripherals || 
                !rst_n_rt_core || !rst_n_gp_core) begin
                $error("Not all resets released after sequence");
                error_count = error_count + 1;
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_quick_reset_mode;
        begin
            $display("=== QUICK: Quick Reset Mode Test ===");
            
            quick_reset_en = 1'b1;
            reset_all_inputs();
            sw_reset_req = 1'b1;
            
            repeat(5) @(posedge clk_gp_100mhz);
            sw_reset_req = 1'b0;
            
            fork
                simulate_pll_lock_sequence();
            join_none
            
            // Wait for completion with shorter timeout for quick mode
            fork
                begin
                    wait(reset_sequence_done);
                end
                begin
                    repeat(1000) @(posedge clk_gp_100mhz);  // Shorter timeout
                    $error("Quick reset mode failed to complete");
                    error_count = error_count + 1;
                end
            join_any
            disable fork;
            
            if (cores_ready) begin
                $display("Quick reset mode working");
            end
            
            quick_reset_en = 1'b0;  // Reset to default
            test_count = test_count + 1;
        end
    endtask
    
    task test_uptime_counter;
        begin
            $display("=== UPTIME: Uptime Counter Test ===");
            
            // Ensure system is out of reset
            wait(cores_ready);
            
            uptime_start = uptime_counter;
            repeat(100) @(posedge clk_gp_100mhz);
            uptime_end = uptime_counter;
            
            if ((uptime_end - uptime_start) < 90 || (uptime_end - uptime_start) > 110) begin
                $error("Uptime counter not incrementing correctly: Delta=%0d", 
                       uptime_end - uptime_start);
                error_count = error_count + 1;
            end else begin
                $display("Uptime counter working: Delta=%0d", uptime_end - uptime_start);
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_reset_priority;
        begin
            $display("=== PRIORITY: Reset Priority Test ===");
            
            reset_all_inputs();
            
            // Apply multiple reset sources simultaneously
            por_reset_n = 1'b0;      // Highest priority
            ext_reset_n = 1'b0;
            sw_reset_req = 1'b1;
            
            repeat(5) @(posedge clk_gp_100mhz);
            
            // Release all resets
            por_reset_n = 1'b1;
            ext_reset_n = 1'b1;
            sw_reset_req = 1'b0;
            
            fork
                simulate_pll_lock_sequence();
            join_none
            
            wait_for_reset_completion();
            
            if (reset_cause !== 3'b000) begin  // Should be POR
                $error("Reset priority incorrect: Expected POR, Got %0d", reset_cause);
                error_count = error_count + 1;
            end else begin
                $display("Reset priority working correctly");
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task stress_test_reset_cycles;
        begin
            $display("=== STRESS: Multiple Reset Cycles ===");
            
            for (i = 0; i < 5; i++) begin
                reset_all_inputs();
                
                // Random reset type
                case (i % 3)
                    0: ext_reset_n = 1'b0;
                    1: sw_reset_req = 1'b1;
                    2: rt_core_reset_req = 1'b1;
                endcase
                
                repeat(3) @(posedge clk_gp_100mhz);
                
                // Release reset
                ext_reset_n = 1'b1;
                sw_reset_req = 1'b0;
                rt_core_reset_req = 1'b0;
                
                fork
                    simulate_pll_lock_sequence();
                join_none
                
                wait_for_reset_completion();
                
                // Wait for cores to be ready (synchronizers need time)
                repeat(10) @(posedge clk_gp_100mhz);
                
                if (!cores_ready) begin
                    $error("Stress test iteration %0d failed", i);
                    error_count = error_count + 1;
                end
            end
            
            $display("Stress test completed");
            test_count = test_count + 1;
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("MAKu Reset Controller Testbench");
        $display("=================================");
        
        // Initialize all inputs
        reset_all_inputs();
        
        // Test 1: Power-on reset
        test_reset_cause(3'b000, "Power-On");
        
        // Test 2: External reset
        test_reset_cause(3'b001, "External");
        
        // Test 3: Software reset
        test_reset_cause(3'b010, "Software");
        
        // Test 4: Watchdog reset
        test_watchdog_reset();
        
        // Test 5: Core request reset
        test_reset_cause(3'b100, "Core-Request");
        
        // Test 6: Reset sequencing
        test_reset_sequencing();
        
        // Test 7: Quick reset mode
        test_quick_reset_mode();
        
        // Test 8: Uptime counter
        test_uptime_counter();
        
        // Test 9: Reset priority
        test_reset_priority();
        
        // Test 10: Stress testing
        stress_test_reset_cycles();
        
        // Final Results
        $display("=================================");
        $display("Test Results Summary");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        $display("Last Reset Cause: %0d", reset_cause);
        $display("Cores Ready: %b", cores_ready);
        $display("Uptime: %0d cycles", uptime_counter);
        
        if (error_count == 0) begin
            $display("ALL TESTS PASSED! Reset Controller ready.");
        end else begin
            $display("%0d TESTS FAILED!", error_count);
        end
        
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Timeout Protection
    //--------------------------------------------------------------------------
    initial begin
        #50ms;
        $error("Testbench timeout!");
        $finish;
    end

endmodule
