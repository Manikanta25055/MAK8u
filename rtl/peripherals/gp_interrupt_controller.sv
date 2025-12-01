`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: gp_interrupt_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: General-Purpose Interrupt Controller
//              - 32 Interrupt Sources
//              - Vector Table Offset Generation
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gp_interrupt_controller (
    input  logic        clk,
    input  logic        rst_n,
    
    // Interrupt Sources
    input  logic [31:0] irq_sources,
    
    // Core Interface
    output logic        irq_req,
    output logic [4:0]  irq_vector, // 32 sources -> 5 bits
    input  logic        irq_ack,
    
    // Register Interface
    input  logic        reg_en,
    input  logic        reg_we,
    input  logic [3:0]  reg_addr,
    input  logic [31:0] reg_wdata,
    output logic [31:0] reg_rdata
);

    logic [31:0] irq_enable;
    logic [31:0] irq_pending;
    
    logic [31:0] active_irqs;
    logic [4:0]  highest_pri_vector;
    logic        any_irq;
    
    // Latch Interrupts
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending <= 32'h0;
        end else begin
            irq_pending <= (irq_pending | irq_sources) & ~({32{irq_ack}} & (32'h1 << irq_vector));
        end
    end
    
    assign active_irqs = irq_pending & irq_enable;
    
    // Priority Arbitration (Fixed 0->31)
    always_comb begin
        highest_pri_vector = 5'h0;
        any_irq = 1'b0;
        
        for (int i = 0; i < 32; i++) begin
            if (active_irqs[i]) begin
                highest_pri_vector = i[4:0];
                any_irq = 1'b1;
                break;
            end
        end
    end
    
    assign irq_req = any_irq;
    assign irq_vector = highest_pri_vector;
    
    // Register Access
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_enable <= 32'h0;
            reg_rdata <= 32'h0;
        end else begin
            if (reg_en && reg_we) begin
                case (reg_addr)
                    4'h0: irq_enable <= reg_wdata;
                endcase
            end
            
            if (reg_en && !reg_we) begin
                case (reg_addr)
                    4'h0: reg_rdata <= irq_enable;
                    4'h1: reg_rdata <= irq_pending;
                endcase
            end
        end
    end

endmodule
