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
    parameter int REDUCTION_TYPE = 0,     // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
    parameter int MULT_PIPELINE  = 3
) (
    input logic clk,
    input logic rst_n,

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
  logic [WIDTH-1:0] sum_aligned;

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

  generate
    if (MULT_PIPELINE == 0) begin : gen_sum_align_comb
      assign sum_aligned = sum;
    end else begin : gen_sum_align_pipe
      logic [WIDTH-1:0] sum_pipe[0:MULT_PIPELINE];
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int i = 0; i <= MULT_PIPELINE; i++) begin
            sum_pipe[i] <= '0;
          end
        end else begin
          sum_pipe[0] <= sum;
          for (int i = 1; i <= MULT_PIPELINE; i++) begin
            sum_pipe[i] <= sum_pipe[i - 1];
          end
        end
      end
      assign sum_aligned = sum_pipe[MULT_PIPELINE];
    end
  endgenerate

  // Step 3: Multiply difference by twiddle: (a - b) · ω^(-k)
  mod_mult #(
      .WIDTH(WIDTH),
      .Q(Q),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) mult_inst (
      .clk(clk),
      .rst_n(rst_n),
      .a(diff),
      .b(twiddle),
      .result(b_out)
  );

  // Output assignments
  assign a_out = sum_aligned;  // a' = a + b

endmodule
