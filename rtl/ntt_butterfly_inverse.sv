`timescale 1ns / 1ps

//==============================================================================
// Inverse NTT Butterfly Unit (Gentleman-Sande)
//==============================================================================
// Implements the radix-2 Gentleman-Sande butterfly operation for Inverse NTT
//
// Butterfly operation for INVERSE NTT:
//   Input: (a, b), twiddle factor ψ^(-k)
//   Output: (a', b')
//     a' = (a + b) mod q
//     b' = (a - b) · ψ^(-k) mod q
//
// NOTE: This is DIFFERENT from forward NTT butterfly!
// Forward multiplies twiddle with b BEFORE add/sub
// Inverse adds/subs FIRST, THEN multiplies with twiddle
//==============================================================================

module ntt_butterfly_inverse #(
    parameter int WIDTH          = 32,    // Coefficient bit width
    parameter int Q              = 8380417,  // Modulus (Dilithium prime)
    parameter int REDUCTION_TYPE = 0      // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
) (
    // Inputs
    input logic [WIDTH-1:0] a,       // First input coefficient
    input logic [WIDTH-1:0] b,       // Second input coefficient
    input logic [WIDTH-1:0] twiddle, // Inverse twiddle factor ψ^(-k)

    // Outputs
    output logic [WIDTH-1:0] a_out,  // First output: (a + b) mod q
    output logic [WIDTH-1:0] b_out   // Second output: (a - b) · ω^(-k) mod q
);

  // Intermediate results
  logic [WIDTH-1:0] sum;  // a + b
  logic [WIDTH-1:0] diff;  // a - b

  // Step 1: Modular addition: a + b
  mod_add #(
      .WIDTH(WIDTH),
      .Q(Q)
  ) add_inst (
      .a(a),
      .b(b),
      .result(sum)
  );

  // Step 2: Modular subtraction: a - b
  mod_sub #(
      .WIDTH(WIDTH),
      .Q(Q)
  ) sub_inst (
      .a(a),
      .b(b),
      .result(diff)
  );

  // Step 3: Multiply difference by twiddle: (a - b) · ω^(-k)
  mod_mult #(
      .WIDTH(WIDTH),
      .Q(Q),
      .REDUCTION_TYPE(REDUCTION_TYPE)
  ) mult_inst (
      .a(diff),
      .b(twiddle),
      .result(b_out)
  );

  // Output assignments
  assign a_out = sum;  // a' = a + b

endmodule
