`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: rt_timer_bank
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Real-Time Timer Bank
//              - 4x 32-bit Timers
//              - Deterministic timing (50MHz base)
//              - Interrupt generation on overflow/match
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module rt_timer_bank (
    input  logic        clk,
    input  logic        rst_n,
    
    // Register Interface
    input  logic        reg_en,
    input  logic        reg_we,
    input  logic [3:0]  reg_addr, // 16 registers (4 per timer)
    input  logic [31:0] reg_wdata,
    output logic [31:0] reg_rdata,
    
    // Interrupt Output
    output logic [3:0]  timer_irq // One per timer
);

    // Timer Registers
    // Base + 0: Control (Start, Mode, IntEn)
    // Base + 1: Counter Value
    // Base + 2: Reload/Match Value
    // Base + 3: Prescaler
    
    logic [31:0] timer_ctrl [0:3];
    logic [31:0] timer_count [0:3];
    logic [31:0] timer_match [0:3];
    logic [31:0] timer_prescale [0:3];
    logic [31:0] prescale_count [0:3];
    
    // Internal Signals
    logic [3:0] timer_enable;
    logic [3:0] timer_int_en;
    logic [3:0] timer_mode; // 0=Free run, 1=One-shot
    
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            timer_enable[i] = timer_ctrl[i][0];
            timer_int_en[i] = timer_ctrl[i][1];
            timer_mode[i]   = timer_ctrl[i][2];
        end
    end
    
    // Timer Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                timer_ctrl[i] <= 32'h0;
                timer_count[i] <= 32'h0;
                timer_match[i] <= 32'h0;
                timer_prescale[i] <= 32'h0;
                prescale_count[i] <= 32'h0;
                timer_irq[i] <= 1'b0;
            end
            reg_rdata <= 32'h0;
        end else begin
            // Register Write
            if (reg_en && reg_we) begin
                case (reg_addr[1:0])
                    2'b00: timer_ctrl[reg_addr[3:2]] <= reg_wdata;
                    2'b01: timer_count[reg_addr[3:2]] <= reg_wdata;
                    2'b10: timer_match[reg_addr[3:2]] <= reg_wdata;
                    2'b11: timer_prescale[reg_addr[3:2]] <= reg_wdata;
                endcase
            end
            
            // Register Read
            if (reg_en && !reg_we) begin
                case (reg_addr[1:0])
                    2'b00: reg_rdata <= timer_ctrl[reg_addr[3:2]];
                    2'b01: reg_rdata <= timer_count[reg_addr[3:2]];
                    2'b10: reg_rdata <= timer_match[reg_addr[3:2]];
                    2'b11: reg_rdata <= timer_prescale[reg_addr[3:2]];
                endcase
            end
            
            // Timer Counting
            for (int i = 0; i < 4; i++) begin
                if (timer_enable[i]) begin
                    if (prescale_count[i] >= timer_prescale[i]) begin
                        prescale_count[i] <= 32'h0;
                        
                        if (timer_count[i] >= timer_match[i]) begin
                            timer_count[i] <= 32'h0;
                            if (timer_int_en[i]) timer_irq[i] <= 1'b1;
                            
                            if (timer_mode[i]) begin // One-shot
                                timer_ctrl[i][0] <= 1'b0; // Clear enable
                            end
                        end else begin
                            timer_count[i] <= timer_count[i] + 1;
                            timer_irq[i] <= 1'b0; // Clear IRQ on next tick? Or write-to-clear?
                            // For simplicity, pulse IRQ or hold until cleared. 
                            // Let's assume write-to-clear in Control reg bit 3.
                        end
                    end else begin
                        prescale_count[i] <= prescale_count[i] + 1;
                    end
                end
                
                // Clear Interrupt
                if (reg_en && reg_we && (reg_addr[3:2] == i) && (reg_addr[1:0] == 2'b00) && reg_wdata[3]) begin
                    timer_irq[i] <= 1'b0;
                end
            end
        end
    end

endmodule
