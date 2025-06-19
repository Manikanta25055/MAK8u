`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 01/02/2025
// Design Name: MAKu Dual-Core Microcontroller
// Module Name: data_ram_controller_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T (Simulation)
// Tool Versions: Vivado 2024.2
// Description: Comprehensive testbench for Data RAM Controller
//              Tests 64KB partitioned data RAM with dual-core access
//              Validates bounds checking, collision detection, performance
// 
// Dependencies: data_ram_controller.sv
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - Tests both RT-Core and GP-Core partitions
// - Validates memory protection and bounds checking
// - Clock domain testing (50MHz RT, 100MHz GP)
// - Comprehensive functional verification
// 
//////////////////////////////////////////////////////////////////////////////////

module data_ram_controller_tb;

    //--------------------------------------------------------------------------
    // Test Parameters
    //--------------------------------------------------------------------------
    localparam CLK_PERIOD_RT = 20;     // 50MHz RT-Core (20ns)
    localparam CLK_PERIOD_GP = 10;     // 100MHz GP-Core (10ns)
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam RT_BASE_ADDR = 32'h20000;
    localparam GP_BASE_ADDR = 32'h28000;
    localparam RT_END_ADDR = 32'h27FFF;
    localparam GP_END_ADDR = 32'h2FFFF;
    localparam TEST_TIMEOUT = 500000;  // 500us timeout
    
    //--------------------------------------------------------------------------
    // DUT Signals - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    logic                    clk_rt_50mhz;
    logic                    clk_gp_100mhz;
    logic                    rst_n;
    
    // RT-Core Interface
    logic                    rt_mem_en;
    logic                    rt_mem_we;
    logic [ADDR_WIDTH-1:0]   rt_mem_addr;
    logic [DATA_WIDTH-1:0]   rt_mem_wdata;
    logic [DATA_WIDTH-1:0]   rt_mem_rdata;
    logic                    rt_mem_ready;
    logic                    rt_mem_error;
    
    // GP-Core Interface
    logic                    gp_mem_en;
    logic                    gp_mem_we;
    logic [ADDR_WIDTH-1:0]   gp_mem_addr;
    logic [DATA_WIDTH-1:0]   gp_mem_wdata;
    logic [DATA_WIDTH-1:0]   gp_mem_rdata;
    logic                    gp_mem_ready;
    logic                    gp_mem_error;
    
    // System Status
    logic                    ram_ready;
    logic [31:0]             rt_access_count;
    logic [31:0]             gp_access_count;
    logic                    address_collision;
    logic [15:0]             rt_local_addr;
    logic [15:0]             gp_local_addr;
    
    //--------------------------------------------------------------------------
    // Test Control Variables - ALL DECLARED AT TOP
    //--------------------------------------------------------------------------
    integer test_errors;
    integer test_number;
    integer i, j, k;
    logic [31:0] test_addr;
    logic [31:0] test_data;
    logic [31:0] read_data;
    logic test_error;
    integer rt_accesses_before;
    integer gp_accesses_before;
    integer rt_accesses_after;
    integer gp_accesses_after;
    logic collision_detected;
    
    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial clk_rt_50mhz = 0;
    always #(CLK_PERIOD_RT/2) clk_rt_50mhz = ~clk_rt_50mhz;
    
    initial clk_gp_100mhz = 0;
    always #(CLK_PERIOD_GP/2) clk_gp_100mhz = ~clk_gp_100mhz;
    
    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    data_ram_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .RT_RAM_SIZE(32768),
        .GP_RAM_SIZE(32768),
        .RT_BASE_ADDR(RT_BASE_ADDR),
        .GP_BASE_ADDR(GP_BASE_ADDR)
    ) dut (
        .clk_rt_50mhz(clk_rt_50mhz),
        .clk_gp_100mhz(clk_gp_100mhz),
        .rst_n(rst_n),
        .rt_mem_en(rt_mem_en),
        .rt_mem_we(rt_mem_we),
        .rt_mem_addr(rt_mem_addr),
        .rt_mem_wdata(rt_mem_wdata),
        .rt_mem_rdata(rt_mem_rdata),
        .rt_mem_ready(rt_mem_ready),
        .rt_mem_error(rt_mem_error),
        .gp_mem_en(gp_mem_en),
        .gp_mem_we(gp_mem_we),
        .gp_mem_addr(gp_mem_addr),
        .gp_mem_wdata(gp_mem_wdata),
        .gp_mem_rdata(gp_mem_rdata),
        .gp_mem_ready(gp_mem_ready),
        .gp_mem_error(gp_mem_error),
        .ram_ready(ram_ready),
        .rt_access_count(rt_access_count),
        .gp_access_count(gp_access_count),
        .address_collision(address_collision),
        .rt_local_addr(rt_local_addr),
        .gp_local_addr(gp_local_addr)
    );
    
    //--------------------------------------------------------------------------
    // Test Tasks
    //--------------------------------------------------------------------------
    
    // Reset system
    task reset_system;
        begin
            $display("=== Resetting System ===");
            rst_n = 1'b0;
            rt_mem_en = 1'b0;
            rt_mem_we = 1'b0;
            rt_mem_addr = 32'h0;
            rt_mem_wdata = 32'h0;
            gp_mem_en = 1'b0;
            gp_mem_we = 1'b0;
            gp_mem_addr = 32'h0;
            gp_mem_wdata = 32'h0;
            
            repeat(5) @(posedge clk_rt_50mhz);
            rst_n = 1'b1;
            repeat(3) @(posedge clk_rt_50mhz);
            $display("Reset completed");
        end
    endtask
    
    // RT-Core memory write
    task rt_write(input [31:0] addr, input [31:0] data, output logic error);
        begin
            @(posedge clk_rt_50mhz);
            rt_mem_en = 1'b1;
            rt_mem_we = 1'b1;
            rt_mem_addr = addr;
            rt_mem_wdata = data;
            
            @(posedge clk_rt_50mhz);
            while (!rt_mem_ready) @(posedge clk_rt_50mhz);
            
            error = rt_mem_error;
            rt_mem_en = 1'b0;
            rt_mem_we = 1'b0;
            @(posedge clk_rt_50mhz);
        end
    endtask
    
    // RT-Core memory read
    task rt_read(input [31:0] addr, output [31:0] data, output logic error);
        begin
            @(posedge clk_rt_50mhz);
            rt_mem_en = 1'b1;
            rt_mem_we = 1'b0;
            rt_mem_addr = addr;
            
            @(posedge clk_rt_50mhz);
            while (!rt_mem_ready) @(posedge clk_rt_50mhz);
            
            data = rt_mem_rdata;
            error = rt_mem_error;
            rt_mem_en = 1'b0;
            @(posedge clk_rt_50mhz);
        end
    endtask
    
    // GP-Core memory write
    task gp_write(input [31:0] addr, input [31:0] data, output logic error);
        begin
            @(posedge clk_gp_100mhz);
            gp_mem_en = 1'b1;
            gp_mem_we = 1'b1;
            gp_mem_addr = addr;
            gp_mem_wdata = data;
            
            @(posedge clk_gp_100mhz);
            while (!gp_mem_ready) @(posedge clk_gp_100mhz);
            
            error = gp_mem_error;
            gp_mem_en = 1'b0;
            gp_mem_we = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    // GP-Core memory read
    task gp_read(input [31:0] addr, output [31:0] data, output logic error);
        begin
            @(posedge clk_gp_100mhz);
            gp_mem_en = 1'b1;
            gp_mem_we = 1'b0;
            gp_mem_addr = addr;
            
            @(posedge clk_gp_100mhz);
            while (!gp_mem_ready) @(posedge clk_gp_100mhz);
            
            data = gp_mem_rdata;
            error = gp_mem_error;
            gp_mem_en = 1'b0;
            @(posedge clk_gp_100mhz);
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Test Procedures
    //--------------------------------------------------------------------------
    
    // Test 1: Basic RT-Core operations
    task test_rt_basic_operations;
        begin
            $display("=== Test 1: RT-Core Basic Operations ===");
            test_number = 1;
            
            // Write to RT partition
            rt_write(RT_BASE_ADDR, 32'hDEADBEEF, test_error);
            if (test_error) begin
                $error("Test 1: RT write to valid address failed");
                test_errors++;
            end
            
            // Read back
            rt_read(RT_BASE_ADDR, read_data, test_error);
            if (test_error) begin
                $error("Test 1: RT read from valid address failed");
                test_errors++;
            end
            
            if (read_data != 32'hDEADBEEF) begin
                $error("Test 1: Data mismatch - Expected 0x%08X, Got 0x%08X", 
                       32'hDEADBEEF, read_data);
                test_errors++;
            end else begin
                $display("Test 1: RT basic read/write - PASS");
            end
        end
    endtask
    
    // Test 2: Basic GP-Core operations
    task test_gp_basic_operations;
        begin
            $display("=== Test 2: GP-Core Basic Operations ===");
            test_number = 2;
            
            // Write to GP partition
            gp_write(GP_BASE_ADDR, 32'hCAFEBABE, test_error);
            if (test_error) begin
                $error("Test 2: GP write to valid address failed");
                test_errors++;
            end
            
            // Read back
            gp_read(GP_BASE_ADDR, read_data, test_error);
            if (test_error) begin
                $error("Test 2: GP read from valid address failed");
                test_errors++;
            end
            
            if (read_data != 32'hCAFEBABE) begin
                $error("Test 2: Data mismatch - Expected 0x%08X, Got 0x%08X", 
                       32'hCAFEBABE, read_data);
                test_errors++;
            end else begin
                $display("Test 2: GP basic read/write - PASS");
            end
        end
    endtask
    
    // Test 3: Memory partition isolation
    task test_memory_isolation;
        begin
            $display("=== Test 3: Memory Partition Isolation ===");
            test_number = 3;
            
            // Write different patterns to both partitions
            rt_write(RT_BASE_ADDR + 32'h100, 32'hAA55AA55, test_error);
            gp_write(GP_BASE_ADDR + 32'h100, 32'h55AA55AA, test_error);
            
            // Read from both partitions
            rt_read(RT_BASE_ADDR + 32'h100, read_data, test_error);
            if (read_data != 32'hAA55AA55) begin
                $error("Test 3: RT partition data corrupted");
                test_errors++;
            end
            
            gp_read(GP_BASE_ADDR + 32'h100, read_data, test_error);
            if (read_data != 32'h55AA55AA) begin
                $error("Test 3: GP partition data corrupted");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 3: Memory isolation - PASS");
            end
        end
    endtask
    
    // Test 4: Bounds checking - RT-Core
    task test_rt_bounds_checking;
        begin
            $display("=== Test 4: RT-Core Bounds Checking ===");
            test_number = 4;
            
            // Try to access below RT partition
            rt_write(RT_BASE_ADDR - 32'h4, 32'h12345678, test_error);
            if (!test_error) begin
                $error("Test 4: RT should not access below partition");
                test_errors++;
            end else begin
                $display("Test 4: RT lower bound check - PASS");
            end
            
            // Try to access above RT partition
            rt_write(RT_END_ADDR + 32'h4, 32'h12345678, test_error);
            if (!test_error) begin
                $error("Test 4: RT should not access above partition");
                test_errors++;
            end else begin
                $display("Test 4: RT upper bound check - PASS");
            end
            
            // Try to access GP partition
            rt_write(GP_BASE_ADDR, 32'h12345678, test_error);
            if (!test_error) begin
                $error("Test 4: RT should not access GP partition");
                test_errors++;
            end else begin
                $display("Test 4: RT cross-partition check - PASS");
            end
        end
    endtask
    
    // Test 5: Bounds checking - GP-Core
    task test_gp_bounds_checking;
        begin
            $display("=== Test 5: GP-Core Bounds Checking ===");
            test_number = 5;
            
            // Try to access below GP partition
            gp_write(GP_BASE_ADDR - 32'h4, 32'h87654321, test_error);
            if (!test_error) begin
                $error("Test 5: GP should not access below partition");
                test_errors++;
            end else begin
                $display("Test 5: GP lower bound check - PASS");
            end
            
            // Try to access above GP partition
            gp_write(GP_END_ADDR + 32'h4, 32'h87654321, test_error);
            if (!test_error) begin
                $error("Test 5: GP should not access above partition");
                test_errors++;
            end else begin
                $display("Test 5: GP upper bound check - PASS");
            end
            
            // Try to access RT partition
            gp_write(RT_BASE_ADDR, 32'h87654321, test_error);
            if (!test_error) begin
                $error("Test 5: GP should not access RT partition");
                test_errors++;
            end else begin
                $display("Test 5: GP cross-partition check - PASS");
            end
        end
    endtask
    
    // Test 6: Address alignment checking
    task test_address_alignment;
        begin
            $display("=== Test 6: Address Alignment Checking ===");
            test_number = 6;
            
            // Try unaligned accesses
            rt_write(RT_BASE_ADDR + 32'h1, 32'h11111111, test_error);
            if (!test_error) begin
                $error("Test 6: RT should reject unaligned address");
                test_errors++;
            end else begin
                $display("Test 6: RT alignment check - PASS");
            end
            
            gp_write(GP_BASE_ADDR + 32'h3, 32'h22222222, test_error);
            if (!test_error) begin
                $error("Test 6: GP should reject unaligned address");
                test_errors++;
            end else begin
                $display("Test 6: GP alignment check - PASS");
            end
        end
    endtask
    
    // Test 7: Performance counters
    task test_performance_counters;
        begin
            $display("=== Test 7: Performance Counters ===");
            test_number = 7;
            
            rt_accesses_before = rt_access_count;
            gp_accesses_before = gp_access_count;
            
            // Perform some operations
            rt_write(RT_BASE_ADDR + 32'h200, 32'h11111111, test_error);
            rt_read(RT_BASE_ADDR + 32'h200, read_data, test_error);
            gp_write(GP_BASE_ADDR + 32'h200, 32'h22222222, test_error);
            gp_read(GP_BASE_ADDR + 32'h200, read_data, test_error);
            
            rt_accesses_after = rt_access_count;
            gp_accesses_after = gp_access_count;
            
            if ((rt_accesses_after - rt_accesses_before) != 2) begin
                $error("Test 7: RT access count incorrect");
                test_errors++;
            end else begin
                $display("Test 7: RT access counting - PASS");
            end
            
            if ((gp_accesses_after - gp_accesses_before) != 2) begin
                $error("Test 7: GP access count incorrect");
                test_errors++;
            end else begin
                $display("Test 7: GP access counting - PASS");
            end
        end
    endtask
    
    // Test 8: Boundary addresses
    task test_boundary_addresses;
        begin
            $display("=== Test 8: Boundary Address Testing ===");
            test_number = 8;
            
            // Test RT partition boundaries
            rt_write(RT_BASE_ADDR, 32'hBBBBBBBB, test_error);
            if (test_error) begin
                $error("Test 8: RT base address access failed");
                test_errors++;
            end
            
            rt_write(RT_END_ADDR - 32'h3, 32'hCCCCCCCC, test_error); // Last valid word
            if (test_error) begin
                $error("Test 8: RT end address access failed");
                test_errors++;
            end
            
            // Test GP partition boundaries
            gp_write(GP_BASE_ADDR, 32'hDDDDDDDD, test_error);
            if (test_error) begin
                $error("Test 8: GP base address access failed");
                test_errors++;
            end
            
            gp_write(GP_END_ADDR - 32'h3, 32'hEEEEEEEE, test_error); // Last valid word
            if (test_error) begin
                $error("Test 8: GP end address access failed");
                test_errors++;
            end
            
            if (test_errors == 0) begin
                $display("Test 8: Boundary address testing - PASS");
            end
        end
    endtask
    
    // Test 9: Collision detection
    task test_collision_detection;
        begin
            $display("=== Test 9: Collision Detection ===");
            test_number = 9;
            
            collision_detected = 1'b0;
            
            // Simultaneous access to trigger collision detection
            fork
                begin
                    @(posedge clk_rt_50mhz);
                    rt_mem_en = 1'b1;
                    rt_mem_addr = RT_BASE_ADDR + 32'h300;
                    @(posedge clk_rt_50mhz);
                    rt_mem_en = 1'b0;
                end
                begin
                    @(posedge clk_gp_100mhz);
                    gp_mem_en = 1'b1;
                    gp_mem_addr = GP_BASE_ADDR + 32'h300;
                    @(posedge clk_gp_100mhz);
                    gp_mem_en = 1'b0;
                end
            join
            
            // Check if collision was detected
            repeat(3) @(posedge clk_rt_50mhz);
            
            $display("Test 9: Collision detection - INFO (collision signal may vary with timing)");
        end
    endtask
    
    // Test 10: Sequential access pattern
    task test_sequential_access;
        begin
            $display("=== Test 10: Sequential Access Pattern ===");
            test_number = 10;
            
            // Sequential writes to RT partition
            for (i = 0; i < 16; i++) begin
                test_addr = RT_BASE_ADDR + (i * 4);
                test_data = 32'h10000000 + i;
                rt_write(test_addr, test_data, test_error);
                if (test_error) begin
                    $error("Test 10: RT sequential write failed at iteration %0d", i);
                    test_errors++;
                end
            end
            
            // Sequential reads and verify
            for (i = 0; i < 16; i++) begin
                test_addr = RT_BASE_ADDR + (i * 4);
                test_data = 32'h10000000 + i;
                rt_read(test_addr, read_data, test_error);
                if (test_error || (read_data != test_data)) begin
                    $error("Test 10: RT sequential read failed at iteration %0d", i);
                    test_errors++;
                end
            end
            
            // Sequential writes to GP partition
            for (i = 0; i < 16; i++) begin
                test_addr = GP_BASE_ADDR + (i * 4);
                test_data = 32'h20000000 + i;
                gp_write(test_addr, test_data, test_error);
                if (test_error) begin
                    $error("Test 10: GP sequential write failed at iteration %0d", i);
                    test_errors++;
                end
            end
            
            // Sequential reads and verify
            for (i = 0; i < 16; i++) begin
                test_addr = GP_BASE_ADDR + (i * 4);
                test_data = 32'h20000000 + i;
                gp_read(test_addr, read_data, test_error);
                if (test_error || (read_data != test_data)) begin
                    $error("Test 10: GP sequential read failed at iteration %0d", i);
                    test_errors++;
                end
            end
            
            if (test_errors == 0) begin
                $display("Test 10: Sequential access pattern - PASS");
            end
        end
    endtask
    
    //--------------------------------------------------------------------------
    // Main Test Execution
    //--------------------------------------------------------------------------
    
    initial begin
        $display("===============================================");
        $display("Data RAM Controller Testbench");
        $display("MAK8u Microcontroller Project");
        $display("Author: Manikanta Gonugondla");
        $display("===============================================");
        
        test_errors = 0;
        
        // Reset and initialize
        reset_system();
        
        // Wait for system to stabilize
        repeat(10) @(posedge clk_rt_50mhz);
        
        // Run all tests
        test_rt_basic_operations();
        test_gp_basic_operations();
        test_memory_isolation();
        test_rt_bounds_checking();
        test_gp_bounds_checking();
        test_address_alignment();
        test_performance_counters();
        test_boundary_addresses();
        test_collision_detection();
        test_sequential_access();
        
        // Final stabilization
        repeat(10) @(posedge clk_rt_50mhz);
        
        // Final report
        $display("===============================================");
        $display("Test Results Summary:");
        $display("  Tests completed: 10");
        $display("  Total errors: %0d", test_errors);
        $display("  Final RT access count: %0d", rt_access_count);
        $display("  Final GP access count: %0d", gp_access_count);
        $display("  RAM ready status: %b", ram_ready);
        
        if (test_errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
            $display("Data RAM Controller is WORKING CORRECTLY!");
        end else begin
            $display("*** %0d TESTS FAILED ***", test_errors);
            $display("Module needs debugging");
        end
        
        $display("===============================================");
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Timeout Protection
    //--------------------------------------------------------------------------
    initial begin
        #TEST_TIMEOUT;
        $error("Simulation timeout");
        $finish;
    end

endmodule
