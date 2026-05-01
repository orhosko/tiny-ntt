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
  (* use_dsp = "yes" *) logic [2*WIDTH-1:0] mult_result;
  
  logic [WIDTH-1:0] result_comb;
  logic [WIDTH-1:0] result_reg;
  logic [WIDTH-1:0] a_reg, b_reg;
  
  // Pipeline registers for the multiplier
  logic [2*WIDTH-1:0] mult_stage1_reg;
  logic [2*WIDTH-1:0] mult_stage2_reg;

  generate
    if (PIPELINE_STAGES == 0) begin : gen_no_pipe
      assign mult_result = a * b;
      assign result = result_comb;
      
    end else if (PIPELINE_STAGES == 3) begin : gen_pipe_3_dsp_optimized
      // NO RESET on the datapath allows the tool to map these directly 
      // into the DSP block's internal A, B, M, and P registers.
      always_ff @(posedge clk) begin
        // Stage 1: Input registers (Maps to DSP A/B registers)
        a_reg <= a;
        b_reg <= b;
        
        // Stage 2: Intermediate product (Maps to DSP M registers)
        mult_stage1_reg <= a_reg * b_reg;
        
        // Stage 3: Final product / Cascaded output (Maps to DSP P registers)
        mult_stage2_reg <= mult_stage1_reg;
        
        // Output stage for the Barrett Reduction
        result_reg <= result_comb;
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
          .PRODUCT_WIDTH(2 * WIDTH)
      ) barrett_inst (
          .product(mult_result),
          .result (barrett_out)
      );

      assign result_comb = barrett_out;
  endgenerate

endmodule