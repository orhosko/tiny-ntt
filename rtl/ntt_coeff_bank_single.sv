`timescale 1ns / 1ps

//==============================================================================
// Single Coefficient Bank - True Dual-Port RAM with Dual Write
//==============================================================================
// A single bank of coefficient storage for NTT.
// Ports:
// - Port A: Butterfly read access (1-cycle latency)
// - Port B: External read access (1-cycle latency)
// - Write Port 1: result_a write
// - Write Port 2: result_b write (for CG NTT, both a and b go to same bank)
//
// Note: For CG NTT, output addresses addr0_out and addr1_out always go to
// the same bank (because addr1_out = addr0_out + N/2, and N/2 is divisible
// by BANKS). So we need dual write capability.
//
// Let Vivado decide RAM style (LUTRAM vs BRAM) based on size and utilization.
//==============================================================================

module ntt_coeff_bank_single #(
    parameter int WIDTH     = 32,
    parameter int DEPTH     = 16,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic clk,
    
    // Read port A - Butterfly access (synchronous, 1-cycle latency)
    input  logic [ADDR_WIDTH-1:0] rd_addr_a,
    output logic [WIDTH-1:0]      rd_data_a,
    
    // Read port B - External access (synchronous, 1-cycle latency)
    input  logic [ADDR_WIDTH-1:0] rd_addr_b,
    output logic [WIDTH-1:0]      rd_data_b,
    
    // Write port 1 (synchronous)
    input  logic                  wr_en_1,
    input  logic [ADDR_WIDTH-1:0] wr_addr_1,
    input  logic [WIDTH-1:0]      wr_data_1,
    
    // Write port 2 (synchronous)
    input  logic                  wr_en_2,
    input  logic [ADDR_WIDTH-1:0] wr_addr_2,
    input  logic [WIDTH-1:0]      wr_data_2
);

  //============================================================================
  // Memory Array
  //============================================================================
  // Let Vivado choose optimal RAM style based on size
  // Initialize to zero for simulation
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  
  // Initialize memory to zero (for simulation)
  initial begin
    integer i;
    for (i = 0; i < DEPTH; i = i + 1) begin
      mem[i] = '0;
    end
  end

  //============================================================================
  // Read Port A - Butterfly Access (Synchronous)
  //============================================================================
  always_ff @(posedge clk) begin
    rd_data_a <= mem[rd_addr_a];
  end

  //============================================================================
  // Read Port B - External Access (Synchronous)
  //============================================================================
  always_ff @(posedge clk) begin
    rd_data_b <= mem[rd_addr_b];
  end

  //============================================================================
  // Write Ports (Synchronous)
  //============================================================================
  // Both writes happen in the same always_ff block to ensure proper
  // simulation behavior. In hardware, this requires dual-write-port RAM
  // or the synthesizer to handle multiple writes.
  always_ff @(posedge clk) begin
    if (wr_en_1) begin
      mem[wr_addr_1] <= wr_data_1;
    end
    if (wr_en_2) begin
      mem[wr_addr_2] <= wr_data_2;
    end
  end

endmodule
