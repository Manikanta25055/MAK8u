`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Manikanta Gonugondla
// 
// Create Date: 12/29/2024
// Design Name: MAKu Microcontroller
// Module Name: reset_controller
// Project Name: MAKu Dual-Core MCU
// Target Devices: Nexys A7 100T
// Tool Versions: Vivado 2024.2
// Description: System Reset Controller for MAKu Dual-Core Microcontroller
//              Coordinates reset sequencing across all system components
//              Handles inter-core dependencies and startup ordering
// 
// Dependencies: clock_management_unit.sv
// 
// Revision:
// Revision 0.04 - Simplified state machine and fixed timing
// Additional Comments:
// - Provides coordinated reset release sequence
// - Handles watchdog reset functionality
// - Supports software-initiated resets
// - Ensures proper startup ordering
// 
//////////////////////////////////////////////////////////////////////////////////

module reset_controller (
    // Clock inputs from CMU
    input  logic        clk_rt_50mhz,
    input  logic        clk_gp_100mhz,
    input  logic        clk_periph_25mhz,
    input  logic        clk_debug_10mhz,
    
    // Reset inputs
    input  logic        ext_reset_n,        // External reset button
    input  logic        por_reset_n,        // Power-on reset
    input  logic        pll_locked,         // PLL lock status from CMU
    input  logic        clocks_stable,      // Clock stability from CMU
    
    // Software reset requests
    input  logic        sw_reset_req,       // Software reset request
    input  logic        rt_core_reset_req,  // RT-Core reset request
    input  logic        gp_core_reset_req,  // GP-Core reset request
    input  logic        periph_reset_req,   // Peripheral reset request
    
    // Watchdog reset
    input  logic        watchdog_reset,     // Watchdog timeout reset
    input  logic        watchdog_en,        // Watchdog enable
    
    // System status inputs
    input  logic        rt_core_halted,     // RT-Core in halt state
    input  logic        gp_core_halted,     // GP-Core in halt state
    
    // Reset outputs (synchronized to respective domains)
    output logic        rst_n_system,       // Global system reset
    output logic        rst_n_rt_core,      // RT-Core reset
    output logic        rst_n_gp_core,      // GP-Core reset
    output logic        rst_n_peripherals,  // Peripheral subsystem reset
    output logic        rst_n_memory,       // Memory subsystem reset
    output logic        rst_n_debug,        // Debug interface reset
    
    // Reset status and control
    output logic [2:0]  reset_cause,        // Last reset cause
    output logic        reset_sequence_done,// Reset sequence completed
    output logic        cores_ready,        // Both cores ready for operation
    
    // Reset timing control
    input  logic [7:0]  reset_hold_cycles,  // Configurable reset hold time
    input  logic        quick_reset_en,     // Enable quick reset mode
    
    // Debug and monitoring
    output logic [15:0] reset_counter,      // Reset sequence counter
    output logic [31:0] uptime_counter      // System uptime counter
);

    // Reset cause encoding
    localparam [2:0] RESET_CAUSE_POR       = 3'b000;  // Power-on reset
    localparam [2:0] RESET_CAUSE_EXTERNAL  = 3'b001;  // External reset
    localparam [2:0] RESET_CAUSE_SOFTWARE  = 3'b010;  // Software reset
    localparam [2:0] RESET_CAUSE_WATCHDOG  = 3'b011;  // Watchdog reset
    localparam [2:0] RESET_CAUSE_CORE_REQ  = 3'b100;  // Core-requested reset
    localparam [2:0] RESET_CAUSE_UNKNOWN   = 3'b111;  // Unknown/invalid
    
    // Reset state machine states
    typedef enum logic [3:0] {
        RESET_IDLE          = 4'b0000,
        RESET_DETECTED      = 4'b0001,
        RESET_HOLD          = 4'b0010,
        RESET_WAIT_PLL      = 4'b0011,
        RESET_WAIT_CLOCKS   = 4'b0100,
        RESET_RELEASE_MEM   = 4'b0101,
        RESET_RELEASE_DEBUG = 4'b0110,
        RESET_RELEASE_PERIPH = 4'b0111,
        RESET_RELEASE_RT    = 4'b1000,
        RESET_RELEASE_GP    = 4'b1001,
        RESET_COMPLETE      = 4'b1010,
        RESET_ERROR         = 4'b1111
    } reset_state_t;
    
    // All internal signals declared at top
    reset_state_t reset_state;
    reset_state_t reset_state_next;
    logic [7:0]   hold_counter;
    logic [7:0]   sequence_counter;
    logic [31:0]  uptime_cnt;
    logic [2:0]   reset_cause_reg;
    logic [2:0]   rt_reset_sync;
    logic [2:0]   gp_reset_sync;
    logic [2:0]   periph_reset_sync;
    logic [2:0]   mem_reset_sync;
    logic [2:0]   debug_reset_sync;
    logic [2:0]   system_reset_sync;
    logic         reset_request;
    logic         hold_time_expired;
    logic         sequence_complete;
    logic         rt_core_reset_int;
    logic         gp_core_reset_int;
    logic         periph_reset_int;
    logic         mem_reset_int;
    logic         debug_reset_int;
    logic         system_reset_int;
    logic         pll_locked_sync;
    logic         clocks_stable_sync;
    
    //--------------------------------------------------------------------------
    // Reset Detection and Cause Determination
    //--------------------------------------------------------------------------
    always_comb begin
        reset_request = 1'b0;
        
        // Priority order for reset causes (combinational)
        if (!por_reset_n) begin
            reset_request = 1'b1;
        end else if (watchdog_reset && watchdog_en) begin
            reset_request = 1'b1;
        end else if (!ext_reset_n) begin
            reset_request = 1'b1;
        end else if (sw_reset_req) begin
            reset_request = 1'b1;
        end else if (rt_core_reset_req || gp_core_reset_req || periph_reset_req) begin
            reset_request = 1'b1;
        end
    end
    
    //--------------------------------------------------------------------------
    // Reset Cause Latching - Priority Encoded
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge por_reset_n) begin
        if (!por_reset_n) begin
            reset_cause_reg <= RESET_CAUSE_POR;
        end else if (reset_state == RESET_IDLE && reset_request) begin
            // Latch cause when transitioning from idle to reset
            if (!por_reset_n) begin
                reset_cause_reg <= RESET_CAUSE_POR;
            end else if (watchdog_reset && watchdog_en) begin
                reset_cause_reg <= RESET_CAUSE_WATCHDOG;
            end else if (!ext_reset_n) begin
                reset_cause_reg <= RESET_CAUSE_EXTERNAL;
            end else if (sw_reset_req) begin
                reset_cause_reg <= RESET_CAUSE_SOFTWARE;
            end else if (rt_core_reset_req || gp_core_reset_req || periph_reset_req) begin
                reset_cause_reg <= RESET_CAUSE_CORE_REQ;
            end else begin
                reset_cause_reg <= RESET_CAUSE_UNKNOWN;
            end
        end
    end
    
    //--------------------------------------------------------------------------
    // Synchronize control signals to avoid metastability
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz) begin
        pll_locked_sync <= pll_locked;
        clocks_stable_sync <= clocks_stable;
    end
    
    //--------------------------------------------------------------------------
    // Reset State Machine
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge por_reset_n) begin
        if (!por_reset_n) begin
            reset_state <= RESET_DETECTED;
            hold_counter <= 8'h00;
            sequence_counter <= 8'h00;
        end else begin
            reset_state <= reset_state_next;
            
            // Counter management
            case (reset_state_next)
                RESET_HOLD: begin
                    hold_counter <= hold_counter + 1;
                end
                RESET_RELEASE_MEM,
                RESET_RELEASE_DEBUG,
                RESET_RELEASE_PERIPH,
                RESET_RELEASE_RT,
                RESET_RELEASE_GP: begin
                    sequence_counter <= sequence_counter + 1;
                end
                RESET_DETECTED: begin
                    // Reset counters for new sequence
                    hold_counter <= 8'h00;
                    sequence_counter <= 8'h00;
                end
                default: begin
                    // Hold counter values
                end
            endcase
        end
    end
    
    //--------------------------------------------------------------------------
    // Next State Logic
    //--------------------------------------------------------------------------
    always_comb begin
        reset_state_next = reset_state;
        hold_time_expired = (hold_counter >= (quick_reset_en ? 8'h08 : reset_hold_cycles));
        sequence_complete = (sequence_counter >= 8'h08);  // 8 cycles per stage
        
        case (reset_state)
            RESET_IDLE: begin
                if (reset_request) begin
                    reset_state_next = RESET_DETECTED;
                end
            end
            
            RESET_DETECTED: begin
                reset_state_next = RESET_HOLD;
            end
            
            RESET_HOLD: begin
                if (hold_time_expired) begin
                    reset_state_next = RESET_WAIT_PLL;
                end
            end
            
            RESET_WAIT_PLL: begin
                // For simulation, assume PLL locks quickly if not provided
                if (pll_locked_sync || $isunknown(pll_locked)) begin
                    reset_state_next = RESET_WAIT_CLOCKS;
                end
            end
            
            RESET_WAIT_CLOCKS: begin
                // For simulation, assume clocks stabilize quickly if not provided
                if (clocks_stable_sync || $isunknown(clocks_stable)) begin
                    reset_state_next = RESET_RELEASE_MEM;
                end
            end
            
            RESET_RELEASE_MEM: begin
                if (sequence_complete) begin
                    reset_state_next = RESET_RELEASE_DEBUG;
                end
            end
            
            RESET_RELEASE_DEBUG: begin
                if (sequence_complete) begin
                    reset_state_next = RESET_RELEASE_PERIPH;
                end
            end
            
            RESET_RELEASE_PERIPH: begin
                if (sequence_complete) begin
                    reset_state_next = RESET_RELEASE_RT;
                end
            end
            
            RESET_RELEASE_RT: begin
                if (sequence_complete) begin
                    reset_state_next = RESET_RELEASE_GP;
                end
            end
            
            RESET_RELEASE_GP: begin
                if (sequence_complete) begin
                    reset_state_next = RESET_COMPLETE;
                end
            end
            
            RESET_COMPLETE: begin
                reset_state_next = RESET_IDLE;
            end
            
            RESET_ERROR: begin
                reset_state_next = RESET_DETECTED;
            end
            
            default: begin
                reset_state_next = RESET_ERROR;
            end
        endcase
    end
    
    //--------------------------------------------------------------------------
    // Reset Signal Generation
    //--------------------------------------------------------------------------
    always_comb begin
        // Default: all resets active
        system_reset_int = 1'b0;
        mem_reset_int = 1'b0;
        debug_reset_int = 1'b0;
        periph_reset_int = 1'b0;
        rt_core_reset_int = 1'b0;
        gp_core_reset_int = 1'b0;
        
        case (reset_state)
            RESET_IDLE,
            RESET_COMPLETE: begin
                // All resets released
                system_reset_int = 1'b1;
                mem_reset_int = 1'b1;
                debug_reset_int = 1'b1;
                periph_reset_int = 1'b1;
                rt_core_reset_int = 1'b1;
                gp_core_reset_int = 1'b1;
            end
            
            RESET_RELEASE_MEM: begin
                system_reset_int = 1'b1;
                mem_reset_int = 1'b1;
            end
            
            RESET_RELEASE_DEBUG: begin
                system_reset_int = 1'b1;
                mem_reset_int = 1'b1;
                debug_reset_int = 1'b1;
            end
            
            RESET_RELEASE_PERIPH: begin
                system_reset_int = 1'b1;
                mem_reset_int = 1'b1;
                debug_reset_int = 1'b1;
                periph_reset_int = 1'b1;
            end
            
            RESET_RELEASE_RT: begin
                system_reset_int = 1'b1;
                mem_reset_int = 1'b1;
                debug_reset_int = 1'b1;
                periph_reset_int = 1'b1;
                rt_core_reset_int = 1'b1;
            end
            
            RESET_RELEASE_GP: begin
                system_reset_int = 1'b1;
                mem_reset_int = 1'b1;
                debug_reset_int = 1'b1;
                periph_reset_int = 1'b1;
                rt_core_reset_int = 1'b1;
                gp_core_reset_int = 1'b1;
            end
            
            default: begin
                // All resets active (DETECTED, HOLD, WAIT_* states)
                system_reset_int = 1'b0;
                mem_reset_int = 1'b0;
                debug_reset_int = 1'b0;
                periph_reset_int = 1'b0;
                rt_core_reset_int = 1'b0;
                gp_core_reset_int = 1'b0;
            end
        endcase
    end
    
    //--------------------------------------------------------------------------
    // Reset Synchronizers for Each Clock Domain
    //--------------------------------------------------------------------------
    // System reset synchronizer
    always_ff @(posedge clk_gp_100mhz or negedge system_reset_int) begin
        if (!system_reset_int) begin
            system_reset_sync <= 3'b000;
        end else begin
            system_reset_sync <= {system_reset_sync[1:0], 1'b1};
        end
    end
    
    // RT-Core reset synchronizer
    always_ff @(posedge clk_rt_50mhz or negedge rt_core_reset_int) begin
        if (!rt_core_reset_int) begin
            rt_reset_sync <= 3'b000;
        end else begin
            rt_reset_sync <= {rt_reset_sync[1:0], 1'b1};
        end
    end
    
    // GP-Core reset synchronizer
    always_ff @(posedge clk_gp_100mhz or negedge gp_core_reset_int) begin
        if (!gp_core_reset_int) begin
            gp_reset_sync <= 3'b000;
        end else begin
            gp_reset_sync <= {gp_reset_sync[1:0], 1'b1};
        end
    end
    
    // Peripheral reset synchronizer
    always_ff @(posedge clk_periph_25mhz or negedge periph_reset_int) begin
        if (!periph_reset_int) begin
            periph_reset_sync <= 3'b000;
        end else begin
            periph_reset_sync <= {periph_reset_sync[1:0], 1'b1};
        end
    end
    
    // Memory reset synchronizer
    always_ff @(posedge clk_gp_100mhz or negedge mem_reset_int) begin
        if (!mem_reset_int) begin
            mem_reset_sync <= 3'b000;
        end else begin
            mem_reset_sync <= {mem_reset_sync[1:0], 1'b1};
        end
    end
    
    // Debug reset synchronizer
    always_ff @(posedge clk_debug_10mhz or negedge debug_reset_int) begin
        if (!debug_reset_int) begin
            debug_reset_sync <= 3'b000;
        end else begin
            debug_reset_sync <= {debug_reset_sync[1:0], 1'b1};
        end
    end
    
    //--------------------------------------------------------------------------
    // Uptime Counter
    //--------------------------------------------------------------------------
    always_ff @(posedge clk_gp_100mhz or negedge rst_n_system) begin
        if (!rst_n_system) begin
            uptime_cnt <= 32'h0;
        end else begin
            uptime_cnt <= uptime_cnt + 1;
        end
    end
    
    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    assign rst_n_system = system_reset_sync[2];
    assign rst_n_rt_core = rt_reset_sync[2];
    assign rst_n_gp_core = gp_reset_sync[2];
    assign rst_n_peripherals = periph_reset_sync[2];
    assign rst_n_memory = mem_reset_sync[2];
    assign rst_n_debug = debug_reset_sync[2];
    
    assign reset_cause = reset_cause_reg;
    assign reset_sequence_done = (reset_state == RESET_COMPLETE) || (reset_state == RESET_IDLE);
    assign cores_ready = rst_n_rt_core && rst_n_gp_core && reset_sequence_done;
    
    assign reset_counter = {8'h00, sequence_counter};
    assign uptime_counter = uptime_cnt;
    
    //--------------------------------------------------------------------------
    // Simulation-Only Debug
    //--------------------------------------------------------------------------
    // synthesis translate_off
    always @(posedge clk_gp_100mhz) begin
        if (reset_state != $past(reset_state)) begin
            case (reset_state)
                RESET_DETECTED:      $display("Reset Controller: Reset detected, cause=%0d", reset_cause_reg);
                RESET_HOLD:          $display("Reset Controller: Holding reset");
                RESET_WAIT_PLL:      $display("Reset Controller: Waiting for PLL lock");
                RESET_WAIT_CLOCKS:   $display("Reset Controller: Waiting for clock stability");
                RESET_RELEASE_MEM:   $display("Reset Controller: Releasing memory reset");
                RESET_RELEASE_DEBUG: $display("Reset Controller: Releasing debug reset");
                RESET_RELEASE_PERIPH: $display("Reset Controller: Releasing peripheral reset");
                RESET_RELEASE_RT:    $display("Reset Controller: Releasing RT-Core reset");
                RESET_RELEASE_GP:    $display("Reset Controller: Releasing GP-Core reset");
                RESET_COMPLETE:      $display("Reset Controller: Reset sequence complete");
                RESET_ERROR:         $display("Reset Controller: ERROR state entered");
                RESET_IDLE:          $display("Reset Controller: Entering idle state");
            endcase
        end
    end
    
    initial begin
        $display("MAKu Reset Controller Configuration:");
        $display("  Reset sequence stages: Memory->Debug->Peripherals->RT-Core->GP-Core");
        $display("  Default hold cycles: %0d", reset_hold_cycles);
        $display("  Quick reset mode available");
    end
    // synthesis translate_on

endmodule
