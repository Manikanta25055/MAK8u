`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: vector_memory_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Vector Data Memory Controller (8KB)
//              - Dedicated memory for Vector Processing Unit
//              - 128-bit wide access
//              - High bandwidth
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module vector_memory_controller #(
    parameter MEM_SIZE = 512 // 512 x 128-bit = 8KB
)(
    input  logic         clk,
    input  logic         rst_n,
    
    // Vector Memory Interface
    input  logic         mem_en,
    input  logic         mem_we,
    input  logic [8:0]   mem_addr, // 512 entries
    input  logic [127:0] mem_wdata,
    output logic [127:0] mem_rdata,
    output logic         mem_ready
);

    // Vector Memory Array (Block RAM)
    (* ram_style = "block" *) logic [127:0] vector_ram [0:MEM_SIZE-1];
    
    logic mem_en_d1;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rdata <= 128'h0;
            mem_en_d1 <= 1'b0;
        end else begin
            mem_en_d1 <= mem_en;
            
            if (mem_en) begin
                if (mem_we) begin
                    vector_ram[mem_addr] <= mem_wdata;
                end
                mem_rdata <= vector_ram[mem_addr]; // Read-during-write = old data or new? Block RAM usually new or old depending on mode. Assuming READ_FIRST or WRITE_FIRST.
            end
        end
    end
    
    assign mem_ready = mem_en_d1; // 1-cycle latency

endmodule
