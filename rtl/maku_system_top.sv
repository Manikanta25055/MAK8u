`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: maku_system_top
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: MAKu System Top Level
//              - Integrates Core Top with Peripherals and Memory
//              - Top-level IO mapping
// 
// Dependencies: maku_core_top, clock_management_unit, data_ram_controller, program_rom_controller, ...
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module maku_system_top (
    input  logic        sys_clk_100mhz, // Nexys A7 100MHz Input
    input  logic        sys_rst_n,      // Active Low Reset
    
    // UART
    input  logic        uart_rx,
    output logic        uart_tx,
    
    // GPIO
    inout  wire [15:0]  gpio_pins, // Reduced to 16 for demo/board limit
    
    // LEDs
    output logic [15:0] leds
);

    //--------------------------------------------------------------------------
    // Clock Management
    //--------------------------------------------------------------------------
    logic clk_rt_50mhz;
    logic clk_gp_100mhz;
    logic locked;
    logic rst_n;
    
    clock_management_unit cmu (
        .clk_in1(sys_clk_100mhz),
        .resetn(sys_rst_n),
        .clk_out1(clk_gp_100mhz), // 100MHz
        .clk_out2(clk_rt_50mhz),  // 50MHz
        .locked(locked)
    );
    
    assign rst_n = sys_rst_n & locked;
    
    //--------------------------------------------------------------------------
    // Core Top Instance
    //--------------------------------------------------------------------------
    logic        rt_icache_req;
    logic [15:0] rt_icache_addr;
    logic [15:0] rt_icache_data;
    logic        rt_icache_ready;
    
    logic        rt_dmem_en;
    logic        rt_dmem_we;
    logic [31:0] rt_dmem_addr;
    logic [31:0] rt_dmem_wdata;
    logic [31:0] rt_dmem_rdata;
    logic        rt_dmem_ready;
    
    logic        gp_icache_req;
    logic [15:0] gp_icache_addr;
    logic [15:0] gp_icache_data;
    logic        gp_icache_ready;
    
    logic        gp_dcache_req;
    logic        gp_dcache_we;
    logic [3:0]  gp_dcache_be;
    logic [31:0] gp_dcache_addr;
    logic [31:0] gp_dcache_wdata;
    logic [31:0] gp_dcache_rdata;
    logic        gp_dcache_ready;
    
    logic [15:0] rt_irq_sources;
    logic [31:0] gp_irq_sources;
    
    maku_core_top core_top (
        .clk_rt_50mhz(clk_rt_50mhz),
        .clk_gp_100mhz(clk_gp_100mhz),
        .rst_n(rst_n),
        
        .rt_icache_req(rt_icache_req),
        .rt_icache_addr(rt_icache_addr),
        .rt_icache_data(rt_icache_data),
        .rt_icache_ready(rt_icache_ready),
        
        .rt_dmem_en(rt_dmem_en),
        .rt_dmem_we(rt_dmem_we),
        .rt_dmem_addr(rt_dmem_addr),
        .rt_dmem_wdata(rt_dmem_wdata),
        .rt_dmem_rdata(rt_dmem_rdata),
        .rt_dmem_ready(rt_dmem_ready),
        
        .rt_irq_sources(rt_irq_sources),
        
        .gp_icache_req(gp_icache_req),
        .gp_icache_addr(gp_icache_addr),
        .gp_icache_data(gp_icache_data),
        .gp_icache_ready(gp_icache_ready),
        
        .gp_dcache_req(gp_dcache_req),
        .gp_dcache_we(gp_dcache_we),
        .gp_dcache_be(gp_dcache_be),
        .gp_dcache_addr(gp_dcache_addr),
        .gp_dcache_wdata(gp_dcache_wdata),
        .gp_dcache_rdata(gp_dcache_rdata),
        .gp_dcache_ready(gp_dcache_ready),
        
        .gp_irq_sources(gp_irq_sources)
    );
    
    //--------------------------------------------------------------------------
    // Memory Controllers
    //--------------------------------------------------------------------------
    
    // Program ROM (Shared or Split?)
    // Assuming separate ROM controllers or dual-port ROM.
    // For now, placeholder ROM response.
    assign rt_icache_data = 16'hF000; // NOP
    assign rt_icache_ready = 1'b1;
    assign gp_icache_data = 16'hF000; // NOP
    assign gp_icache_ready = 1'b1;
    
    // Data RAM
    // Placeholder RAM response
    assign rt_dmem_rdata = 32'h0;
    assign rt_dmem_ready = 1'b1;
    assign gp_dcache_rdata = 32'h0;
    assign gp_dcache_ready = 1'b1;
    
    //--------------------------------------------------------------------------
    // Peripherals
    //--------------------------------------------------------------------------
    
    // GPIO
    logic gpio_irq_a, gpio_irq_b;
    gpio_controller gpio (
        .clk(clk_gp_100mhz),
        .rst_n(rst_n),
        .reg_en(1'b0), // TODO: Map to GP address space
        .reg_we(1'b0),
        .reg_addr(4'h0),
        .reg_wdata(32'h0),
        .reg_rdata(),
        .gpio_irq_a(gpio_irq_a),
        .gpio_irq_b(gpio_irq_b),
        .gpio_pins({48'h0, gpio_pins}) // Map 16 pins to lower bits
    );
    
    // UART
    logic [3:0] uart_irq;
    uart_controller uart (
        .clk(clk_gp_100mhz),
        .rst_n(rst_n),
        .reg_en(1'b0), // TODO: Map
        .reg_we(1'b0),
        .reg_addr(6'h0),
        .reg_wdata(32'h0),
        .reg_rdata(),
        .uart_irq(uart_irq),
        .uart_rx({3'b000, uart_rx}),
        .uart_tx({3'bxxx, uart_tx}) // Only channel 0 connected
    );
    
    // Timers
    logic [3:0] rt_timer_irq;
    rt_timer_bank rt_timers (
        .clk(clk_rt_50mhz),
        .rst_n(rst_n),
        .reg_en(1'b0),
        .reg_we(1'b0),
        .reg_addr(4'h0),
        .reg_wdata(32'h0),
        .reg_rdata(),
        .timer_irq(rt_timer_irq)
    );
    
    logic [1:0] gp_timer_irq;
    gp_timer_bank gp_timers (
        .clk(clk_gp_100mhz),
        .rst_n(rst_n),
        .reg_en(1'b0),
        .reg_we(1'b0),
        .reg_addr(4'h0),
        .reg_wdata(32'h0),
        .reg_rdata(),
        .timer_irq(gp_timer_irq)
    );
    
    //--------------------------------------------------------------------------
    // Interrupt Mapping
    //--------------------------------------------------------------------------
    assign rt_irq_sources = {12'h0, rt_timer_irq}; // Map timers to IRQ
    assign gp_irq_sources = {24'h0, uart_irq, gp_timer_irq, gpio_irq_b, gpio_irq_a};
    
    // Debug LEDs
    assign leds = {14'h0, locked, rst_n};

endmodule
