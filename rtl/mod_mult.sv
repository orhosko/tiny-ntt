`timescale 1ns / 1ps

//==============================================================================
// Modular Multiplier Module
//==============================================================================

module mod_mult #(
    parameter int WIDTH = 32,         // Coefficient bit width
    parameter int Q = 8380417,        // Modulus (Kyber/Dilithium prime)
    parameter int REDUCTION_TYPE = 0, // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
    parameter int PIPELINE_STAGES = 0,

    // Barrett reduction constants (q = 8380417)
    parameter int K_BARRETT = 23,     // Bit width
    parameter int MU = 8396807,       // floor(2^46 / 8380417)

    // Montgomery reduction constants (q = 8380417)
    parameter int K_MONTGOMERY = 23,  // R = 2^23 = 8388608
    parameter int Q_PRIME = 8380415,  // -q^-1 mod R
    parameter int R_MOD_Q = 8191      // R mod q (for conversion)
) (
    input  logic clk,
    // Note: rst_n might only be needed for control logic/valid signals now
    input  logic rst_n, 
    input  logic [WIDTH-1:0] a,      
    input  logic [WIDTH-1:0] b,      
    output logic [WIDTH-1:0] result  
);

  // Force DSP usage
  localparam int MOD_WIDTH = (Q > 0) ? $clog2(Q) : WIDTH;

  (* use_dsp = "yes" *) logic [2*MOD_WIDTH-1:0] mult_result;

  logic [WIDTH-1:0] result_comb;
  logic [WIDTH-1:0] result_reg;
  logic [MOD_WIDTH-1:0] a_reg, b_reg;
  logic [MOD_WIDTH-1:0] a_trim, b_trim;

  // Pipeline registers for the multiplier
  logic [2*MOD_WIDTH-1:0] mult_stage1_reg;
  logic [2*MOD_WIDTH-1:0] mult_stage2_reg;

  assign a_trim = a[MOD_WIDTH-1:0];
  assign b_trim = b[MOD_WIDTH-1:0];

  generate
    if (WIDTH > MOD_WIDTH) begin : gen_unused_inputs
      (* keep *) logic unused_a;
      (* keep *) logic unused_b;
      assign unused_a = ^a[WIDTH-1:MOD_WIDTH];
      assign unused_b = ^b[WIDTH-1:MOD_WIDTH];
    end
  endgenerate

  generate
    if (PIPELINE_STAGES == 0) begin : gen_no_pipe
      assign mult_result = a_trim * b_trim;
      assign result = rst_n ? result_comb : '0;

    end else if (PIPELINE_STAGES == 3) begin : gen_pipe_3_dsp_optimized
      always_ff @(posedge clk) begin
        if (!rst_n) begin
          a_reg <= '0;
          b_reg <= '0;
          mult_stage1_reg <= '0;
          mult_stage2_reg <= '0;
          result_reg <= '0;
        end else begin
          // Stage 1: Input registers (Maps to DSP A/B registers)
          a_reg <= a_trim;
          b_reg <= b_trim;

          // Stage 2: Intermediate product (Maps to DSP M registers)
          mult_stage1_reg <= a_reg * b_reg;

          // Stage 3: Final product / Cascaded output (Maps to DSP P registers)
          mult_stage2_reg <= mult_stage1_reg;

          // Output stage for the Barrett Reduction
          result_reg <= result_comb;
        end
      end

      assign mult_result = mult_stage2_reg;
      assign result = result_reg;
    end
  endgenerate

  generate
      // Barrett reduction
      logic [WIDTH-1:0] barrett_out;

      barrett_reduction #(
          .Q(Q),
          .K(K_BARRETT),
          .MU(MU),
          .PRODUCT_WIDTH(2 * MOD_WIDTH)
      ) barrett_inst (
          .product(mult_result),
          .result (barrett_out)
      );

      assign result_comb = barrett_out;
  endgenerate

endmodule