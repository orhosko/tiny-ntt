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

  localparam HALF_DEPTH = DEPTH / 2;
  localparam HALF_ADDR_WIDTH = (HALF_DEPTH <= 1) ? 1 : $clog2(HALF_DEPTH);

  wire rd_a_hi = rd_addr_a[ADDR_WIDTH-1];
  wire rd_b_hi = rd_addr_b[ADDR_WIDTH-1];
  wire wr_1_hi = wr_addr_1[ADDR_WIDTH-1];
  wire wr_2_hi = wr_addr_2[ADDR_WIDTH-1];

  wire [HALF_ADDR_WIDTH-1:0] rd_addr_a_half = rd_addr_a[HALF_ADDR_WIDTH-1:0];
  wire [HALF_ADDR_WIDTH-1:0] rd_addr_b_half = rd_addr_b[HALF_ADDR_WIDTH-1:0];
  wire [HALF_ADDR_WIDTH-1:0] wr_addr_1_half = wr_addr_1[HALF_ADDR_WIDTH-1:0];
  wire [HALF_ADDR_WIDTH-1:0] wr_addr_2_half = wr_addr_2[HALF_ADDR_WIDTH-1:0];

  integer i;
  (* ram_style = "block" *) reg [WIDTH-1:0] mem_lo [0:HALF_DEPTH-1];
  (* ram_style = "block" *) reg [WIDTH-1:0] mem_hi [0:HALF_DEPTH-1];

  initial begin
    for (i = 0; i < HALF_DEPTH; i = i + 1) begin
      mem_lo[i] = 0;
      mem_hi[i] = 0;
    end
  end

  // Read port A shares the logical bank across the low/high physical halves.
  always @(posedge clk) begin
    if (rd_a_hi)
      rd_data_a <= mem_hi[rd_addr_a_half];
    else
      rd_data_a <= mem_lo[rd_addr_a_half];
  end

  // Read port B is used for external reads. During compute the write ports take
  // precedence and the external read value is don't-care.
  always @(posedge clk) begin
    if (wr_en_2 && wr_2_hi) begin
      mem_hi[wr_addr_2_half] <= wr_data_2;
      if (rd_b_hi)
        rd_data_b <= wr_data_2;
    end else if (wr_en_1 && wr_1_hi) begin
      mem_hi[wr_addr_1_half] <= wr_data_1;
      if (rd_b_hi)
        rd_data_b <= wr_data_1;
    end else if (rd_b_hi) begin
      rd_data_b <= mem_hi[rd_addr_b_half];
    end

    if (wr_en_2 && !wr_2_hi) begin
      mem_lo[wr_addr_2_half] <= wr_data_2;
      if (!rd_b_hi)
        rd_data_b <= wr_data_2;
    end else if (wr_en_1 && !wr_1_hi) begin
      mem_lo[wr_addr_1_half] <= wr_data_1;
      if (!rd_b_hi)
        rd_data_b <= wr_data_1;
    end else if (!rd_b_hi) begin
      rd_data_b <= mem_lo[rd_addr_b_half];
    end
  end

endmodule
