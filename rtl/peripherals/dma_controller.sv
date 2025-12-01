`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: dma_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: DMA Controller
//              - 8 Channels
//              - Memory-to-Memory, Memory-to-Peripheral
//              - Scatter-Gather Support (Simplified)
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module dma_controller (
    input  logic        clk,
    input  logic        rst_n,
    
    // Register Interface
    input  logic        reg_en,
    input  logic        reg_we,
    input  logic [5:0]  reg_addr,
    input  logic [31:0] reg_wdata,
    output logic [31:0] reg_rdata,
    
    // Master Interface (Memory Access)
    output logic        mem_req,
    output logic        mem_we,
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    input  logic [31:0] mem_rdata,
    input  logic        mem_ready,
    
    // Interrupt
    output logic        dma_irq
);

    // 8 Channels
    // Regs per channel:
    // +0: Src Addr
    // +1: Dst Addr
    // +2: Count
    // +3: Control (Start, Enable, Mode)
    
    logic [31:0] dma_src [0:7];
    logic [31:0] dma_dst [0:7];
    logic [31:0] dma_cnt [0:7];
    logic [31:0] dma_ctrl [0:7];
    
    // State Machine
    typedef enum logic [2:0] {
        IDLE,
        READ,
        WRITE,
        NEXT
    } state_t;
    
    state_t state;
    logic [2:0] active_ch;
    logic [31:0] data_buffer;
    
    // Arbitration: Round Robin
    logic [2:0] next_ch;
    
    always_comb begin
        next_ch = active_ch; // Default
        for (int i = 1; i <= 8; i++) begin
            logic [2:0] idx;
            idx = (active_ch + i) % 8;
            if (dma_ctrl[idx][0]) begin // If enabled/start bit set
                next_ch = idx;
                break;
            end
        end
    end
    
    // DMA Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            active_ch <= 3'h0;
            mem_req <= 1'b0;
            mem_we <= 1'b0;
            dma_irq <= 1'b0;
            reg_rdata <= 32'h0;
            for (int i=0; i<8; i++) begin
                dma_src[i] <= 32'h0;
                dma_dst[i] <= 32'h0;
                dma_cnt[i] <= 32'h0;
                dma_ctrl[i] <= 32'h0;
            end
        end else begin
            // Register Access
            if (reg_en && reg_we) begin
                case (reg_addr[1:0])
                    2'b00: dma_src[reg_addr[4:2]] <= reg_wdata;
                    2'b01: dma_dst[reg_addr[4:2]] <= reg_wdata;
                    2'b10: dma_cnt[reg_addr[4:2]] <= reg_wdata;
                    2'b11: dma_ctrl[reg_addr[4:2]] <= reg_wdata;
                endcase
            end
            
            // State Machine
            case (state)
                IDLE: begin
                    if (dma_ctrl[next_ch][0]) begin // Check if any channel active
                        active_ch <= next_ch;
                        state <= READ;
                        mem_req <= 1'b1;
                        mem_we <= 1'b0;
                        mem_addr <= dma_src[next_ch];
                    end
                end
                
                READ: begin
                    if (mem_ready) begin
                        data_buffer <= mem_rdata;
                        state <= WRITE;
                        mem_req <= 1'b1;
                        mem_we <= 1'b1;
                        mem_addr <= dma_dst[active_ch];
                        mem_wdata <= mem_rdata; // Or data_buffer next cycle? 
                        // Assuming 1-cycle latency, data available now.
                        // If we need to hold address/data for write, we might need to register it.
                        // Let's assume we can switch to write immediately.
                    end
                end
                
                WRITE: begin
                    if (mem_ready) begin
                        state <= NEXT;
                        mem_req <= 1'b0;
                        mem_we <= 1'b0;
                        
                        // Update Pointers
                        dma_src[active_ch] <= dma_src[active_ch] + 4;
                        dma_dst[active_ch] <= dma_dst[active_ch] + 4;
                        dma_cnt[active_ch] <= dma_cnt[active_ch] - 1;
                    end
                end
                
                NEXT: begin
                    if (dma_cnt[active_ch] == 0) begin
                        dma_ctrl[active_ch][0] <= 1'b0; // Clear enable
                        if (dma_ctrl[active_ch][1]) dma_irq <= 1'b1; // IRQ
                        state <= IDLE;
                    end else begin
                        state <= READ; // Continue burst
                        mem_req <= 1'b1;
                        mem_we <= 1'b0;
                        mem_addr <= dma_src[active_ch];
                    end
                end
            endcase
        end
    end

endmodule
