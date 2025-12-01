`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/01/2025
// Design Name: MAKu Microcontroller
// Module Name: priority_inheritance
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Hardware Priority Inheritance Logic
//              - Prevents priority inversion in real-time systems
//              - Monitors mutex/semaphore ownership
//              - Dynamically boosts priority of mutex owners if high-priority task waits
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module priority_inheritance #(
    parameter TASK_COUNT = 8,
    parameter MUTEX_COUNT = 16
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // Task Status
    input  logic [TASK_COUNT-1:0]      task_active,
    input  logic [3:0]                 task_base_priority [0:TASK_COUNT-1],
    
    // Mutex Status
    input  logic [MUTEX_COUNT-1:0]     mutex_locked,
    input  logic [2:0]                 mutex_owner [0:MUTEX_COUNT-1], // Task ID owning mutex
    input  logic [TASK_COUNT-1:0]      task_waiting_for_mutex [0:MUTEX_COUNT-1], // Bitmap of tasks waiting
    
    // Output
    output logic [3:0]                 task_effective_priority [0:TASK_COUNT-1]
);

    logic [3:0] inherited_priority [0:TASK_COUNT-1];

    always_comb begin
        // Initialize with base priority
        for (int t = 0; t < TASK_COUNT; t++) begin
            inherited_priority[t] = task_base_priority[t];
        end
        
        // Check all mutexes
        for (int m = 0; m < MUTEX_COUNT; m++) begin
            if (mutex_locked[m]) begin
                logic [2:0] owner_id;
                owner_id = mutex_owner[m];
                
                // Check if any higher priority task is waiting for this mutex
                for (int t = 0; t < TASK_COUNT; t++) begin
                    if (task_waiting_for_mutex[m][t]) begin
                        // If waiting task has higher priority than current inherited priority of owner
                        if (task_base_priority[t] > inherited_priority[owner_id]) begin
                            inherited_priority[owner_id] = task_base_priority[t];
                        end
                    end
                end
            end
        end
    end
    
    // Output assignment
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int t = 0; t < TASK_COUNT; t++) begin
                task_effective_priority[t] <= 4'h0;
            end
        end else begin
            for (int t = 0; t < TASK_COUNT; t++) begin
                task_effective_priority[t] <= inherited_priority[t];
            end
        end
    end

endmodule
