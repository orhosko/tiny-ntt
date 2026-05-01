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
    parameter int REDUCTION_TYPE = 0,     // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
    parameter int MULT_PIPELINE  = 3
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [N*WIDTH-1:0] poly_a_flat,
    input  logic [N*WIDTH-1:0] poly_b_flat,
    output logic [N*WIDTH-1:0] poly_c_flat
);

  // Generate N modular multipliers in parallel
  genvar i;
  generate
    for (i = 0; i < N; i++) begin : gen_mult
      wire [WIDTH-1:0] a_coeff = poly_a_flat[i*WIDTH +: WIDTH];
      wire [WIDTH-1:0] b_coeff = poly_b_flat[i*WIDTH +: WIDTH];
      wire [WIDTH-1:0] c_coeff;

      mod_mult #(
          .WIDTH(WIDTH),
          .Q(Q),
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .PIPELINE_STAGES(MULT_PIPELINE)
      ) mult_inst (
          .clk(clk),
          .rst_n(rst_n),
          .a(a_coeff),
          .b(b_coeff),
          .result(c_coeff)
      );

      assign poly_c_flat[i*WIDTH +: WIDTH] = c_coeff;
    end
  endgenerate

endmodule
