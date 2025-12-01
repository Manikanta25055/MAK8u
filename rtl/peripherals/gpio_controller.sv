`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: gpio_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: GPIO Controller (64-pin)
//              - Configurable Direction (Input/Output)
//              - Interrupt on Change
//              - 2 Ports (A: 0-31, B: 32-63)
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module gpio_controller (
    input  logic        clk,
    input  logic        rst_n,
    
    // Register Interface
    input  logic        reg_en,
    input  logic        reg_we,
    input  logic [3:0]  reg_addr,
    input  logic [31:0] reg_wdata,
    output logic [31:0] reg_rdata,
    
    // Interrupt Output
    output logic        gpio_irq_a,
    output logic        gpio_irq_b,
    
    // Physical Pins
    inout  wire [63:0]  gpio_pins
);

    // Registers Map
    // 0x0: Port A Data (RW)
    // 0x1: Port A Direction (RW, 1=Output)
    // 0x2: Port A Interrupt Enable (RW)
    // 0x3: Port A Interrupt Status (RW1C)
    // 0x4: Port B Data
    // 0x5: Port B Direction
    // 0x6: Port B Interrupt Enable
    // 0x7: Port B Interrupt Status
    
    logic [31:0] port_a_data_out;
    logic [31:0] port_a_data_in;
    logic [31:0] port_a_dir;
    logic [31:0] port_a_int_en;
    logic [31:0] port_a_int_stat;
    
    logic [31:0] port_b_data_out;
    logic [31:0] port_b_data_in;
    logic [31:0] port_b_dir;
    logic [31:0] port_b_int_en;
    logic [31:0] port_b_int_stat;
    
    logic [31:0] port_a_in_d1, port_a_in_d2;
    logic [31:0] port_b_in_d1, port_b_in_d2;
    
    // Tri-state buffers
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin
            assign gpio_pins[i] = port_a_dir[i] ? port_a_data_out[i] : 1'bz;
            assign gpio_pins[i+32] = port_b_dir[i] ? port_b_data_out[i] : 1'bz;
        end
    endgenerate
    
    // Input Synchronization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            port_a_in_d1 <= 32'h0;
            port_a_in_d2 <= 32'h0;
            port_b_in_d1 <= 32'h0;
            port_b_in_d2 <= 32'h0;
        end else begin
            port_a_in_d1 <= gpio_pins[31:0];
            port_a_in_d2 <= port_a_in_d1;
            port_b_in_d1 <= gpio_pins[63:32];
            port_b_in_d2 <= port_b_in_d1;
            
            port_a_data_in <= port_a_in_d2;
            port_b_data_in <= port_b_in_d2;
        end
    end
    
    // Interrupt Generation (Edge Detect)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            port_a_int_stat <= 32'h0;
            port_b_int_stat <= 32'h0;
        end else begin
            // Detect change
            logic [31:0] change_a;
            logic [31:0] change_b;
            change_a = port_a_in_d1 ^ port_a_in_d2;
            change_b = port_b_in_d1 ^ port_b_in_d2;
            
            // Set status bits
            port_a_int_stat <= port_a_int_stat | (change_a & port_a_int_en);
            port_b_int_stat <= port_b_int_stat | (change_b & port_b_int_en);
            
            // Clear status on write
            if (reg_en && reg_we) begin
                if (reg_addr == 4'h3) port_a_int_stat <= port_a_int_stat & ~reg_wdata;
                if (reg_addr == 4'h7) port_b_int_stat <= port_b_int_stat & ~reg_wdata;
            end
        end
    end
    
    assign gpio_irq_a = |port_a_int_stat;
    assign gpio_irq_b = |port_b_int_stat;
    
    // Register Access
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            port_a_data_out <= 32'h0;
            port_a_dir <= 32'h0;
            port_a_int_en <= 32'h0;
            port_b_data_out <= 32'h0;
            port_b_dir <= 32'h0;
            port_b_int_en <= 32'h0;
            reg_rdata <= 32'h0;
        end else begin
            if (reg_en && reg_we) begin
                case (reg_addr)
                    4'h0: port_a_data_out <= reg_wdata;
                    4'h1: port_a_dir <= reg_wdata;
                    4'h2: port_a_int_en <= reg_wdata;
                    // 4'h3 is Status Clear (handled above)
                    4'h4: port_b_data_out <= reg_wdata;
                    4'h5: port_b_dir <= reg_wdata;
                    4'h6: port_b_int_en <= reg_wdata;
                    // 4'h7 is Status Clear
                endcase
            end
            
            if (reg_en && !reg_we) begin
                case (reg_addr)
                    4'h0: reg_rdata <= port_a_data_in;
                    4'h1: reg_rdata <= port_a_dir;
                    4'h2: reg_rdata <= port_a_int_en;
                    4'h3: reg_rdata <= port_a_int_stat;
                    4'h4: reg_rdata <= port_b_data_in;
                    4'h5: reg_rdata <= port_b_dir;
                    4'h6: reg_rdata <= port_b_int_en;
                    4'h7: reg_rdata <= port_b_int_stat;
                endcase
            end
        end
    end

endmodule
