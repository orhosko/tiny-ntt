`timescale 1ns / 1ps

module montgomery_reduction #(
    parameter WIDTH         = 32,
    parameter Q             = 8380417,
    parameter K             = 23,
    parameter Q_PRIME       = 8380415,
    parameter PRODUCT_WIDTH = 64
) (
    input  wire [PRODUCT_WIDTH-1:0] product,
    output wire [WIDTH-1:0]         result
);

  localparam R      = (1 << K);
  localparam R_MASK = R - 1;

  wire [PRODUCT_WIDTH-1:0] m_temp;
  wire [K-1:0]             m;
  wire [PRODUCT_WIDTH-1:0] t_temp;
  wire [WIDTH-1:0]         t;

  assign m_temp  = product * Q_PRIME;
  assign m       = m_temp[K-1:0];
  assign t_temp  = product + (m * Q);
  assign t       = t_temp[K +: WIDTH];
  assign result  = (t >= Q) ? (t - Q) : t;

endmodule
