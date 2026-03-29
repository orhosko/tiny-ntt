`timescale 1ns / 1ps

//==============================================================================
// Dual-Port BRAM for Twiddle Factors
//==============================================================================
// Synchronous dual-port RAM that infers BRAM on Xilinx FPGAs.
// Both ports are read-only for twiddle factor access.
// Initialized via $readmemh from a hex file.
//
// Features:
//   - Two independent read ports (A and B)
//   - Synchronous reads (1-cycle latency)
//   - Parameterized depth and width
//   - Hex file initialization for BRAM inference
//==============================================================================

module twiddle_bram #(
    parameter int WIDTH      = 32,           // Data width
    parameter int DEPTH      = 256,          // Number of entries
    parameter int ADDR_WIDTH = $clog2(DEPTH),// Address width
    parameter     HEX_FILE   = ""            // Hex file for initialization
) (
    input  logic                  clk,

    // Port A (read-only)
    input  logic [ADDR_WIDTH-1:0] addr_a,
    output logic [WIDTH-1:0]      data_a,

    // Port B (read-only)
    input  logic [ADDR_WIDTH-1:0] addr_b,
    output logic [WIDTH-1:0]      data_b
);

    // Memory array - will be inferred as BRAM
    (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

    // Initialize memory from hex file
    initial begin
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, mem);
        end else begin
            // Default initialization to avoid X values
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] = '0;
            end
        end
    end

    // Port A - synchronous read
    always_ff @(posedge clk) begin
        data_a <= mem[addr_a];
    end

    // Port B - synchronous read
    always_ff @(posedge clk) begin
        data_b <= mem[addr_b];
    end

endmodule
