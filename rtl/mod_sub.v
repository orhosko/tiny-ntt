`timescale 1ns / 1ps

module mod_sub #(
    parameter WIDTH = 32,
    parameter Q     = 8380417
) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] result
);

  wire               is_negative;
  wire [WIDTH-1:0]   diff;

  assign is_negative = (a < b);
  assign diff        = a - b;
  assign result      = is_negative ? (diff + Q) : diff;

endmodule
