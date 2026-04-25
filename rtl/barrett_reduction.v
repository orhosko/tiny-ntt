`timescale 1ns / 1ps

module barrett_reduction #(
    parameter Q             = 8380417,
    parameter K             = 23,
    parameter MU            = 8396807,
    parameter PRODUCT_WIDTH = 64
) (
    input  wire [PRODUCT_WIDTH-1:0] product,
    output wire [31:0]              result
);

  localparam Q2_WIDTH = PRODUCT_WIDTH + K;

  wire [PRODUCT_WIDTH-1:0]   q1;
  wire [Q2_WIDTH-1:0]        q2_temp;
  wire [Q2_WIDTH-1:0]        q2_shifted;
  wire [31:0]                q2;
  wire [PRODUCT_WIDTH+31:0]  r_temp;
  wire [31:0]                r;

  assign q1        = product >> (K - 1);
  assign q2_temp   = q1 * MU;
  assign q2_shifted = q2_temp >> (K + 1);
  assign q2        = q2_shifted[31:0];
  assign r_temp    = {{32{1'b0}}, product} - (q2 * Q);
  assign r         = r_temp[31:0];
  assign result    = (r >= Q) ? (r - Q) : r;

endmodule
