`timescale 1ns / 1ps

module mod_add #(
    parameter WIDTH = 32,
    parameter [WIDTH-1:0] Q = 8380417
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] result
);

  wire [WIDTH:0] sum;

  assign sum    = {1'b0, a} + {1'b0, b};
  assign result = (sum >= {1'b0, Q}) ? (sum - {1'b0, Q}) : sum[WIDTH-1:0];

endmodule
