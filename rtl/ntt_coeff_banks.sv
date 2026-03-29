`timescale 1ns / 1ps

//==============================================================================
// NTT Coefficient Banked Memory
//==============================================================================
// Isolates all coefficient storage and banking logic for NTT.
// This module handles:
//   - Banked memory storage (A and B banks for ping-pong)
//   - Parallel read access for butterflies (8 lanes × 2 coefficients)
//   - Parallel write-back from butterflies
//   - Load interface for initial coefficients
//   - Read interface for final results
//
// Banking scheme: 16 banks × 16 depth = 256 coefficients
// Each lane reads from a pair of consecutive banks (conflict-free for CG NTT)
//==============================================================================

module ntt_coeff_banks #(
    parameter int N                = 256,
    parameter int WIDTH            = 32,
    parameter int ADDR_WIDTH       = $clog2(N),
    parameter int PARALLEL         = 8,
    parameter int BANKS            = PARALLEL * 2,  // 16 banks for 8 parallel
    parameter int BANK_DEPTH       = (N + BANKS - 1) / BANKS,
    parameter int BANK_ADDR_WIDTH  = $clog2(BANKS),
    parameter int BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH),
    parameter int PIPE_DEPTH       = 4,  // Pipeline depth for write-back alignment
    parameter int OUTPUT_BANK      = 0   // Which bank (A=0, B=1) has final results
) (
    input  logic clk,
    input  logic rst_n,

    //==========================================================================
    // Load Interface (write initial coefficients)
    //==========================================================================
    input  logic                  load_enable,
    input  logic [ADDR_WIDTH-1:0] load_addr,
    input  logic [WIDTH-1:0]      load_data,

    //==========================================================================
    // Read Interface (read final results)
    //==========================================================================
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [WIDTH-1:0]      read_data,

    //==========================================================================
    // Butterfly Read Interface (parallel coefficient access)
    //==========================================================================
    input  logic                                        read_bank_sel,  // 0=A, 1=B
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0]    rd_bank_a,      // Bank select for coeff a
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0]   rd_index_a,     // Index within bank for a
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0]    rd_bank_b,      // Bank select for coeff b
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0]   rd_index_b,     // Index within bank for b
    output logic [PARALLEL-1:0][WIDTH-1:0]              coeff_a,        // Coefficient a output
    output logic [PARALLEL-1:0][WIDTH-1:0]              coeff_b,        // Coefficient b output

    //==========================================================================
    // Butterfly Write Interface (parallel result write-back)
    //==========================================================================
    input  logic                                        write_enable,
    input  logic                                        write_bank_sel, // 0=A, 1=B
    input  logic [PARALLEL-1:0]                         wr_valid,       // Per-lane write valid
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0]    wr_bank_a,      // Bank for result a
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0]   wr_index_a,     // Index for result a
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0]    wr_bank_b,      // Bank for result b
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0]   wr_index_b,     // Index for result b
    input  logic [PARALLEL-1:0][WIDTH-1:0]              result_a,       // Butterfly output a
    input  logic [PARALLEL-1:0][WIDTH-1:0]              result_b        // Butterfly output b
);

  //============================================================================
  // Memory Arrays
  //============================================================================
  // Two sets of banked memory for ping-pong operation between stages
  
  (* ram_style = "distributed" *) logic [WIDTH-1:0] mem_bank_a [0:BANKS-1][0:BANK_DEPTH-1];
  (* ram_style = "distributed" *) logic [WIDTH-1:0] mem_bank_b [0:BANKS-1][0:BANK_DEPTH-1];

  //============================================================================
  // Helper Functions
  //============================================================================
  
  function automatic [ADDR_WIDTH-1:0] bit_reverse(input logic [ADDR_WIDTH-1:0] value);
    automatic logic [ADDR_WIDTH-1:0] reversed;
    for (int i = 0; i < ADDR_WIDTH; i++) begin
      reversed[i] = value[ADDR_WIDTH-1-i];
    end
    return reversed;
  endfunction

  function automatic [BANK_ADDR_WIDTH-1:0] get_bank(input logic [ADDR_WIDTH-1:0] addr);
    return addr[BANK_ADDR_WIDTH-1:0];  // addr % BANKS (BANKS is power of 2)
  endfunction

  function automatic [BANK_DEPTH_WIDTH-1:0] get_index(input logic [ADDR_WIDTH-1:0] addr);
    return addr[ADDR_WIDTH-1:BANK_ADDR_WIDTH];  // addr / BANKS
  endfunction

  //============================================================================
  // Read Interface (Final Results)
  //============================================================================
  // Synchronous read for external result access
  
  always_ff @(posedge clk) begin
    if (OUTPUT_BANK == 0) begin
      read_data <= mem_bank_a[get_bank(read_addr)][get_index(read_addr)];
    end else begin
      read_data <= mem_bank_b[get_bank(read_addr)][get_index(read_addr)];
    end
  end

  //============================================================================
  // Butterfly Read Interface (Parallel Coefficient Access)
  //============================================================================
  // Combinational reads - each lane reads from its designated banks
  // Note: For CG NTT, lane i reads consecutive addresses 2i and 2i+1,
  // which map to banks 2i and 2i+1 (conflict-free)
  
  always_comb begin
    for (int lane = 0; lane < PARALLEL; lane++) begin
      if (read_bank_sel) begin
        // Read from bank B
        coeff_a[lane] = mem_bank_b[rd_bank_a[lane]][rd_index_a[lane]];
        coeff_b[lane] = mem_bank_b[rd_bank_b[lane]][rd_index_b[lane]];
      end else begin
        // Read from bank A
        coeff_a[lane] = mem_bank_a[rd_bank_a[lane]][rd_index_a[lane]];
        coeff_b[lane] = mem_bank_a[rd_bank_b[lane]][rd_index_b[lane]];
      end
    end
  end

  //============================================================================
  // Memory Write Logic
  //============================================================================
  // Handles both initial coefficient loading and butterfly write-back
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset all memory to zero
      for (int bank = 0; bank < BANKS; bank++) begin
        for (int idx = 0; idx < BANK_DEPTH; idx++) begin
          mem_bank_a[bank][idx] <= '0;
          mem_bank_b[bank][idx] <= '0;
        end
      end
    end else if (load_enable) begin
      // Load initial coefficients (bit-reversed addressing)
      mem_bank_a[get_bank(bit_reverse(load_addr))][get_index(bit_reverse(load_addr))] <= load_data;
    end else if (write_enable) begin
      // Write-back butterfly results
      for (int lane = 0; lane < PARALLEL; lane++) begin
        if (wr_valid[lane]) begin
          if (write_bank_sel) begin
            // Write to bank B
            mem_bank_b[wr_bank_a[lane]][wr_index_a[lane]] <= result_a[lane];
            mem_bank_b[wr_bank_b[lane]][wr_index_b[lane]] <= result_b[lane];
          end else begin
            // Write to bank A
            mem_bank_a[wr_bank_a[lane]][wr_index_a[lane]] <= result_a[lane];
            mem_bank_a[wr_bank_b[lane]][wr_index_b[lane]] <= result_b[lane];
          end
        end
      end
    end
  end

endmodule
