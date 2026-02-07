`timescale 1ns / 1ps

//==============================================================================
// Modular Adder
//==============================================================================
// Computes (a + b) mod q for NTT arithmetic
// Combinational module for modular addition
//==============================================================================

module mod_add #(
    parameter int WIDTH = 32,   // Coefficient bit width
    parameter int Q     = 3329  // Modulus (Kyber/Dilithium prime)
) (
    input  logic [WIDTH-1:0] a,      // First operand
    input  logic [WIDTH-1:0] b,      // Second operand
    output logic [WIDTH-1:0] result  // (a + b) mod Q
);

  // Intermediate sum (may overflow WIDTH bits)
  logic [WIDTH:0] sum;  // WIDTH+1 bits to handle overflow

  // Compute a + b
  assign sum = {1'b0, a} + {1'b0, b};

  // Reduce modulo Q if needed
  // If sum >= Q, subtract Q
  assign result = (sum >= Q) ? (sum - Q) : sum[WIDTH-1:0];

endmodule
