`timescale 1ns / 1ps

module ntt_coeff_bank_single #(
    parameter WIDTH      = 32,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  wire                  clk,

    input  wire [ADDR_WIDTH-1:0] rd_addr_a,
    output reg  [WIDTH-1:0]      rd_data_a,

    input  wire [ADDR_WIDTH-1:0] rd_addr_b,
    output reg  [WIDTH-1:0]      rd_data_b,

    input  wire                  wr_en_1,
    input  wire [ADDR_WIDTH-1:0] wr_addr_1,
    input  wire [WIDTH-1:0]      wr_data_1,

    input  wire                  wr_en_2,
    input  wire [ADDR_WIDTH-1:0] wr_addr_2,
    input  wire [WIDTH-1:0]      wr_data_2
);

  integer i;
  reg [WIDTH-1:0] mem [0:DEPTH-1];

  initial begin
    for (i = 0; i < DEPTH; i = i + 1)
      mem[i] = 0;
  end

  always @(posedge clk)
    rd_data_a <= mem[rd_addr_a];

  always @(posedge clk)
    rd_data_b <= mem[rd_addr_b];

  always @(posedge clk) begin
    if (wr_en_1)
      mem[wr_addr_1] <= wr_data_1;
    if (wr_en_2)
      mem[wr_addr_2] <= wr_data_2;
  end

endmodule
