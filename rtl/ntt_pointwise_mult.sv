`timescale 1ns / 1ps

//==============================================================================
// NTT Pointwise Multiplication Unit
//==============================================================================
// Performs parallel pointwise multiplication of two NTT-domain polynomials
// C[i] = (A[i] * B[i]) mod q for all i in [0, N-1]
//
// Supports configurable modular reduction methods via REDUCTION_TYPE parameter:
//   0: SIMPLE     - Direct modulo (baseline)
//   1: BARRETT    - Barrett reduction (optimized)
//   2: MONTGOMERY - Montgomery reduction (fastest for repeated ops)
//==============================================================================

module ntt_pointwise_mult #(
    parameter int N              = 256,   // Polynomial degree (number of coefficients)
    parameter int WIDTH          = 32,    // Coefficient bit width
    parameter int Q              = 8380417,  // Modulus (Dilithium prime)
    parameter int REDUCTION_TYPE = 1      // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
) (
    // Input polynomial A (NTT domain)
    input logic [WIDTH-1:0] poly_a[N-1:0],

    // Input polynomial B (NTT domain)
    input logic [WIDTH-1:0] poly_b[N-1:0],

    // Output polynomial C = A * B (NTT domain)
    output logic [WIDTH-1:0] poly_c[N-1:0]
);

  // Generate N modular multipliers in parallel
  genvar i;
  generate
    for (i = 0; i < N; i++) begin : gen_mult
      mod_mult #(
          .WIDTH(WIDTH),
          .Q(Q),
          .REDUCTION_TYPE(REDUCTION_TYPE)
      ) mult_inst (
          .a(poly_a[i]),
          .b(poly_b[i]),
          .result(poly_c[i])
      );
    end
  endgenerate

endmodule
