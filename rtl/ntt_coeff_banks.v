`timescale 1ns / 1ps

module ntt_coeff_banks #(
    parameter N                = 1024,
    parameter WIDTH            = 32,
    parameter ADDR_WIDTH       = $clog2(N),
    parameter PARALLEL         = 8,
    parameter BANKS            = PARALLEL * 2,
    parameter BANK_DEPTH       = (N + BANKS - 1) / BANKS,
    parameter BANK_ADDR_WIDTH  = $clog2(BANKS),
    parameter BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH),
    parameter PIPE_DEPTH       = 4,
    parameter OUTPUT_BANK      = 0
) (
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire                             load_enable,
    input  wire [ADDR_WIDTH-1:0]            load_addr,
    input  wire [WIDTH-1:0]                 load_data,
    input  wire [ADDR_WIDTH-1:0]            read_addr,
    output reg  [WIDTH-1:0]                 read_data,
    input  wire                             read_bank_sel,
    input  wire [PARALLEL*BANK_ADDR_WIDTH-1:0]  rd_bank_a,
    input  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] rd_index_a,
    input  wire [PARALLEL*BANK_ADDR_WIDTH-1:0]  rd_bank_b,
    input  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] rd_index_b,
    output wire [PARALLEL*WIDTH-1:0]        coeff_a,
    output wire [PARALLEL*WIDTH-1:0]        coeff_b,
    input  wire                             write_enable,
    input  wire                             write_bank_sel,
    input  wire [PARALLEL-1:0]              wr_valid,
    input  wire [PARALLEL*BANK_ADDR_WIDTH-1:0]  wr_bank_a,
    input  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] wr_index_a,
    input  wire [PARALLEL*BANK_ADDR_WIDTH-1:0]  wr_bank_b,
    input  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] wr_index_b,
    input  wire [PARALLEL*WIDTH-1:0]        result_a,
    input  wire [PARALLEL*WIDTH-1:0]        result_b
);

  function [ADDR_WIDTH-1:0] bit_reverse;
    input [ADDR_WIDTH-1:0] value;
    integer i;
    reg [ADDR_WIDTH-1:0] reversed;
    begin
      reversed = 0;
      for (i = 0; i < ADDR_WIDTH; i = i + 1)
        reversed[i] = value[ADDR_WIDTH-1-i];
      bit_reverse = reversed;
    end
  endfunction

  function [BANK_ADDR_WIDTH-1:0] get_bank;
    input [ADDR_WIDTH-1:0] addr;
    begin
      get_bank = addr[BANK_ADDR_WIDTH-1:0];
    end
  endfunction

  function [BANK_DEPTH_WIDTH-1:0] get_index;
    input [ADDR_WIDTH-1:0] addr;
    begin
      get_index = addr[ADDR_WIDTH-1:BANK_ADDR_WIDTH];
    end
  endfunction

  wire [BANK_DEPTH_WIDTH-1:0] bank_bf_rd_addr_a [0:BANKS-1];
  wire [BANK_DEPTH_WIDTH-1:0] bank_bf_rd_addr_b [0:BANKS-1];
  wire [WIDTH-1:0] bank_bf_rd_data_a [0:BANKS-1];
  wire [WIDTH-1:0] bank_bf_rd_data_b [0:BANKS-1];
  wire [WIDTH-1:0] bank_ext_rd_data_a [0:BANKS-1];
  wire [WIDTH-1:0] bank_ext_rd_data_b [0:BANKS-1];

  reg bank_wr_en_1_a [0:BANKS-1];
  reg bank_wr_en_1_b [0:BANKS-1];
  reg [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_1_a [0:BANKS-1];
  reg [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_1_b [0:BANKS-1];
  reg [WIDTH-1:0] bank_wr_data_1_a [0:BANKS-1];
  reg [WIDTH-1:0] bank_wr_data_1_b [0:BANKS-1];
  reg bank_wr_en_2_a [0:BANKS-1];
  reg bank_wr_en_2_b [0:BANKS-1];
  reg [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_2_a [0:BANKS-1];
  reg [BANK_DEPTH_WIDTH-1:0] bank_wr_addr_2_b [0:BANKS-1];
  reg [WIDTH-1:0] bank_wr_data_2_a [0:BANKS-1];
  reg [WIDTH-1:0] bank_wr_data_2_b [0:BANKS-1];

  wire [BANK_ADDR_WIDTH-1:0] ext_rd_bank;
  wire [BANK_DEPTH_WIDTH-1:0] ext_rd_index;
  reg [BANK_ADDR_WIDTH-1:0] ext_rd_bank_reg;
  wire [ADDR_WIDTH-1:0] load_addr_br;
  wire [BANK_ADDR_WIDTH-1:0] load_bank;
  wire [BANK_DEPTH_WIDTH-1:0] load_index;

  assign ext_rd_bank = get_bank(read_addr);
  assign ext_rd_index = get_index(read_addr);
  assign load_addr_br = bit_reverse(load_addr);
  assign load_bank = get_bank(load_addr_br);
  assign load_index = get_index(load_addr_br);

  genvar b;
  generate
    for (b = 0; b < BANKS; b = b + 1) begin : gen_banks
      ntt_coeff_bank_single #(
          .WIDTH(WIDTH),
          .DEPTH(BANK_DEPTH),
          .ADDR_WIDTH(BANK_DEPTH_WIDTH)
      ) u_bank_a (
          .clk(clk),
          .rd_addr_a(bank_bf_rd_addr_a[b]),
          .rd_data_a(bank_bf_rd_data_a[b]),
          .rd_addr_b(ext_rd_index),
          .rd_data_b(bank_ext_rd_data_a[b]),
          .wr_en_1(bank_wr_en_1_a[b]),
          .wr_addr_1(bank_wr_addr_1_a[b]),
          .wr_data_1(bank_wr_data_1_a[b]),
          .wr_en_2(bank_wr_en_2_a[b]),
          .wr_addr_2(bank_wr_addr_2_a[b]),
          .wr_data_2(bank_wr_data_2_a[b])
      );

      ntt_coeff_bank_single #(
          .WIDTH(WIDTH),
          .DEPTH(BANK_DEPTH),
          .ADDR_WIDTH(BANK_DEPTH_WIDTH)
      ) u_bank_b (
          .clk(clk),
          .rd_addr_a(bank_bf_rd_addr_b[b]),
          .rd_data_a(bank_bf_rd_data_b[b]),
          .rd_addr_b(ext_rd_index),
          .rd_data_b(bank_ext_rd_data_b[b]),
          .wr_en_1(bank_wr_en_1_b[b]),
          .wr_addr_1(bank_wr_addr_1_b[b]),
          .wr_data_1(bank_wr_data_1_b[b]),
          .wr_en_2(bank_wr_en_2_b[b]),
          .wr_addr_2(bank_wr_addr_2_b[b]),
          .wr_data_2(bank_wr_data_2_b[b])
      );
    end
  endgenerate

  genvar lane;
  generate
    for (lane = 0; lane < PARALLEL; lane = lane + 1) begin : gen_read_connections
      localparam BANK_FOR_A = lane * 2;
      localparam BANK_FOR_B = lane * 2 + 1;

      assign bank_bf_rd_addr_a[BANK_FOR_A] = rd_index_a[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];
      assign bank_bf_rd_addr_b[BANK_FOR_A] = rd_index_a[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];
      assign bank_bf_rd_addr_a[BANK_FOR_B] = rd_index_b[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];
      assign bank_bf_rd_addr_b[BANK_FOR_B] = rd_index_b[lane*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];

      assign coeff_a[lane*WIDTH +: WIDTH] = read_bank_sel ? bank_bf_rd_data_b[BANK_FOR_A] : bank_bf_rd_data_a[BANK_FOR_A];
      assign coeff_b[lane*WIDTH +: WIDTH] = read_bank_sel ? bank_bf_rd_data_b[BANK_FOR_B] : bank_bf_rd_data_a[BANK_FOR_B];
    end
  endgenerate

  always @(posedge clk) begin
    if (!rst_n)
      ext_rd_bank_reg <= 0;
    else
      ext_rd_bank_reg <= ext_rd_bank;
  end

  always @(*) begin
    if (OUTPUT_BANK == 0)
      read_data = bank_ext_rd_data_a[ext_rd_bank_reg];
    else
      read_data = bank_ext_rd_data_b[ext_rd_bank_reg];
  end

  integer bi;
  integer li;
  reg [BANK_ADDR_WIDTH-1:0] wr_bank_a_lane;
  reg [BANK_ADDR_WIDTH-1:0] wr_bank_b_lane;
  reg [BANK_DEPTH_WIDTH-1:0] wr_index_a_lane;
  reg [BANK_DEPTH_WIDTH-1:0] wr_index_b_lane;
  reg [WIDTH-1:0] result_a_lane;
  reg [WIDTH-1:0] result_b_lane;
  always @(*) begin
    for (bi = 0; bi < BANKS; bi = bi + 1) begin
      bank_wr_en_1_a[bi] = 1'b0;
      bank_wr_en_1_b[bi] = 1'b0;
      bank_wr_addr_1_a[bi] = 0;
      bank_wr_addr_1_b[bi] = 0;
      bank_wr_data_1_a[bi] = 0;
      bank_wr_data_1_b[bi] = 0;
      bank_wr_en_2_a[bi] = 1'b0;
      bank_wr_en_2_b[bi] = 1'b0;
      bank_wr_addr_2_a[bi] = 0;
      bank_wr_addr_2_b[bi] = 0;
      bank_wr_data_2_a[bi] = 0;
      bank_wr_data_2_b[bi] = 0;
    end

    if (load_enable) begin
      bank_wr_en_1_a[load_bank] = 1'b1;
      bank_wr_addr_1_a[load_bank] = load_index;
      bank_wr_data_1_a[load_bank] = load_data;
    end else if (write_enable) begin
      for (li = 0; li < PARALLEL; li = li + 1) begin
        if (wr_valid[li]) begin
          wr_bank_a_lane = wr_bank_a[li*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH];
          wr_bank_b_lane = wr_bank_b[li*BANK_ADDR_WIDTH +: BANK_ADDR_WIDTH];
          wr_index_a_lane = wr_index_a[li*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];
          wr_index_b_lane = wr_index_b[li*BANK_DEPTH_WIDTH +: BANK_DEPTH_WIDTH];
          result_a_lane = result_a[li*WIDTH +: WIDTH];
          result_b_lane = result_b[li*WIDTH +: WIDTH];

          if (write_bank_sel) begin
            bank_wr_en_1_b[wr_bank_a_lane] = 1'b1;
            bank_wr_addr_1_b[wr_bank_a_lane] = wr_index_a_lane;
            bank_wr_data_1_b[wr_bank_a_lane] = result_a_lane;
            bank_wr_en_2_b[wr_bank_b_lane] = 1'b1;
            bank_wr_addr_2_b[wr_bank_b_lane] = wr_index_b_lane;
            bank_wr_data_2_b[wr_bank_b_lane] = result_b_lane;
          end else begin
            bank_wr_en_1_a[wr_bank_a_lane] = 1'b1;
            bank_wr_addr_1_a[wr_bank_a_lane] = wr_index_a_lane;
            bank_wr_data_1_a[wr_bank_a_lane] = result_a_lane;
            bank_wr_en_2_a[wr_bank_b_lane] = 1'b1;
            bank_wr_addr_2_a[wr_bank_b_lane] = wr_index_b_lane;
            bank_wr_data_2_a[wr_bank_b_lane] = result_b_lane;
          end
        end
      end
    end
  end

endmodule
