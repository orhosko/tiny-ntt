`timescale 1ns / 1ps

//==============================================================================
// NTT Pointwise Multiplication - Synthesis Wrapper
//==============================================================================
// Wrapper for Yosys synthesis that uses only packed arrays
// Directly instantiates 256 modular multipliers without using unpacked arrays
//==============================================================================

module ntt_pointwise_mult_synth #(
    parameter int N = 256,                 // Polynomial degree
    parameter int WIDTH = 32,              // Coefficient bit width
    parameter int Q = 3329,                // Modulus
    parameter int REDUCTION_TYPE = 0       // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
) (
    // Flattened inputs (packed arrays - Yosys compatible)
    input  logic [N*WIDTH-1:0] poly_a_flat,  // N coefficients concatenated
    input  logic [N*WIDTH-1:0] poly_b_flat,  // N coefficients concatenated
    output logic [N*WIDTH-1:0] poly_c_flat   // N coefficients concatenated
);

    // Generate N modular multipliers in parallel
    genvar i;
    generate
        for (i = 0; i < N; i++) begin : gen_mult
            // Extract coefficients from flattened arrays
            wire [WIDTH-1:0] a_coeff = poly_a_flat[i*WIDTH +: WIDTH];
            wire [WIDTH-1:0] b_coeff = poly_b_flat[i*WIDTH +: WIDTH];
            wire [WIDTH-1:0] c_coeff;
            
            // Instantiate modular multiplier
            mod_mult #(
                .WIDTH(WIDTH),
                .Q(Q),
                .REDUCTION_TYPE(REDUCTION_TYPE)
            ) mult_inst (
                .a(a_coeff),
                .b(b_coeff),
                .result(c_coeff)
            );
            
            // Pack result back into flattened array
            assign poly_c_flat[i*WIDTH +: WIDTH] = c_coeff;
        end
    endgenerate

endmodule
