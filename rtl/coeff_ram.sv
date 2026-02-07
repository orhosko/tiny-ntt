`timescale 1ns / 1ps

//==============================================================================
// Dual-Port RAM for NTT Coefficients
//==============================================================================
// Synchronous dual-port RAM for storing polynomial coefficients
// 
// Features:
//   - Two independent read/write ports (A and B)
//   - Synchronous reads and writes
//   - Configurable size and width
//
// Used for storing input/output coefficients during NTT computation
//==============================================================================

module coeff_ram #(
    parameter int WIDTH      = 32,   // Data width
    parameter int DEPTH      = 256,  // Number of entries
    parameter int ADDR_WIDTH = 8     // Address width (log2(DEPTH))
) (
    input logic clk,
    input logic rst_n,

    // Port A
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic [     WIDTH-1:0] din_a,
    output logic [     WIDTH-1:0] dout_a,
    input  logic                  we_a,

    // Port B  
    input  logic [ADDR_WIDTH-1:0] addr_b,
    input  logic [     WIDTH-1:0] din_b,
    output logic [     WIDTH-1:0] dout_b,
    input  logic                  we_b
);

  // Memory array
  logic [WIDTH-1:0] mem[0:DEPTH-1];

  // Initialize memory to avoid X values in simulation
  initial begin
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = '0;
    end
  end

  // Port A - synchronous read/write with WRITE-FIRST behavior
  always_ff @(posedge clk) begin
    if (we_a) begin
      mem[addr_a] <= din_a;
      dout_a <= din_a;  // Write-first: output gets written data immediately
    end else begin
      dout_a <= mem[addr_a];  // Normal read
    end
  end

  // Port B - synchronous read/write with WRITE-FIRST behavior  
  always_ff @(posedge clk) begin
    if (we_b) begin
      mem[addr_b] <= din_b;
      dout_b <= din_b;  // Write-first: output gets written data immediately
    end else begin
      dout_b <= mem[addr_b];  // Normal read
    end
  end

  // Optional: Reset memory (can be removed if not needed)
  // Note: Resetting large memories can be expensive in hardware
  // Commented out by default
  /*
    always_ff @(posedge cllk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
        end
    end
    */

endmodule
