`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: maku_system_tb
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: System Level Testbench
//              - Instantiates maku_system_top
//              - Generates Clocks and Reset
//              - Simulates UART Input
//              - Monitors GPIO and LEDs
// 
// Dependencies: maku_system_top
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module maku_system_tb;

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    logic sys_clk_100mhz;
    logic sys_rst_n;
    logic uart_rx;
    logic uart_tx;
    wire [15:0] gpio_pins;
    logic [15:0] leds;
    
    // GPIO Driver
    logic [15:0] gpio_drive;
    logic [15:0] gpio_dir; // 1 = Output (TB driving), 0 = Input (DUT driving)
    
    assign gpio_pins = gpio_dir ? gpio_drive : 16'bz;

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------
    maku_system_top dut (
        .sys_clk_100mhz(sys_clk_100mhz),
        .sys_rst_n(sys_rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio_pins(gpio_pins),
        .leds(leds)
    );

    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial begin
        sys_clk_100mhz = 0;
        forever #5 sys_clk_100mhz = ~sys_clk_100mhz; // 100MHz = 10ns period
    end

    //--------------------------------------------------------------------------
    // Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        // Initialize Inputs
        sys_rst_n = 0;
        uart_rx = 1; // Idle High
        gpio_drive = 16'h0000;
        gpio_dir = 16'h0000; // High-Z
        
        $display("----------------------------------------------------------------");
        $display("MAKu System Testbench Started");
        $display("----------------------------------------------------------------");
        
        // Reset Pulse
        #100;
        sys_rst_n = 1;
        $display("[%0t] Reset Released", $time);
        
        // Wait for Lock (PLL lock time)
        wait(leds[1]); // LED[1] is locked signal
        $display("[%0t] Clock Manager Locked", $time);
        
        // Let it run for a while
        #1000;
        
        // Test UART RX (Send a byte 0xA5)
        // Baud rate simulation is tricky without knowing configured baud.
        // Assuming default or fast baud for sim.
        // Let's just toggle the pin to see if IRQ triggers in waveform.
        uart_rx = 0; // Start bit
        #8680; // Assuming 115200 baud (8.68us bit time) -> 8680ns
        uart_rx = 1; // Data bit 0
        #8680;
        uart_rx = 0; // Data bit 1
        #8680;
        uart_rx = 1; // Data bit 2
        #8680;
        uart_rx = 0; // Data bit 3
        #8680;
        uart_rx = 0; // Data bit 4
        #8680;
        uart_rx = 1; // Data bit 5
        #8680;
        uart_rx = 0; // Data bit 6
        #8680;
        uart_rx = 1; // Data bit 7
        #8680;
        uart_rx = 1; // Stop bit
        #8680;
        
        $display("[%0t] UART Byte Sent", $time);
        
        // Test GPIO Input
        gpio_dir = 16'hFFFF; // Drive all pins
        gpio_drive = 16'h55AA;
        #100;
        gpio_drive = 16'hAA55;
        #100;
        gpio_dir = 16'h0000; // Release
        
        $display("[%0t] GPIO Toggled", $time);
        
        #5000;
        
        $display("----------------------------------------------------------------");
        $display("Test Complete");
        $display("----------------------------------------------------------------");
        $finish;
    end
    
    //--------------------------------------------------------------------------
    // Monitoring
    //--------------------------------------------------------------------------
    initial begin
        $monitor("Time=%0t | RST=%b | LEDS=%h | UART_TX=%b", 
                 $time, sys_rst_n, leds, uart_tx);
    end

endmodule
