`timescale 1ns / 1ps

//==============================================================================
// Modular Subtractor
//==============================================================================
// Computes (a - b) mod q for NTT arithmetic
// Handles negative results by adding Q
// Combinational module for modular subtraction
//==============================================================================

module mod_sub #(
    parameter int WIDTH = 32,   // Coefficient bit width
    parameter int Q     = 8380417  // Modulus (Dilithium prime)
) (
    input  logic [WIDTH-1:0] a,      // Minuend
    input  logic [WIDTH-1:0] b,      // Subtrahend
    output logic [WIDTH-1:0] result  // (a - b) mod Q
);

  // Check if a < b (would give negative result)
  logic is_negative;
  logic [WIDTH-1:0] diff;

  assign is_negative = (a < b);
  assign diff = a - b;

  // If negative, add Q to make result positive
  // (a - b) mod Q = (a - b + Q) mod Q when a < b
  assign result = is_negative ? (diff + Q) : diff;

endmodule
