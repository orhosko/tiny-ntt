`timescale 1ns / 1ps

//==============================================================================
// NTT Coefficient Banked Memory - Optimized with Hardwired Reads
//==============================================================================
// Optimized coefficient storage for NTT with:
//   - 32 individual dual-port RAM banks (16 per ping-pong set)
//   - HARDWIRED read connections (lane i reads banks 2i and 2i+1)
//   - Write crossbar for dynamic bank selection
//   - External read interface uses separate read port (no sharing)
//
// CG NTT Read Pattern (conflict-free):
//   Lane 0: banks 0, 1    Lane 4: banks 8, 9
//   Lane 1: banks 2, 3    Lane 5: banks 10, 11
//   Lane 2: banks 4, 5    Lane 6: banks 12, 13
//   Lane 3: banks 6, 7    Lane 7: banks 14, 15
//
// This eliminates the 16:1 read muxes, saving ~7,500 LUTs.
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
    // Read Interface (read final results) - 1-cycle latency (BRAM)
    //==========================================================================
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [WIDTH-1:0]      read_data,

    //==========================================================================
    // Butterfly Read Interface (parallel coefficient access) - 1-cycle latency
    //==========================================================================
    input  logic                                        read_bank_sel,  // 0=A, 1=B
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0]    rd_bank_a,      // Bank select for coeff a (for assertions)
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0]   rd_index_a,     // Index within bank for a
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0]    rd_bank_b,      // Bank select for coeff b (for assertions)
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0]   rd_index_b,     // Index within bank for b
    output logic [PARALLEL-1:0][WIDTH-1:0]              coeff_a,        // Coefficient a output (registered)
    output logic [PARALLEL-1:0][WIDTH-1:0]              coeff_b,        // Coefficient b output (registered)

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
  // Helper Functions
  //============================================================================
  
  function automatic [ADDR_WIDTH-1:0] bit_reverse(input logic [ADDR_WIDTH-1:0] value);
    logic [ADDR_WIDTH-1:0] reversed;
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
  // Bank Interface Signals
  //============================================================================
  
  // Butterfly read addresses (port A of each bank)
  logic [BANK_DEPTH_WIDTH-1:0] bank_bf_rd_addr_a [0:BANKS-1];  // Butterfly read addr for ping-pong A
  logic [BANK_DEPTH_WIDTH-1:0] bank_bf_rd_addr_b [0:BANKS-1];  // Butterfly read addr for ping-pong B
  
  // Butterfly read data (port A output)
  logic [WIDTH-1:0] bank_bf_rd_data_a [0:BANKS-1];
  logic [WIDTH-1:0] bank_bf_rd_data_b [0:BANKS-1];
  
  // External read data (port B output)
  logic [WIDTH-1:0] bank_ext_rd_data_a [0:BANKS-1];
  logic [WIDTH-1:0] bank_ext_rd_data_b [0:BANKS-1];
  
  // Write port 1 (result_a) - for each bank in ping-pong sets A and B
  logic bank_wr_en_1_a [0:BANKS-1];
  logic bank_wr_en_1_b [0:BANKS-1];
  logic [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_1_a [0:BANKS-1];
  logic [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_1_b [0:BANKS-1];
  logic [WIDTH-1:0] bank_wr_data_1_a [0:BANKS-1];
  logic [WIDTH-1:0] bank_wr_data_1_b [0:BANKS-1];
  
  // Write port 2 (result_b) - for each bank in ping-pong sets A and B
  logic bank_wr_en_2_a [0:BANKS-1];
  logic bank_wr_en_2_b [0:BANKS-1];
  logic [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_2_a [0:BANKS-1];
  logic [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_2_b [0:BANKS-1];
  logic [WIDTH-1:0] bank_wr_data_2_a [0:BANKS-1];
  logic [WIDTH-1:0] bank_wr_data_2_b [0:BANKS-1];

  //============================================================================
  // External Read Address Computation
  //============================================================================
  logic [BANK_ADDR_WIDTH-1:0] ext_rd_bank;
  logic [BANK_DEPTH_WIDTH-1:0] ext_rd_index;
  logic [BANK_ADDR_WIDTH-1:0] ext_rd_bank_reg;
  
  assign ext_rd_bank = get_bank(read_addr);
  assign ext_rd_index = get_index(read_addr);

  //============================================================================
  // Bank Instantiation (32 banks total: 16 for set A, 16 for set B)
  //============================================================================
  // Each bank has:
  //   - Read Port A: Butterfly access (hardwired to specific lanes)
  //   - Read Port B: External read access (shared, muxed by bank select)
  //   - Write Port 1: result_a write
  //   - Write Port 2: result_b write (for CG NTT dual-write requirement)
  
  generate
    for (genvar b = 0; b < BANKS; b++) begin : gen_banks
      // Ping-pong set A
      ntt_coeff_bank_single #(
          .WIDTH    (WIDTH),
          .DEPTH    (BANK_DEPTH),
          .ADDR_WIDTH(BANK_DEPTH_WIDTH)
      ) u_bank_a (
          .clk       (clk),
          .rd_addr_a (bank_bf_rd_addr_a[b]),    // Butterfly read
          .rd_data_a (bank_bf_rd_data_a[b]),
          .rd_addr_b (ext_rd_index),            // External read (all banks get same addr)
          .rd_data_b (bank_ext_rd_data_a[b]),
          .wr_en_1   (bank_wr_en_1_a[b]),
          .wr_addr_1 (bank_wr_addr_1_a[b]),
          .wr_data_1 (bank_wr_data_1_a[b]),
          .wr_en_2   (bank_wr_en_2_a[b]),
          .wr_addr_2 (bank_wr_addr_2_a[b]),
          .wr_data_2 (bank_wr_data_2_a[b])
      );
      
      // Ping-pong set B
      ntt_coeff_bank_single #(
          .WIDTH    (WIDTH),
          .DEPTH    (BANK_DEPTH),
          .ADDR_WIDTH(BANK_DEPTH_WIDTH)
      ) u_bank_b (
          .clk       (clk),
          .rd_addr_a (bank_bf_rd_addr_b[b]),    // Butterfly read
          .rd_data_a (bank_bf_rd_data_b[b]),
          .rd_addr_b (ext_rd_index),            // External read
          .rd_data_b (bank_ext_rd_data_b[b]),
          .wr_en_1   (bank_wr_en_1_b[b]),
          .wr_addr_1 (bank_wr_addr_1_b[b]),
          .wr_data_1 (bank_wr_data_1_b[b]),
          .wr_en_2   (bank_wr_en_2_b[b]),
          .wr_addr_2 (bank_wr_addr_2_b[b]),
          .wr_data_2 (bank_wr_data_2_b[b])
      );
    end
  endgenerate

  //============================================================================
  // Butterfly Read Address Routing (Hardwired)
  //============================================================================
  // Each lane reads from fixed banks: lane i reads banks 2i and 2i+1.
  // This is conflict-free for CG NTT access pattern.
  // External reads use the separate port B, no address muxing needed.
  
  generate
    for (genvar lane = 0; lane < PARALLEL; lane++) begin : gen_read_connections
      localparam int BANK_FOR_A = lane * 2;      // 0, 2, 4, 6, 8, 10, 12, 14
      localparam int BANK_FOR_B = lane * 2 + 1;  // 1, 3, 5, 7, 9, 11, 13, 15
      
      // Butterfly read addresses (hardwired, no mux needed)
      assign bank_bf_rd_addr_a[BANK_FOR_A] = rd_index_a[lane];
      assign bank_bf_rd_addr_b[BANK_FOR_A] = rd_index_a[lane];
      assign bank_bf_rd_addr_a[BANK_FOR_B] = rd_index_b[lane];
      assign bank_bf_rd_addr_b[BANK_FOR_B] = rd_index_b[lane];
      
      // Butterfly output mux: only 2:1 for ping-pong selection (not 16:1!)
      assign coeff_a[lane] = read_bank_sel ? bank_bf_rd_data_b[BANK_FOR_A] : bank_bf_rd_data_a[BANK_FOR_A];
      assign coeff_b[lane] = read_bank_sel ? bank_bf_rd_data_b[BANK_FOR_B] : bank_bf_rd_data_a[BANK_FOR_B];
    end
  endgenerate

  //============================================================================
  // External Read Interface
  //============================================================================
  // External reads use port B of the BRAMs, which is completely independent
  // of the butterfly read port A. This eliminates timing issues at the
  // NTT-to-read transition.
  //
  // The BRAM outputs are registered internally (1-cycle latency).
  // We register the bank select to align with the data.
  
  // Stage 1: Register bank select (aligned with BRAM read)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ext_rd_bank_reg <= '0;
    end else begin
      ext_rd_bank_reg <= ext_rd_bank;
    end
  end
  
  // Stage 2: Mux the correct bank's output (combinational on registered signals)
  always_comb begin
    if (OUTPUT_BANK == 0) begin
      read_data = bank_ext_rd_data_a[ext_rd_bank_reg];
    end else begin
      read_data = bank_ext_rd_data_b[ext_rd_bank_reg];
    end
  end

  //============================================================================
  // Write Crossbar (Combinational Logic)
  //============================================================================
  // Determines which bank receives a write based on:
  //   - Load phase: bit-reversed address determines bank (uses port 1)
  //   - Butterfly write-back: result_a uses port 1, result_b uses port 2
  //
  // Note: For CG NTT, wr_bank_a[lane] == wr_bank_b[lane] always (because
  // addr0_out and addr1_out differ by N/2, which is divisible by BANKS).
  // So we MUST use separate write ports for result_a and result_b.
  
  // Intermediate signals for load path
  logic [ADDR_WIDTH-1:0] load_addr_br;
  logic [BANK_ADDR_WIDTH-1:0] load_bank;
  logic [BANK_DEPTH_WIDTH-1:0] load_index;
  
  assign load_addr_br = bit_reverse(load_addr);
  assign load_bank = get_bank(load_addr_br);
  assign load_index = get_index(load_addr_br);
  
  always_comb begin
    // Default: no writes
    for (int b = 0; b < BANKS; b++) begin
      // Write port 1 (for result_a and load)
      bank_wr_en_1_a[b] = 1'b0;
      bank_wr_en_1_b[b] = 1'b0;
      bank_wr_addr_1_a[b] = '0;
      bank_wr_addr_1_b[b] = '0;
      bank_wr_data_1_a[b] = '0;
      bank_wr_data_1_b[b] = '0;
      // Write port 2 (for result_b)
      bank_wr_en_2_a[b] = 1'b0;
      bank_wr_en_2_b[b] = 1'b0;
      bank_wr_addr_2_a[b] = '0;
      bank_wr_addr_2_b[b] = '0;
      bank_wr_data_2_a[b] = '0;
      bank_wr_data_2_b[b] = '0;
    end
    
    if (load_enable) begin
      // Load phase: write to bank_a via port 1 based on bit-reversed address
      bank_wr_en_1_a[load_bank] = 1'b1;
      bank_wr_addr_1_a[load_bank] = load_index;
      bank_wr_data_1_a[load_bank] = load_data;
    end else if (write_enable) begin
      // Butterfly write-back phase
      // result_a goes to port 1, result_b goes to port 2
      for (int lane = 0; lane < PARALLEL; lane++) begin
        if (wr_valid[lane]) begin
          if (write_bank_sel) begin
            // Write to ping-pong set B
            // Port 1: result_a
            bank_wr_en_1_b[wr_bank_a[lane]] = 1'b1;
            bank_wr_addr_1_b[wr_bank_a[lane]] = wr_index_a[lane];
            bank_wr_data_1_b[wr_bank_a[lane]] = result_a[lane];
            // Port 2: result_b
            bank_wr_en_2_b[wr_bank_b[lane]] = 1'b1;
            bank_wr_addr_2_b[wr_bank_b[lane]] = wr_index_b[lane];
            bank_wr_data_2_b[wr_bank_b[lane]] = result_b[lane];
          end else begin
            // Write to ping-pong set A
            // Port 1: result_a
            bank_wr_en_1_a[wr_bank_a[lane]] = 1'b1;
            bank_wr_addr_1_a[wr_bank_a[lane]] = wr_index_a[lane];
            bank_wr_data_1_a[wr_bank_a[lane]] = result_a[lane];
            // Port 2: result_b
            bank_wr_en_2_a[wr_bank_b[lane]] = 1'b1;
            bank_wr_addr_2_a[wr_bank_b[lane]] = wr_index_b[lane];
            bank_wr_data_2_a[wr_bank_b[lane]] = result_b[lane];
          end
        end
      end
    end
  end

  //============================================================================
  // Assertions (Simulation Only)
  //============================================================================
  
`ifdef SIMULATION
  // Verify read bank mapping is correct (lane i should read banks 2i and 2i+1)
  generate
    for (genvar lane = 0; lane < PARALLEL; lane++) begin : gen_rd_assertions
      always @(posedge clk) begin
        if (write_enable && wr_valid[lane]) begin
          // Only check when there's active computation
          assert (rd_bank_a[lane] == lane * 2)
            else $error("Lane %0d rd_bank_a mismatch: expected %0d, got %0d", 
                        lane, lane * 2, rd_bank_a[lane]);
          assert (rd_bank_b[lane] == lane * 2 + 1)
            else $error("Lane %0d rd_bank_b mismatch: expected %0d, got %0d", 
                        lane, lane * 2 + 1, rd_bank_b[lane]);
        end
      end
    end
  endgenerate

  // Detect write conflicts (multiple sources writing to same bank)
  always @(posedge clk) begin
    if (write_enable) begin
      for (int b = 0; b < BANKS; b++) begin
        automatic int wr_count = 0;
        for (int lane = 0; lane < PARALLEL; lane++) begin
          if (wr_valid[lane]) begin
            if (wr_bank_a[lane] == b) wr_count++;
            if (wr_bank_b[lane] == b) wr_count++;
          end
        end
        assert (wr_count <= 1)
          else $error("Write conflict: %0d writes to bank %0d in same cycle", wr_count, b);
      end
    end
  end
`endif

endmodule
