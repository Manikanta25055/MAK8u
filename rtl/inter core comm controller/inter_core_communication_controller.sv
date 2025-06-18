`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/29/2024
// Design Name: MAKu Microcontroller
// Module Name: inter_core_communication_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: Inter-Core Communication Controller for MAKu Dual-Core MCU
//              Manages shared memory, message queues, semaphores, and cross-core interrupts
//              Enables 2-cycle message passing between RT-Core and GP-Core
// 
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// - 8KB shared dual-port RAM
// - 4x 256-byte FIFO message queues
// - 16 hardware semaphores with priority arbitration
// - Cross-core interrupt generation
// - Hardware barrier primitives
// 
//////////////////////////////////////////////////////////////////////////////////

module inter_core_communication_controller #(
    parameter SHARED_MEM_SIZE = 8192,      // 8KB shared memory
    parameter QUEUE_COUNT = 4,             // 4 message queues
    parameter QUEUE_DEPTH = 64,            // 256 bytes / 4 bytes per entry
    parameter SEMAPHORE_COUNT = 16,        // 16 hardware semaphores
    parameter BARRIER_COUNT = 4            // 4 hardware barriers
)(
    // Clock and Reset
    input  logic        clk_rt_50mhz,
    input  logic        clk_gp_100mhz,
    input  logic        rst_n_system,
    
    // RT-Core Interface (50MHz domain)
    input  logic                      rt_mem_en,
    input  logic                      rt_mem_we,
    input  logic [12:0]               rt_mem_addr,      // 8KB addressing
    input  logic [31:0]               rt_mem_wdata,
    output logic [31:0]               rt_mem_rdata,
    output logic                      rt_mem_ready,
    
    // RT-Core Message Queue Interface
    input  logic [1:0]                rt_queue_sel,     // Queue selection
    input  logic                      rt_queue_push,
    input  logic                      rt_queue_pop,
    input  logic [31:0]               rt_queue_data_in,
    output logic [31:0]               rt_queue_data_out,
    output logic                      rt_queue_full,
    output logic                      rt_queue_empty,
    
    // RT-Core Semaphore Interface
    input  logic [3:0]                rt_sem_id,        // Semaphore ID
    input  logic                      rt_sem_acquire,
    input  logic                      rt_sem_release,
    output logic                      rt_sem_acquired,
    output logic [15:0]               rt_sem_status,    // All semaphore status
    
    // RT-Core Barrier Interface
    input  logic [1:0]                rt_barrier_id,
    input  logic                      rt_barrier_wait,
    input  logic                      rt_barrier_reset,
    output logic                      rt_barrier_reached,
    
    // GP-Core Interface (100MHz domain)
    input  logic                      gp_mem_en,
    input  logic                      gp_mem_we,
    input  logic [12:0]               gp_mem_addr,
    input  logic [31:0]               gp_mem_wdata,
    output logic [31:0]               gp_mem_rdata,
    output logic                      gp_mem_ready,
    
    // GP-Core Message Queue Interface
    input  logic [1:0]                gp_queue_sel,
    input  logic                      gp_queue_push,
    input  logic                      gp_queue_pop,
    input  logic [31:0]               gp_queue_data_in,
    output logic [31:0]               gp_queue_data_out,
    output logic                      gp_queue_full,
    output logic                      gp_queue_empty,
    
    // GP-Core Semaphore Interface
    input  logic [3:0]                gp_sem_id,
    input  logic                      gp_sem_acquire,
    input  logic                      gp_sem_release,
    output logic                      gp_sem_acquired,
    output logic [15:0]               gp_sem_status,
    
    // GP-Core Barrier Interface
    input  logic [1:0]                gp_barrier_id,
    input  logic                      gp_barrier_wait,
    input  logic                      gp_barrier_reset,
    output logic                      gp_barrier_reached,
    
    // Cross-Core Interrupts
    output logic                      rt_to_gp_interrupt,
    output logic                      gp_to_rt_interrupt,
    input  logic                      rt_interrupt_ack,
    input  logic                      gp_interrupt_ack,
    
    // Status and Debug
    output logic [31:0]               message_count_rt_to_gp,
    output logic [31:0]               message_count_gp_to_rt,
    output logic [7:0]                active_semaphores,
    output logic [3:0]                barrier_status,
    output logic                      communication_error
);

    //--------------------------------------------------------------------------
    // Internal Signal Declarations
    //--------------------------------------------------------------------------
    
    // Shared memory signals
    logic [31:0] shared_memory [0:(SHARED_MEM_SIZE/4)-1];
    logic        mem_collision;
    logic        rt_mem_ready_int;
    logic        gp_mem_ready_int;
    
    // Message queue signals
    logic [31:0] message_queues [0:QUEUE_COUNT-1][0:QUEUE_DEPTH-1];
    logic [5:0]  queue_head [0:QUEUE_COUNT-1];
    logic [5:0]  queue_tail [0:QUEUE_COUNT-1];
    logic [5:0]  queue_count [0:QUEUE_COUNT-1];
    logic        queue_full_int [0:QUEUE_COUNT-1];
    logic        queue_empty_int [0:QUEUE_COUNT-1];
    
    // Semaphore signals
    logic [15:0] semaphore_owners;     // 0=free, 1=RT-Core, 2=GP-Core
    logic [15:0] semaphore_pending_rt;
    logic [15:0] semaphore_pending_gp;
    logic [3:0]  sem_grant_rt;
    logic [3:0]  sem_grant_gp;
    
    // Barrier signals
    logic [3:0]  barrier_rt_waiting;
    logic [3:0]  barrier_gp_waiting;
    logic [3:0]  barrier_both_reached;
    
    // Cross-core interrupt signals
    logic        rt_to_gp_int_req;
    logic        gp_to_rt_int_req;
    logic        rt_to_gp_int_pending;
    logic        gp_to_rt_int_pending;
    
    // Statistics counters
    logic [31:0] msg_cnt_rt_to_gp;
    logic [31:0] msg_cnt_gp_to_rt;
    logic [31:0] collision_count;
    
    //--------------------------------------------------------------------------
    // Shared Memory Implementation (True Dual-Port)
    //--------------------------------------------------------------------------
    
    // RT-Core memory access (50MHz domain)
    always_ff @(posedge clk_rt_50mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            rt_mem_rdata <= 32'h0;
            rt_mem_ready_int <= 1'b0;
        end else begin
            rt_mem_ready_int <= rt_mem_en;
            
            if (rt_mem_en) begin
                if (rt_mem_we && (rt_mem_addr < (SHARED_MEM_SIZE/4))) begin
                    shared_memory[rt_mem_addr] <= rt_mem_wdata;
                end else if (!rt_mem_we && (rt_mem_addr < (SHARED_MEM_SIZE/4))) begin
                    rt_mem_rdata <= shared_memory[rt_mem_addr];
                end else begin
                    rt_mem_rdata <= 32'h0;  // Out of bounds
                end
            end
        end
    end
    
    // GP-Core memory access (100MHz domain)
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            gp_mem_rdata <= 32'h0;
            gp_mem_ready_int <= 1'b0;
        end else begin
            gp_mem_ready_int <= gp_mem_en;
            
            if (gp_mem_en) begin
                if (gp_mem_we && (gp_mem_addr < (SHARED_MEM_SIZE/4))) begin
                    shared_memory[gp_mem_addr] <= gp_mem_wdata;
                end else if (!gp_mem_we && (gp_mem_addr < (SHARED_MEM_SIZE/4))) begin
                    gp_mem_rdata <= shared_memory[gp_mem_addr];
                end else begin
                    gp_mem_rdata <= 32'h0;  // Out of bounds
                end
            end
        end
    end
    
    // Collision detection
    assign mem_collision = rt_mem_en && gp_mem_en && (rt_mem_addr == gp_mem_addr);
    
    //--------------------------------------------------------------------------
    // Message Queue Implementation (4x 256-byte FIFOs)
    //--------------------------------------------------------------------------
    
    // Initialize message queues
    initial begin
        for (int i = 0; i < QUEUE_COUNT; i++) begin
            queue_head[i] = 6'h0;
            queue_tail[i] = 6'h0;
            queue_count[i] = 6'h0;
        end
    end
    
    // RT-Core queue operations (50MHz domain)
    always_ff @(posedge clk_rt_50mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            for (int i = 0; i < QUEUE_COUNT; i++) begin
                queue_head[i] <= 6'h0;
                queue_tail[i] <= 6'h0;
                queue_count[i] <= 6'h0;
            end
            rt_queue_data_out <= 32'h0;
            msg_cnt_rt_to_gp <= 32'h0;
        end else begin
            // RT-Core push operation
            if (rt_queue_push && !queue_full_int[rt_queue_sel]) begin
                message_queues[rt_queue_sel][queue_head[rt_queue_sel]] <= rt_queue_data_in;
                queue_head[rt_queue_sel] <= (queue_head[rt_queue_sel] + 1) % QUEUE_DEPTH;
                queue_count[rt_queue_sel] <= queue_count[rt_queue_sel] + 1;
                
                // Statistics
                if (rt_queue_sel < 2) begin  // Queues 0,1 are RT->GP
                    msg_cnt_rt_to_gp <= msg_cnt_rt_to_gp + 1;
                end
            end
            
            // RT-Core pop operation
            if (rt_queue_pop && !queue_empty_int[rt_queue_sel]) begin
                rt_queue_data_out <= message_queues[rt_queue_sel][queue_tail[rt_queue_sel]];
                queue_tail[rt_queue_sel] <= (queue_tail[rt_queue_sel] + 1) % QUEUE_DEPTH;
                queue_count[rt_queue_sel] <= queue_count[rt_queue_sel] - 1;
            end
        end
    end
    
    // GP-Core queue operations (100MHz domain)
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            gp_queue_data_out <= 32'h0;
            msg_cnt_gp_to_rt <= 32'h0;
        end else begin
            // GP-Core push operation
            if (gp_queue_push && !queue_full_int[gp_queue_sel]) begin
                message_queues[gp_queue_sel][queue_head[gp_queue_sel]] <= gp_queue_data_in;
                queue_head[gp_queue_sel] <= (queue_head[gp_queue_sel] + 1) % QUEUE_DEPTH;
                queue_count[gp_queue_sel] <= queue_count[gp_queue_sel] + 1;
                
                // Statistics
                if (gp_queue_sel >= 2) begin  // Queues 2,3 are GP->RT
                    msg_cnt_gp_to_rt <= msg_cnt_gp_to_rt + 1;
                end
            end
            
            // GP-Core pop operation
            if (gp_queue_pop && !queue_empty_int[gp_queue_sel]) begin
                gp_queue_data_out <= message_queues[gp_queue_sel][queue_tail[gp_queue_sel]];
                queue_tail[gp_queue_sel] <= (queue_tail[gp_queue_sel] + 1) % QUEUE_DEPTH;
                queue_count[gp_queue_sel] <= queue_count[gp_queue_sel] - 1;
            end
        end
    end
    
    // Queue status flags
    always_comb begin
        for (int i = 0; i < QUEUE_COUNT; i++) begin
            queue_full_int[i] = (queue_count[i] == QUEUE_DEPTH);
            queue_empty_int[i] = (queue_count[i] == 0);
        end
    end
    
    //--------------------------------------------------------------------------
    // Hardware Semaphore Implementation (16 semaphores)
    //--------------------------------------------------------------------------
    
    // Semaphore arbitration logic
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            semaphore_owners <= 16'h0;
            semaphore_pending_rt <= 16'h0;
            semaphore_pending_gp <= 16'h0;
            sem_grant_rt <= 4'h0;
            sem_grant_gp <= 4'h0;
        end else begin
            // RT-Core semaphore operations (synchronized to GP clock)
            if (rt_sem_acquire) begin
                if (!semaphore_owners[rt_sem_id]) begin
                    semaphore_owners[rt_sem_id] <= 1'b1;  // RT owns it
                    sem_grant_rt <= rt_sem_id;
                end else begin
                    semaphore_pending_rt[rt_sem_id] <= 1'b1;
                end
            end
            
            if (rt_sem_release && semaphore_owners[rt_sem_id]) begin
                semaphore_owners[rt_sem_id] <= 1'b0;
                semaphore_pending_rt[rt_sem_id] <= 1'b0;
                
                // Grant to pending GP-Core if waiting
                if (semaphore_pending_gp[rt_sem_id]) begin
                    semaphore_owners[rt_sem_id] <= 1'b1;
                    semaphore_pending_gp[rt_sem_id] <= 1'b0;
                    sem_grant_gp <= rt_sem_id;
                end
            end
            
            // GP-Core semaphore operations
            if (gp_sem_acquire) begin
                if (!semaphore_owners[gp_sem_id]) begin
                    semaphore_owners[gp_sem_id] <= 1'b1;
                    sem_grant_gp <= gp_sem_id;
                end else begin
                    semaphore_pending_gp[gp_sem_id] <= 1'b1;
                end
            end
            
            if (gp_sem_release && semaphore_owners[gp_sem_id]) begin
                semaphore_owners[gp_sem_id] <= 1'b0;
                semaphore_pending_gp[gp_sem_id] <= 1'b0;
                
                // Grant to pending RT-Core if waiting
                if (semaphore_pending_rt[gp_sem_id]) begin
                    semaphore_owners[gp_sem_id] <= 1'b1;
                    semaphore_pending_rt[gp_sem_id] <= 1'b0;
                    sem_grant_rt <= gp_sem_id;
                end
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Hardware Barrier Implementation (4 barriers)
    //--------------------------------------------------------------------------
    
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            barrier_rt_waiting <= 4'h0;
            barrier_gp_waiting <= 4'h0;
            barrier_both_reached <= 4'h0;
        end else begin
            // RT-Core barrier operations
            if (rt_barrier_wait) begin
                barrier_rt_waiting[rt_barrier_id] <= 1'b1;
            end
            
            if (rt_barrier_reset) begin
                barrier_rt_waiting[rt_barrier_id] <= 1'b0;
                barrier_both_reached[rt_barrier_id] <= 1'b0;
            end
            
            // GP-Core barrier operations
            if (gp_barrier_wait) begin
                barrier_gp_waiting[gp_barrier_id] <= 1'b1;
            end
            
            if (gp_barrier_reset) begin
                barrier_gp_waiting[gp_barrier_id] <= 1'b0;
                barrier_both_reached[gp_barrier_id] <= 1'b0;
            end
            
            // Check for barrier completion
            for (int i = 0; i < BARRIER_COUNT; i++) begin
                if (barrier_rt_waiting[i] && barrier_gp_waiting[i]) begin
                    barrier_both_reached[i] <= 1'b1;
                    barrier_rt_waiting[i] <= 1'b0;
                    barrier_gp_waiting[i] <= 1'b0;
                end
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Cross-Core Interrupt Generation
    //--------------------------------------------------------------------------
    
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            rt_to_gp_int_pending <= 1'b0;
            gp_to_rt_int_pending <= 1'b0;
        end else begin
            // Generate interrupts on message queue activity
            rt_to_gp_int_req <= rt_queue_push && (rt_queue_sel < 2);  // RT->GP queues
            gp_to_rt_int_req <= gp_queue_push && (gp_queue_sel >= 2); // GP->RT queues
            
            // Interrupt pending logic
            if (rt_to_gp_int_req) begin
                rt_to_gp_int_pending <= 1'b1;
            end else if (gp_interrupt_ack) begin
                rt_to_gp_int_pending <= 1'b0;
            end
            
            if (gp_to_rt_int_req) begin
                gp_to_rt_int_pending <= 1'b1;
            end else if (rt_interrupt_ack) begin
                gp_to_rt_int_pending <= 1'b0;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Collision and Error Detection
    //--------------------------------------------------------------------------
    
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            collision_count <= 32'h0;
        end else if (mem_collision) begin
            collision_count <= collision_count + 1;
        end
    end
    
    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    
    assign rt_mem_ready = rt_mem_ready_int;
    assign gp_mem_ready = gp_mem_ready_int;
    
    assign rt_queue_full = queue_full_int[rt_queue_sel];
    assign rt_queue_empty = queue_empty_int[rt_queue_sel];
    assign gp_queue_full = queue_full_int[gp_queue_sel];
    assign gp_queue_empty = queue_empty_int[gp_queue_sel];
    
    assign rt_sem_acquired = (sem_grant_rt == rt_sem_id) && semaphore_owners[rt_sem_id];
    assign gp_sem_acquired = (sem_grant_gp == gp_sem_id) && semaphore_owners[gp_sem_id];
    assign rt_sem_status = semaphore_owners;
    assign gp_sem_status = semaphore_owners;
    
    assign rt_barrier_reached = barrier_both_reached[rt_barrier_id];
    assign gp_barrier_reached = barrier_both_reached[gp_barrier_id];
    
    assign rt_to_gp_interrupt = rt_to_gp_int_pending;
    assign gp_to_rt_interrupt = gp_to_rt_int_pending;
    
    assign message_count_rt_to_gp = msg_cnt_rt_to_gp;
    assign message_count_gp_to_rt = msg_cnt_gp_to_rt;
    assign active_semaphores = |semaphore_owners ? 8'h1 : 8'h0;
    assign barrier_status = barrier_both_reached;
    assign communication_error = (collision_count > 32'h1000);  // Error threshold
    
    //--------------------------------------------------------------------------
    // Simulation-Only Debug
    //--------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk_gp_100mhz) begin
        if (mem_collision) begin
            $warning("MAKu ICC: Memory collision at address 0x%04X", rt_mem_addr);
        end
        
        if (rt_queue_push && queue_full_int[rt_queue_sel]) begin
            $warning("MAKu ICC: RT-Core attempted push to full queue %0d", rt_queue_sel);
        end
        
        if (gp_queue_push && queue_full_int[gp_queue_sel]) begin
            $warning("MAKu ICC: GP-Core attempted push to full queue %0d", gp_queue_sel);
        end
    end
    
    initial begin
        $display("MAKu Inter-Core Communication Controller Configuration:");
        $display("  Shared Memory: %0d KB", SHARED_MEM_SIZE / 1024);
        $display("  Message Queues: %0d x %0d entries", QUEUE_COUNT, QUEUE_DEPTH);
        $display("  Semaphores: %0d", SEMAPHORE_COUNT);
        $display("  Barriers: %0d", BARRIER_COUNT);
    end
    // synthesis translate_on

endmodule
