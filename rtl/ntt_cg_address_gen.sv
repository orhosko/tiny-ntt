`timescale 1ns / 1ps

//==============================================================================
// Constant-Geometry Address Generator
//==============================================================================

module ntt_cg_address_gen #(
    parameter int N = 256,
    parameter int ADDR_WIDTH = $clog2(N),
    parameter int PARALLEL = 8,
    parameter int BANKS = 16,
    parameter int BANK_ADDR_WIDTH = $clog2(BANKS),
    parameter int BANK_DEPTH_WIDTH = $clog2((N + BANKS - 1) / BANKS)
) (
    input  logic [$clog2(N)-1:0] stage,
    input  logic [$clog2(N/2)-1:0] butterfly_base,
    input  logic [PARALLEL-1:0] lane_valid,
    output logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0,
    output logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1,
    output logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0_out,
    output logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1_out,
    output logic [PARALLEL-1:0][ADDR_WIDTH-1:0] twiddle_addr,
    output logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_bank,
    output logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_bank,
    output logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_index,
    output logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_index,
    output logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank,
    output logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank,
    output logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index,
    output logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index
);

  localparam int LOGN = $clog2(N);

  function automatic [BANK_ADDR_WIDTH-1:0] bank_sel(input logic [ADDR_WIDTH-1:0] addr);
    return addr % BANKS;
  endfunction

  function automatic [BANK_DEPTH_WIDTH-1:0] bank_index(input logic [ADDR_WIDTH-1:0] addr);
    return addr / BANKS;
  endfunction

  always_comb begin
    int unsigned block_size_int;

    block_size_int = N >> (stage + 1);

    for (int lane = 0; lane < PARALLEL; lane++) begin
      int unsigned butterfly_idx;
      int unsigned group;
      int unsigned addr0_int;
      int unsigned addr1_int;
      int unsigned twiddle_exp;

      butterfly_idx = butterfly_base + lane;

      if (lane_valid[lane]) begin
        group = butterfly_idx >> (LOGN - stage - 1);

        // CG NTT: read consecutive pairs, write strided
        addr0_int = 2 * butterfly_idx;
        addr1_int = addr0_int + 1;

        addr0[lane] = ADDR_WIDTH'(addr0_int);
        addr1[lane] = ADDR_WIDTH'(addr1_int);

        addr0_bank[lane] = bank_sel(addr0[lane]);
        addr1_bank[lane] = bank_sel(addr1[lane]);
        addr0_index[lane] = bank_index(addr0[lane]);
        addr1_index[lane] = bank_index(addr1[lane]);

        addr0_out[lane] = ADDR_WIDTH'(butterfly_idx);
        addr1_out[lane] = ADDR_WIDTH'(butterfly_idx + (N >> 1));
        addr0_out_bank[lane] = bank_sel(addr0_out[lane]);
        addr1_out_bank[lane] = bank_sel(addr1_out[lane]);
        addr0_out_index[lane] = bank_index(addr0_out[lane]);
        addr1_out_index[lane] = bank_index(addr1_out[lane]);

        twiddle_exp = (block_size_int * group) << 1;
        twiddle_addr[lane] = ADDR_WIDTH'(twiddle_exp);
      end else begin
        addr0[lane] = '0;
        addr1[lane] = '0;
        addr0_bank[lane] = '0;
        addr1_bank[lane] = '0;
        addr0_index[lane] = '0;
        addr1_index[lane] = '0;
        addr0_out[lane] = '0;
        addr1_out[lane] = '0;
        addr0_out_bank[lane] = '0;
        addr1_out_bank[lane] = '0;
        addr0_out_index[lane] = '0;
        addr1_out_index[lane] = '0;
        twiddle_addr[lane] = '0;
      end
    end
  end

endmodule
