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
    parameter int REDUCTION_TYPE = 0,        // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
    parameter int MULT_PIPELINE  = 3
) (
    input logic clk,
    input logic rst_n,

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
  logic [WIDTH-1:0] a_aligned;

  generate
    if (MULT_PIPELINE == 0) begin : gen_align_comb
      assign a_aligned = a;
    end else begin : gen_align_pipe
      logic [WIDTH-1:0] a_pipe[0:MULT_PIPELINE];
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int i = 0; i <= MULT_PIPELINE; i++) begin
            a_pipe[i] <= '0;
          end
        end else begin
          a_pipe[0] <= a;
          for (int i = 1; i <= MULT_PIPELINE; i++) begin
            a_pipe[i] <= a_pipe[i - 1];
          end
        end
      end
      assign a_aligned = a_pipe[MULT_PIPELINE];
    end
  endgenerate

  // Modular multiplication: twiddle * b
  mod_mult #(
      .WIDTH(WIDTH),
      .Q(Q),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) mult_inst (
      .clk(clk),
      .rst_n(rst_n),
      .a(twiddle),
      .b(b),
      .result(twiddle_mult_b)
  );

  // Modular addition: a + (twiddle * b)
  mod_add #(
      .WIDTH(WIDTH),
      .Q(Q)
  ) add_inst (
      .a(a_aligned),
      .b(twiddle_mult_b),
      .result(a_out)
  );

  // Modular subtraction: a - (twiddle * b)
  mod_sub #(
      .WIDTH(WIDTH),
      .Q(Q)
  ) sub_inst (
      .a(a_aligned),
      .b(twiddle_mult_b),
      .result(b_out)
  );

endmodule
