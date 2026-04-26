`timescale 1ns / 1ps

module ntt_cg_address_gen #(
    parameter N                = 4096,
    parameter ADDR_WIDTH       = $clog2(N),
    parameter PARALLEL         = 8,
    parameter BANKS            = 16,
    parameter BANK_ADDR_WIDTH  = $clog2(BANKS),
    parameter BANK_DEPTH_WIDTH = $clog2((N + BANKS - 1) / BANKS)
) (
    input  wire [$clog2(N)-1:0]              stage,
    input  wire [$clog2(N/2)-1:0]            butterfly_base,
    input  wire [PARALLEL-1:0]               lane_valid,
    output reg  [PARALLEL*ADDR_WIDTH-1:0]    addr0,
    output reg  [PARALLEL*ADDR_WIDTH-1:0]    addr1,
    output reg  [PARALLEL*ADDR_WIDTH-1:0]    addr0_out,
    output reg  [PARALLEL*ADDR_WIDTH-1:0]    addr1_out,
    output reg  [PARALLEL*ADDR_WIDTH-1:0]    twiddle_addr,
    output reg  [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_bank,
    output reg  [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_bank,
    output reg  [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_index,
    output reg  [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_index,
    output reg  [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_out_bank,
    output reg  [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_out_bank,
    output reg  [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_out_index,
    output reg  [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_out_index
);

  localparam LOGN = $clog2(N);

  integer lane;
  integer block_size_int;
  integer butterfly_idx;
  integer group;
  integer addr0_int;
  integer addr1_int;
  integer twiddle_exp;
  reg [ADDR_WIDTH-1:0] addr0_lane;
  reg [ADDR_WIDTH-1:0] addr1_lane;
  reg [ADDR_WIDTH-1:0] addr0_out_lane;
  reg [ADDR_WIDTH-1:0] addr1_out_lane;

  function [BANK_ADDR_WIDTH-1:0] bank_sel;
    input [ADDR_WIDTH-1:0] addr;
    begin
      bank_sel = addr % BANKS;
    end
  endfunction

  function [BANK_DEPTH_WIDTH-1:0] bank_index;
    input [ADDR_WIDTH-1:0] addr;
    begin
      bank_index = addr / BANKS;
    end
  endfunction

  always @(*) begin
    block_size_int = N >> (stage + 1);

    for (lane = 0; lane < PARALLEL; lane = lane + 1) begin
      butterfly_idx = butterfly_base + lane;

      if (lane_valid[lane]) begin
        group = butterfly_idx >> (LOGN - stage - 1);

        addr0_int = 2 * butterfly_idx;
        addr1_int = addr0_int + 1;

        addr0_lane = addr0_int[ADDR_WIDTH-1:0];
        addr1_lane = addr1_int[ADDR_WIDTH-1:0];
        addr0_out_lane = butterfly_idx;
        addr1_out_lane = butterfly_idx + (N >> 1);

        addr0[lane*ADDR_WIDTH +: ADDR_WIDTH] = addr0_lane;
        addr1[lane*ADDR_WIDTH +: ADDR_WIDTH] = addr1_lane;
        addr0_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = bank_sel(addr0_lane);
        addr1_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = bank_sel(addr1_lane);
        addr0_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = bank_index(addr0_lane);
        addr1_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = bank_index(addr1_lane);

        addr0_out[lane*ADDR_WIDTH +: ADDR_WIDTH] = addr0_out_lane;
        addr1_out[lane*ADDR_WIDTH +: ADDR_WIDTH] = addr1_out_lane;
        addr0_out_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = bank_sel(addr0_out_lane);
        addr1_out_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = bank_sel(addr1_out_lane);
        addr0_out_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = bank_index(addr0_out_lane);
        addr1_out_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = bank_index(addr1_out_lane);

        twiddle_exp = (block_size_int * group) << 1;
        twiddle_addr[lane*ADDR_WIDTH +: ADDR_WIDTH] = twiddle_exp[ADDR_WIDTH-1:0];
      end else begin
        addr0[lane*ADDR_WIDTH +: ADDR_WIDTH] = 0;
        addr1[lane*ADDR_WIDTH +: ADDR_WIDTH] = 0;
        addr0_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = 0;
        addr1_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = 0;
        addr0_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = 0;
        addr1_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = 0;
        addr0_out[lane*ADDR_WIDTH +: ADDR_WIDTH] = 0;
        addr1_out[lane*ADDR_WIDTH +: ADDR_WIDTH] = 0;
        addr0_out_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = 0;
        addr1_out_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH] = 0;
        addr0_out_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = 0;
        addr1_out_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH] = 0;
        twiddle_addr[lane*ADDR_WIDTH +: ADDR_WIDTH] = 0;
      end
    end
  end

endmodule
