`timescale 1ns / 1ps

//==============================================================================
// Banked Memory IO for NTT
//==============================================================================

module ntt_bank_io #(
    parameter int N = 256,
    parameter int WIDTH = 32,
    parameter int ADDR_WIDTH = $clog2(N),
    parameter int PARALLEL = 8,
    parameter int BANKS = 16,
    parameter int BANK_ADDR_WIDTH = $clog2(BANKS),
    parameter int BANK_DEPTH_WIDTH = $clog2((N + BANKS - 1) / BANKS),
    parameter int MULT_PIPELINE = 3,
    parameter int OUTPUT_BANK = 0
) (
    input  logic clk,
    input  logic rst_n,
    input  logic load_coeff,
    input  logic [ADDR_WIDTH-1:0] load_addr,
    input  logic [WIDTH-1:0] load_data,
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [WIDTH-1:0] read_data,
    input  logic read_bank_sel,
    input  logic write_enable,
    input  logic write_bank_sel_pipe [0:MULT_PIPELINE],
    input  logic [PARALLEL-1:0] lane_valid_pipe [0:MULT_PIPELINE],
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_bank,
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_bank,
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_index,
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_index,
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe [0:MULT_PIPELINE],
    input  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe [0:MULT_PIPELINE],
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe [0:MULT_PIPELINE],
    input  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe [0:MULT_PIPELINE],
    input  logic [PARALLEL-1:0][WIDTH-1:0] a_out,
    input  logic [PARALLEL-1:0][WIDTH-1:0] b_out,
    output logic [PARALLEL-1:0][WIDTH-1:0] a_in,
    output logic [PARALLEL-1:0][WIDTH-1:0] b_in
);

  localparam int BANK_DEPTH = (N + BANKS - 1) / BANKS;

  logic [WIDTH-1:0] mem_bank_a[0:BANKS-1][0:BANK_DEPTH-1];
  logic [WIDTH-1:0] mem_bank_b[0:BANKS-1][0:BANK_DEPTH-1];

  function automatic [ADDR_WIDTH-1:0] bit_reverse(input logic [ADDR_WIDTH-1:0] value);
    automatic logic [ADDR_WIDTH-1:0] reversed;
    for (int i = 0; i < ADDR_WIDTH; i++) begin
      reversed[i] = value[ADDR_WIDTH - 1 - i];
    end
    return reversed;
  endfunction

  function automatic [BANK_ADDR_WIDTH-1:0] bank_sel(input logic [ADDR_WIDTH-1:0] addr);
    return addr % BANKS;
  endfunction

  function automatic [BANK_DEPTH_WIDTH-1:0] bank_index(input logic [ADDR_WIDTH-1:0] addr);
    return addr / BANKS;
  endfunction

  // Read interface (synchronous)
  always_ff @(posedge clk) begin
    if (OUTPUT_BANK == 0) begin
      read_data <= mem_bank_a[bank_sel(read_addr)][bank_index(read_addr)];
    end else begin
      read_data <= mem_bank_b[bank_sel(read_addr)][bank_index(read_addr)];
    end
  end

  // Combinational reads for butterflies
  always_comb begin
    for (int lane = 0; lane < PARALLEL; lane++) begin
      if (read_bank_sel) begin
        a_in[lane] = mem_bank_b[addr0_bank[lane]][addr0_index[lane]];
        b_in[lane] = mem_bank_b[addr1_bank[lane]][addr1_index[lane]];
      end else begin
        a_in[lane] = mem_bank_a[addr0_bank[lane]][addr0_index[lane]];
        b_in[lane] = mem_bank_a[addr1_bank[lane]][addr1_index[lane]];
      end
    end
  end

  // Write-back results / load coefficients
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int bank = 0; bank < BANKS; bank++) begin
        for (int idx = 0; idx < BANK_DEPTH; idx++) begin
          mem_bank_a[bank][idx] <= '0;
          mem_bank_b[bank][idx] <= '0;
        end
      end
    end else if (load_coeff) begin
      mem_bank_a[bank_sel(bit_reverse(load_addr))][bank_index(bit_reverse(load_addr))] <= load_data;
    end else if (write_enable) begin
      for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
        if (lane_valid_pipe[MULT_PIPELINE][lane_idx]) begin
          if (write_bank_sel_pipe[MULT_PIPELINE]) begin
            mem_bank_b[addr0_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr0_out_index_pipe[MULT_PIPELINE][lane_idx]] <= a_out[lane_idx];
            mem_bank_b[addr1_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr1_out_index_pipe[MULT_PIPELINE][lane_idx]] <= b_out[lane_idx];
          end else begin
            mem_bank_a[addr0_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr0_out_index_pipe[MULT_PIPELINE][lane_idx]] <= a_out[lane_idx];
            mem_bank_a[addr1_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr1_out_index_pipe[MULT_PIPELINE][lane_idx]] <= b_out[lane_idx];
          end
        end
      end
    end
  end

endmodule
