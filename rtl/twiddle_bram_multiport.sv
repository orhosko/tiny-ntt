`timescale 1ns / 1ps

//==============================================================================
// Multi-Port BRAM for Twiddle Factors (8 Read Ports)
//==============================================================================
// Provides 8 parallel read ports for twiddle factors by instantiating
// 4 dual-port BRAMs, each storing a complete copy of the twiddle table.
//
// Architecture:
//   - 4 dual-port BRAMs (twiddle_bram instances)
//   - Each BRAM stores the full twiddle table (DEPTH entries)
//   - BRAM 0: ports for lane 0, 1
//   - BRAM 1: ports for lane 2, 3
//   - BRAM 2: ports for lane 4, 5
//   - BRAM 3: ports for lane 6, 7
//
// Timing:
//   - 1-cycle read latency (synchronous BRAM read)
//   - Addresses must be provided 1 cycle before data is needed
//
// Parameters:
//   - DEPTH: Number of twiddle entries (N for NTT size N)
//   - WIDTH: Bit width of twiddle factors
//   - PARALLEL: Number of parallel read ports (default 8)
//   - HEX_FILE: Path to hex file with precomputed twiddles
//==============================================================================

module twiddle_bram_multiport #(
    parameter int DEPTH      = 256,           // Number of twiddle entries
    parameter int WIDTH      = 32,            // Data width
    parameter int PARALLEL   = 8,             // Number of parallel read ports
    parameter int ADDR_WIDTH = $clog2(DEPTH), // Address width
    parameter     HEX_FILE   = ""             // Hex file for initialization
) (
    input  logic                  clk,

    // Read addresses (PARALLEL ports)
    input  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr,

    // Read data outputs (PARALLEL ports, 1-cycle latency)
    output logic [PARALLEL-1:0][WIDTH-1:0]      data
);

    // Number of dual-port BRAMs needed (each provides 2 read ports)
    localparam int NUM_BRAMS = (PARALLEL + 1) / 2;

    // Intermediary signals for addresses and data (workaround for iverilog bug
    // with packed array indexing in generate blocks)
    logic [ADDR_WIDTH-1:0] addr_a_arr [0:NUM_BRAMS-1];
    logic [ADDR_WIDTH-1:0] addr_b_arr [0:NUM_BRAMS-1];
    logic [WIDTH-1:0] data_a_arr [0:NUM_BRAMS-1];
    logic [WIDTH-1:0] data_b_arr [0:NUM_BRAMS-1];
    
    // Map packed array elements to unpacked for iverilog compatibility
    generate
        for (genvar i = 0; i < NUM_BRAMS; i++) begin : gen_arr_map
            localparam int LANE_A = i * 2;
            localparam int LANE_B = i * 2 + 1;
            
            // Input address mapping
            assign addr_a_arr[i] = addr[LANE_A];
            if (LANE_B < PARALLEL) begin : gen_lane_b_valid
                assign addr_b_arr[i] = addr[LANE_B];
            end else begin : gen_lane_b_zero
                assign addr_b_arr[i] = {ADDR_WIDTH{1'b0}};
            end
            
            // Output data mapping
            assign data[LANE_A] = data_a_arr[i];
            if (LANE_B < PARALLEL) begin : gen_data_b_valid
                assign data[LANE_B] = data_b_arr[i];
            end
        end
    endgenerate
    
    // Generate dual-port BRAMs
    generate
        for (genvar i = 0; i < NUM_BRAMS; i++) begin : gen_brams
            // Instantiate dual-port BRAM using unpacked intermediaries
            twiddle_bram #(
                .WIDTH     (WIDTH),
                .DEPTH     (DEPTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .HEX_FILE  (HEX_FILE)
            ) u_bram (
                .clk   (clk),
                .addr_a(addr_a_arr[i]),
                .data_a(data_a_arr[i]),
                .addr_b(addr_b_arr[i]),
                .data_b(data_b_arr[i])
            );
        end
    endgenerate

endmodule
