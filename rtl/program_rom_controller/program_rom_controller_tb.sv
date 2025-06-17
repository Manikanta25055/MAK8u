`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/29/2024
// Design Name: MAKu Microcontroller
// Module Name: program_rom_controller_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T (Simulation)
// Tool Versions: Vivado 2024.2
// Description: Comprehensive testbench for Program ROM Controller
//              SystemVerilog 2012 compliant for Vivado
// 
// Dependencies: program_rom_controller.sv
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - Fixed SystemVerilog 2012 compliance issues
// - All declarations at top level
// - Vivado-compatible syntax
// 
//////////////////////////////////////////////////////////////////////////////////

module program_rom_controller_tb;

    // Test parameters
    localparam ADDR_WIDTH = 16;
    localparam DATA_WIDTH = 16;
    localparam ROM_SIZE = 65536;
    localparam CLK_PERIOD = 10;
    
    // Testbench signals - ALL DECLARED AT TOP
    logic                     clk;
    logic                     rst_n;
    logic                     rt_core_en;
    logic [ADDR_WIDTH-1:0]    rt_core_addr;
    logic [DATA_WIDTH-1:0]    rt_core_data;
    logic                     rt_core_valid;
    logic                     gp_core_en;
    logic [ADDR_WIDTH-1:0]    gp_core_addr;
    logic [DATA_WIDTH-1:0]    gp_core_data;
    logic                     gp_core_valid;
    logic                     rom_ready;
    logic [31:0]              access_count_rt;
    logic [31:0]              access_count_gp;
    
    // Test control variables - ALL DECLARED AT TOP
    integer test_count;
    integer error_count;
    integer stress_cycles;
    integer i, j;
    logic [ADDR_WIDTH-1:0] addr_temp;
    logic [ADDR_WIDTH-1:0] rt_addr_temp;
    logic [ADDR_WIDTH-1:0] gp_addr_temp;
    logic [DATA_WIDTH-1:0] expected_data;
    logic [DATA_WIDTH-1:0] memory_model [0:ROM_SIZE-1];
    logic [31:0] initial_rt_count;
    logic [31:0] initial_gp_count;
    integer stress_errors;
    logic [ADDR_WIDTH-1:0] invalid_addr;
    
    //--------------------------------------------------------------------------
    // Device Under Test Instantiation
    //--------------------------------------------------------------------------
    program_rom_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ROM_SIZE(ROM_SIZE),
        .MEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rt_core_en(rt_core_en),
        .rt_core_addr(rt_core_addr),
        .rt_core_data(rt_core_data),
        .rt_core_valid(rt_core_valid),
        .gp_core_en(gp_core_en),
        .gp_core_addr(gp_core_addr),
        .gp_core_data(gp_core_data),
        .gp_core_valid(gp_core_valid),
        .rom_ready(rom_ready),
        .access_count_rt(access_count_rt),
        .access_count_gp(access_count_gp)
    );
    
    //--------------------------------------------------------------------------
    // Initialization
    //--------------------------------------------------------------------------
    initial begin
        // Initialize all variables
        test_count = 0;
        error_count = 0;
        stress_cycles = 1000;  // Reduced for faster simulation
        stress_errors = 0;
        invalid_addr = ROM_SIZE + 100;
        
        // Initialize memory model
        for (i = 0; i < ROM_SIZE; i = i + 1) begin
            memory_model[i] = 16'hF000;
        end
        memory_model[0] = 16'h1100;
        memory_model[1] = 16'h1201;
        memory_model[2] = 16'h0112;
        memory_model[3] = 16'h91FD;
        memory_model[4] = 16'hE000;
    end
    
    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //--------------------------------------------------------------------------
    // Test Tasks
    //--------------------------------------------------------------------------
    
    task reset_dut;
        begin
            $display("=== RESET: System Reset ===");
            rt_core_en = 1'b0;
            rt_core_addr = 16'h0000;
            gp_core_en = 1'b0;
            gp_core_addr = 16'h0000;
            rst_n = 1'b0;
            
            repeat(5) @(posedge clk);
            rst_n = 1'b1;
            repeat(3) @(posedge clk);
            
            if (!rom_ready) begin
                $error("ROM not ready after reset");
                error_count = error_count + 1;
            end else begin
                $display("ROM ready signal asserted");
            end
        end
    endtask
    
    task rt_core_read;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] expected;
        begin
            @(posedge clk);
            rt_core_en = 1'b1;
            rt_core_addr = addr;
            
            @(posedge clk);
            rt_core_en = 1'b0;
            
            if (!rt_core_valid) begin
                $error("RT-Core valid signal not asserted");
                error_count = error_count + 1;
            end else if (rt_core_data !== expected) begin
                $error("RT-Core read mismatch: Addr=0x%04X Expected=0x%04X Got=0x%04X", 
                       addr, expected, rt_core_data);
                error_count = error_count + 1;
            end else begin
                $display("RT-Core read OK: Addr=0x%04X Data=0x%04X", addr, rt_core_data);
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task gp_core_read;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] expected;
        begin
            @(posedge clk);
            gp_core_en = 1'b1;
            gp_core_addr = addr;
            
            @(posedge clk);
            gp_core_en = 1'b0;
            
            if (!gp_core_valid) begin
                $error("GP-Core valid signal not asserted");
                error_count = error_count + 1;
            end else if (gp_core_data !== expected) begin
                $error("GP-Core read mismatch: Addr=0x%04X Expected=0x%04X Got=0x%04X", 
                       addr, expected, gp_core_data);
                error_count = error_count + 1;
            end else begin
                $display("GP-Core read OK: Addr=0x%04X Data=0x%04X", addr, gp_core_data);
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task dual_core_read;
        input [ADDR_WIDTH-1:0] rt_addr;
        input [DATA_WIDTH-1:0] rt_expected;
        input [ADDR_WIDTH-1:0] gp_addr;
        input [DATA_WIDTH-1:0] gp_expected;
        begin
            @(posedge clk);
            rt_core_en = 1'b1;
            rt_core_addr = rt_addr;
            gp_core_en = 1'b1;
            gp_core_addr = gp_addr;
            
            @(posedge clk);
            rt_core_en = 1'b0;
            gp_core_en = 1'b0;
            
            if (!rt_core_valid || !gp_core_valid) begin
                $error("Dual access: Valid signals not asserted");
                error_count = error_count + 1;
            end else begin
                if (rt_core_data !== rt_expected) begin
                    $error("Dual RT mismatch: Addr=0x%04X Expected=0x%04X Got=0x%04X", 
                           rt_addr, rt_expected, rt_core_data);
                    error_count = error_count + 1;
                end
                if (gp_core_data !== gp_expected) begin
                    $error("Dual GP mismatch: Addr=0x%04X Expected=0x%04X Got=0x%04X", 
                           gp_addr, gp_expected, gp_core_data);
                    error_count = error_count + 1;
                end
                if ((rt_core_data === rt_expected) && (gp_core_data === gp_expected)) begin
                    $display("Dual access OK: RT[0x%04X]=0x%04X GP[0x%04X]=0x%04X", 
                             rt_addr, rt_core_data, gp_addr, gp_core_data);
                end
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_bounds_checking;
        begin
            $display("=== BOUNDS: Bounds Checking ===");
            
            @(posedge clk);
            rt_core_en = 1'b1;
            rt_core_addr = invalid_addr;
            
            @(posedge clk);
            rt_core_en = 1'b0;
            
            if (rt_core_data !== 16'hF000) begin
                $error("Bounds check failed: Expected NOP for invalid address");
                error_count = error_count + 1;
            end else begin
                $display("Bounds checking works correctly");
            end
            
            test_count = test_count + 1;
        end
    endtask
    
    task test_access_counters;
        begin
            $display("=== COUNTERS: Access Counter Verification ===");
            
            initial_rt_count = access_count_rt;
            initial_gp_count = access_count_gp;
            
            rt_core_read(16'h0000, memory_model[16'h0000]);
            rt_core_read(16'h0001, memory_model[16'h0001]);
            gp_core_read(16'h0002, memory_model[16'h0002]);
            
            if (access_count_rt !== (initial_rt_count + 2)) begin
                $error("RT access counter incorrect: Expected %0d, Got %0d", 
                       initial_rt_count + 2, access_count_rt);
                error_count = error_count + 1;
            end
            
            if (access_count_gp !== (initial_gp_count + 1)) begin
                $error("GP access counter incorrect: Expected %0d, Got %0d", 
                       initial_gp_count + 1, access_count_gp);
                error_count = error_count + 1;
            end
            
            $display("Access counters OK - RT: %0d, GP: %0d", access_count_rt, access_count_gp);
        end
    endtask
    
    task stress_test_high_frequency;
        begin
            $display("=== STRESS: High-Frequency Access Test ===");
            
            stress_errors = 0;
            
            for (i = 0; i < 100; i = i + 1) begin
                addr_temp = $random % 100;
                
                @(posedge clk);
                rt_core_en = 1'b1;
                rt_core_addr = addr_temp;
                gp_core_en = 1'b1;
                gp_core_addr = addr_temp + 1;
                
                @(posedge clk);
                rt_core_en = 1'b0;
                gp_core_en = 1'b0;
                
                if (!rt_core_valid || !gp_core_valid) begin
                    stress_errors = stress_errors + 1;
                end
            end
            
            if (stress_errors == 0) begin
                $display("High-frequency stress test passed (100 accesses)");
            end else begin
                $error("High-frequency stress test failed: %0d errors", stress_errors);
                error_count = error_count + stress_errors;
            end
        end
    endtask
    
    task verify_memory_pattern;
        begin
            $display("=== PATTERN: Memory Pattern Verification ===");
            
            rt_core_read(16'h0000, 16'h1100);
            rt_core_read(16'h0001, 16'h1201);
            rt_core_read(16'h0002, 16'h0112);
            rt_core_read(16'h0003, 16'h91FD);
            rt_core_read(16'h0004, 16'hE000);
            
            gp_core_read(16'h0010, 16'hF000);
            gp_core_read(16'h0100, 16'hF000);
            gp_core_read(16'hFFFF, 16'hF000);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("MAKu Program ROM Controller Testbench");
        $display("=====================================");
        
        reset_dut();
        
        $display("=== BASIC: Basic Single-Core Reads ===");
        rt_core_read(16'h0000, memory_model[16'h0000]);
        gp_core_read(16'h0001, memory_model[16'h0001]);
        
        $display("=== DUAL: Dual-Core Simultaneous Access ===");
        dual_core_read(16'h0000, memory_model[16'h0000], 16'h0001, memory_model[16'h0001]);
        dual_core_read(16'h0002, memory_model[16'h0002], 16'h0003, memory_model[16'h0003]);
        
        verify_memory_pattern();
        test_bounds_checking();
        test_access_counters();
        stress_test_high_frequency();
        
        $display("=== MAX_STRESS: Maximum Stress Test ===");
        for (i = 0; i < stress_cycles; i = i + 1) begin
            rt_addr_temp = $random % ROM_SIZE;
            gp_addr_temp = $random % ROM_SIZE;
            dual_core_read(rt_addr_temp, memory_model[rt_addr_temp], 
                          gp_addr_temp, memory_model[gp_addr_temp]);
            
            if ((i % 100) == 0) begin
                $display("Stress progress: %0d/%0d", i, stress_cycles);
            end
        end
        
        $display("=====================================");
        $display("Test Results Summary");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        $display("RT Access Count: %0d", access_count_rt);
        $display("GP Access Count: %0d", access_count_gp);
        
        if (error_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("%0d TESTS FAILED!", error_count);
        end
        
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Timeout Protection
    //--------------------------------------------------------------------------
    initial begin
        #10ms;
        $error("Testbench timeout!");
        $finish;
    end

endmodule
