`timescale 1ns / 1ps

//==============================================================================
// NTT Butterfly Unit (Cooley-Tukey)
//==============================================================================
// Implements the radix-2 Cooley-Tukey butterfly operation for NTT
//
// Butterfly operation:
//   Input: (a, b), twiddle factor ω
//   Output: (a', b')
//     a' = (a + ω·b) mod q
//     b' = (a - ω·b) mod q
//
// This is the core building block for NTT computation
//==============================================================================

module ntt_butterfly #(
    parameter int WIDTH          = 32,       // Coefficient bit width
    parameter int Q              = 8380417,  // Modulus (Kyber/Dilithium prime)
    parameter int REDUCTION_TYPE = 0         // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
) (
    // Inputs
    input logic [WIDTH-1:0] a,       // First input coefficient
    input logic [WIDTH-1:0] b,       // Second input coefficient
    input logic [WIDTH-1:0] twiddle, // Twiddle factor ω

    // Outputs
    output logic [WIDTH-1:0] a_out,  // First output: (a + ω·b) mod q
    output logic [WIDTH-1:0] b_out   // Second output: (a - ω·b) mod q
);

  // Intermediate result: ω·b
  logic [WIDTH-1:0] twiddle_mult_b;

  // Modular multiplication: twiddle * b
  mod_mult #(
      .WIDTH(WIDTH),
      .Q(Q),
      .REDUCTION_TYPE(REDUCTION_TYPE)
  ) mult_inst (
      .a(twiddle),
      .b(b),
      .result(twiddle_mult_b)
  );

  // Modular addition: a + (twiddle * b)
  mod_add #(
      .WIDTH(WIDTH),
      .Q(Q)
  ) add_inst (
      .a(a),
      .b(twiddle_mult_b),
      .result(a_out)
  );

  // Modular subtraction: a - (twiddle * b)
  mod_sub #(
      .WIDTH(WIDTH),
      .Q(Q)
  ) sub_inst (
      .a(a),
      .b(twiddle_mult_b),
      .result(b_out)
  );

endmodule
