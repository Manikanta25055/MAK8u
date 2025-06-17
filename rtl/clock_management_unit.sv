`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/29/2024
// Design Name: MAKu Microcontroller
// Module Name: clock_management_unit
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Clock Management Unit for MAKu Dual-Core Microcontroller
//              Generates multiple clock domains from 100MHz input
//              Handles reset synchronization across clock domains
// 
// Dependencies: None (uses Xilinx primitives)
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - RT-Core: 50MHz (deterministic timing)
// - GP-Core: 100MHz (high performance)
// - Peripheral: 25MHz (low power peripherals)
// - Debug: 10MHz (JTAG/Debug interface)
// 
//////////////////////////////////////////////////////////////////////////////////

module clock_management_unit (
    // Input clock and reset
    input  logic        clk_in_100mhz,      // 100MHz from Nexys A7
    input  logic        ext_reset_n,        // External reset (active low)
    
    // Generated clocks
    output logic        clk_rt_50mhz,       // RT-Core clock (50MHz)
    output logic        clk_gp_100mhz,      // GP-Core clock (100MHz) 
    output logic        clk_periph_25mhz,   // Peripheral clock (25MHz)
    output logic        clk_debug_10mhz,    // Debug interface clock (10MHz)
    
    // Clock enables (for power management)
    output logic        clk_en_rt,          // RT-Core clock enable
    output logic        clk_en_gp,          // GP-Core clock enable
    output logic        clk_en_periph,      // Peripheral clock enable
    output logic        clk_en_debug,       // Debug clock enable
    
    // Synchronized resets
    output logic        rst_n_rt,           // RT-Core synchronized reset
    output logic        rst_n_gp,           // GP-Core synchronized reset
    output logic        rst_n_periph,       // Peripheral synchronized reset
    output logic        rst_n_debug,        // Debug synchronized reset
    
    // System status
    output logic        pll_locked,         // PLL lock indicator
    output logic        clocks_stable,      // All clocks stable
    
    // Power management
    input  logic        power_down_rt,      // Power down RT-Core
    input  logic        power_down_gp,      // Power down GP-Core
    input  logic        power_down_periph,  // Power down peripherals
    
    // Clock monitoring
    output logic [31:0] rt_clk_count,       // RT clock cycle counter
    output logic [31:0] gp_clk_count        // GP clock cycle counter
);

    // Internal signals - ALL DECLARED AT TOP
    logic        clk_fb;
    logic        clk_200mhz;
    logic        clk_100mhz_buf;
    logic        clk_50mhz_buf;
    logic        clk_25mhz_buf;
    logic        clk_10mhz_buf;
    logic        pll_locked_buf;
    logic        reset_counter_done;
    logic [7:0]  reset_counter;
    logic [2:0]  rt_reset_sync;
    logic [2:0]  gp_reset_sync;
    logic [2:0]  periph_reset_sync;
    logic [2:0]  debug_reset_sync;
    logic [31:0] rt_counter;
    logic [31:0] gp_counter;
    logic        clk_en_rt_int;
    logic        clk_en_gp_int;
    logic        clk_en_periph_int;
    logic        clk_en_debug_int;
    
    //--------------------------------------------------------------------------
    // MMCM/PLL Clock Generation
    //--------------------------------------------------------------------------
    // Using MMCME2_BASE for clock generation
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),        // Jitter programming
        .CLKFBOUT_MULT_F(10.0),        // 100MHz * 10 = 1000MHz VCO
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),          // 100MHz input period
        .CLKOUT0_DIVIDE_F(20.0),       // 1000MHz / 20 = 50MHz (RT-Core)
        .CLKOUT1_DIVIDE(10),           // 1000MHz / 10 = 100MHz (GP-Core)
        .CLKOUT2_DIVIDE(40),           // 1000MHz / 40 = 25MHz (Peripherals)
        .CLKOUT3_DIVIDE(100),          // 1000MHz / 100 = 10MHz (Debug)
        .CLKOUT4_DIVIDE(5),            // 1000MHz / 5 = 200MHz (unused)
        .CLKOUT5_DIVIDE(1),            // Unused
        .CLKOUT6_DIVIDE(1),            // Unused
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_PHASE(0.0),
        .CLKOUT2_PHASE(0.0),
        .CLKOUT3_PHASE(0.0),
        .CLKOUT4_CASCADE("FALSE"),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.0),
        .STARTUP_WAIT("FALSE")
    ) mmcm_inst (
        .CLKOUT0(clk_50mhz_buf),
        .CLKOUT0B(),
        .CLKOUT1(clk_100mhz_buf),
        .CLKOUT1B(),
        .CLKOUT2(clk_25mhz_buf),
        .CLKOUT2B(),
        .CLKOUT3(clk_10mhz_buf),
        .CLKOUT3B(),
        .CLKOUT4(clk_200mhz),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clk_fb),
        .CLKFBOUTB(),
        .LOCKED(pll_locked_buf),
        .CLKIN1(clk_in_100mhz),
        .PWRDWN(1'b0),
        .RST(!ext_reset_n),
        .CLKFBIN(clk_fb)
    );
    
    //--------------------------------------------------------------------------
    // Global Clock Buffers
    //--------------------------------------------------------------------------
    BUFG bufg_rt (.O(clk_rt_50mhz), .I(clk_50mhz_buf));
    BUFG bufg_gp (.O(clk_gp_100mhz), .I(clk_100mhz_buf));
    BUFG bufg_periph (.O(clk_periph_25mhz), .I(clk_25mhz_buf));
    BUFG bufg_debug (.O(clk_debug_10mhz), .I(clk_10mhz_buf));
    
    //--------------------------------------------------------------------------
    // Reset Generation and Synchronization
    //--------------------------------------------------------------------------
    // Reset counter for PLL stabilization
    always_ff @(posedge clk_gp_100mhz or negedge pll_locked_buf) begin
        if (!pll_locked_buf) begin
            reset_counter <= 8'h00;
            reset_counter_done <= 1'b0;
        end else begin
            if (!reset_counter_done) begin
                reset_counter <= reset_counter + 1;
                if (reset_counter == 8'hFF) begin
                    reset_counter_done <= 1'b1;
                end
            end
        end
    end
    
    // RT-Core reset synchronizer (50MHz domain)
    always_ff @(posedge clk_rt_50mhz or negedge reset_counter_done) begin
        if (!reset_counter_done) begin
            rt_reset_sync <= 3'b000;
        end else begin
            rt_reset_sync <= {rt_reset_sync[1:0], 1'b1};
        end
    end
    
    // GP-Core reset synchronizer (100MHz domain)
    always_ff @(posedge clk_gp_100mhz or negedge reset_counter_done) begin
        if (!reset_counter_done) begin
            gp_reset_sync <= 3'b000;
        end else begin
            gp_reset_sync <= {gp_reset_sync[1:0], 1'b1};
        end
    end
    
    // Peripheral reset synchronizer (25MHz domain)
    always_ff @(posedge clk_periph_25mhz or negedge reset_counter_done) begin
        if (!reset_counter_done) begin
            periph_reset_sync <= 3'b000;
        end else begin
            periph_reset_sync <= {periph_reset_sync[1:0], 1'b1};
        end
    end
    
    // Debug reset synchronizer (10MHz domain)
    always_ff @(posedge clk_debug_10mhz or negedge reset_counter_done) begin
        if (!reset_counter_done) begin
            debug_reset_sync <= 3'b000;
        end else begin
            debug_reset_sync <= {debug_reset_sync[1:0], 1'b1};
        end
    end
    
    //--------------------------------------------------------------------------
    // Clock Enable Generation (Power Management)
    //--------------------------------------------------------------------------
    assign clk_en_rt_int = !power_down_rt && pll_locked_buf;
    assign clk_en_gp_int = !power_down_gp && pll_locked_buf;
    assign clk_en_periph_int = !power_down_periph && pll_locked_buf;
    assign clk_en_debug_int = pll_locked_buf; // Debug always enabled when PLL locked
    
    //--------------------------------------------------------------------------
    // Clock Cycle Counters (for profiling/debugging)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_rt_50mhz or negedge rst_n_rt) begin
        if (!rst_n_rt) begin
            rt_counter <= 32'h0;
        end else if (clk_en_rt) begin
            rt_counter <= rt_counter + 1;
        end
    end
    
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_gp) begin
        if (!rst_n_gp) begin
            gp_counter <= 32'h0;
        end else if (clk_en_gp) begin
            gp_counter <= gp_counter + 1;
        end
    end
    
    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    assign pll_locked = pll_locked_buf;
    assign clocks_stable = reset_counter_done && pll_locked_buf;
    
    assign rst_n_rt = rt_reset_sync[2];
    assign rst_n_gp = gp_reset_sync[2];
    assign rst_n_periph = periph_reset_sync[2];
    assign rst_n_debug = debug_reset_sync[2];
    
    assign clk_en_rt = clk_en_rt_int;
    assign clk_en_gp = clk_en_gp_int;
    assign clk_en_periph = clk_en_periph_int;
    assign clk_en_debug = clk_en_debug_int;
    
    assign rt_clk_count = rt_counter;
    assign gp_clk_count = gp_counter;
    
    //--------------------------------------------------------------------------
    // Simulation-Only Debug
    //--------------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        $display("MAKu Clock Management Unit Configuration:");
        $display("  RT-Core Clock: 50MHz (20ns period)");
        $display("  GP-Core Clock: 100MHz (10ns period)");
        $display("  Peripheral Clock: 25MHz (40ns period)");
        $display("  Debug Clock: 10MHz (100ns period)");
    end
    
    always @(posedge clk_gp_100mhz) begin
        if (pll_locked && !$past(pll_locked)) begin
            $display("MAKu Clock: PLL locked at time %0t", $time);
        end
        if (clocks_stable && !$past(clocks_stable)) begin
            $display("MAKu Clock: All clocks stable at time %0t", $time);
        end
    end
    // synthesis translate_on

endmodule
