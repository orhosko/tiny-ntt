`timescale 1ns / 1ps

module ntt_bank_io #(
    parameter N                = 256,
    parameter WIDTH            = 32,
    parameter ADDR_WIDTH       = $clog2(N),
    parameter PARALLEL         = 8,
    parameter BANKS            = 16,
    parameter BANK_ADDR_WIDTH  = $clog2(BANKS),
    parameter BANK_DEPTH_WIDTH = $clog2((N + BANKS - 1) / BANKS),
    parameter MULT_PIPELINE    = 3,
    parameter OUTPUT_BANK      = 0
) (
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             load_coeff,
    input  wire [ADDR_WIDTH-1:0]            load_addr,
    input  wire [WIDTH-1:0]                 load_data,
    input  wire [ADDR_WIDTH-1:0]            read_addr,
    output reg  [WIDTH-1:0]                 read_data,
    input  wire                             read_bank_sel,
    input  wire                             write_enable,
    input  wire [MULT_PIPELINE:0]           write_bank_sel_pipe,
    input  wire [(MULT_PIPELINE+1)*PARALLEL-1:0] lane_valid_pipe,
    input  wire [PARALLEL*BANK_ADDR_WIDTH-1:0]  addr0_bank,
    input  wire [PARALLEL*BANK_ADDR_WIDTH-1:0]  addr1_bank,
    input  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_index,
    input  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_index,
    input  wire [(MULT_PIPELINE+1)*PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe,
    input  wire [(MULT_PIPELINE+1)*PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe,
    input  wire [(MULT_PIPELINE+1)*PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe,
    input  wire [(MULT_PIPELINE+1)*PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe,
    input  wire [PARALLEL*WIDTH-1:0]        a_out,
    input  wire [PARALLEL*WIDTH-1:0]        b_out,
    output reg  [PARALLEL*WIDTH-1:0]        a_in,
    output reg  [PARALLEL*WIDTH-1:0]        b_in
);

  localparam BANK_DEPTH = (N + BANKS - 1) / BANKS;

  reg [WIDTH-1:0] mem_bank_a [0:BANKS-1][0:BANK_DEPTH-1];
  reg [WIDTH-1:0] mem_bank_b [0:BANKS-1][0:BANK_DEPTH-1];

  function [ADDR_WIDTH-1:0] bit_reverse;
    input [ADDR_WIDTH-1:0] value;
    integer i;
    reg [ADDR_WIDTH-1:0] reversed;
    begin
      reversed = 0;
      for (i = 0; i < ADDR_WIDTH; i = i + 1)
        reversed[i] = value[ADDR_WIDTH - 1 - i];
      bit_reverse = reversed;
    end
  endfunction

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

  always @(posedge clk) begin
    if (OUTPUT_BANK == 0)
      read_data <= mem_bank_a[bank_sel(read_addr)][bank_index(read_addr)];
    else
      read_data <= mem_bank_b[bank_sel(read_addr)][bank_index(read_addr)];
  end

  integer lane;
  always @(*) begin
    for (lane = 0; lane < PARALLEL; lane = lane + 1) begin
      if (read_bank_sel) begin
        a_in[lane*WIDTH +: WIDTH] =
            mem_bank_b[addr0_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH]]
                      [addr0_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH]];
        b_in[lane*WIDTH +: WIDTH] =
            mem_bank_b[addr1_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH]]
                      [addr1_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH]];
      end else begin
        a_in[lane*WIDTH +: WIDTH] =
            mem_bank_a[addr0_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH]]
                      [addr0_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH]];
        b_in[lane*WIDTH +: WIDTH] =
            mem_bank_a[addr1_bank[lane*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH]]
                      [addr1_index[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH]];
      end
    end
  end

  integer bank;
  integer idx;
  integer lane_idx;
  reg [BANK_ADDR_WIDTH-1:0] out_bank0_lane;
  reg [BANK_ADDR_WIDTH-1:0] out_bank1_lane;
  reg [BANK_DEPTH_WIDTH-1:0] out_index0_lane;
  reg [BANK_DEPTH_WIDTH-1:0] out_index1_lane;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (bank = 0; bank < BANKS; bank = bank + 1) begin
        for (idx = 0; idx < BANK_DEPTH; idx = idx + 1) begin
          mem_bank_a[bank][idx] <= 0;
          mem_bank_b[bank][idx] <= 0;
        end
      end
    end else if (load_coeff) begin
      mem_bank_a[bank_sel(bit_reverse(load_addr))][bank_index(bit_reverse(load_addr))] <= load_data;
    end else if (write_enable) begin
      for (lane_idx = 0; lane_idx < PARALLEL; lane_idx = lane_idx + 1) begin
        if (lane_valid_pipe[MULT_PIPELINE*PARALLEL + lane_idx]) begin
          out_bank0_lane = addr0_out_bank_pipe[(MULT_PIPELINE*PARALLEL + lane_idx)*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH];
          out_bank1_lane = addr1_out_bank_pipe[(MULT_PIPELINE*PARALLEL + lane_idx)*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH];
          out_index0_lane = addr0_out_index_pipe[(MULT_PIPELINE*PARALLEL + lane_idx)*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];
          out_index1_lane = addr1_out_index_pipe[(MULT_PIPELINE*PARALLEL + lane_idx)*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];
          if (write_bank_sel_pipe[MULT_PIPELINE]) begin
            mem_bank_b[out_bank0_lane][out_index0_lane] <= a_out[lane_idx*WIDTH +: WIDTH];
            mem_bank_b[out_bank1_lane][out_index1_lane] <= b_out[lane_idx*WIDTH +: WIDTH];
          end else begin
            mem_bank_a[out_bank0_lane][out_index0_lane] <= a_out[lane_idx*WIDTH +: WIDTH];
            mem_bank_a[out_bank1_lane][out_index1_lane] <= b_out[lane_idx*WIDTH +: WIDTH];
          end
        end
      end
    end
  end

endmodule
