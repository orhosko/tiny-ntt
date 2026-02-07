`timescale 1ns / 1ps

//==============================================================================
// Modular Multiplier Module
//==============================================================================
// Computes (a * b) mod q where q is a configurable modulus
// Uses simple modulo operation for initial implementation
// Can be upgraded to Barrett/Montgomery reduction for better performance
//==============================================================================

module mod_mult #(
    parameter int WIDTH = 32,      // Coefficient bit width
    parameter int Q = 3329         // Modulus (Kyber/Dilithium prime)
) (
    input  logic [WIDTH-1:0] a,    // First operand
    input  logic [WIDTH-1:0] b,    // Second operand
    output logic [WIDTH-1:0] result // (a * b) mod q
);

    // Intermediate 64-bit multiplication result
    logic [2*WIDTH-1:0] mult_result;
    
    // Perform multiplication
    assign mult_result = a * b;
    
    // Perform modular reduction
    assign result = mult_result % Q;

endmodule
