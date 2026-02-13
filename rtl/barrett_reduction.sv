`timescale 1ns / 1ps

//==============================================================================
// Barrett Reduction Module
//==============================================================================
// Implements Barrett reduction algorithm for efficient modular reduction
// without division operations.
//
// Algorithm:
//   Given product = a * b, compute product mod q
//   1. q1 = product >> (k-1)
//   2. q2 = (q1 * μ) >> (k+1)
//   3. r = product - q2 * q
//   4. if (r >= q) r = r - q  (correction step)
//
// Precomputed constants (for q = 8380417):
//   k = 23 (bit width of q)
//   μ = floor(2^(2k) / q) = floor(2^46 / 8380417) = 8396807
//==============================================================================

module barrett_reduction #(
    parameter int Q = 8380417,           // Modulus
    parameter int K = 23,                // Bit width (2^(k-1) < q < 2^k)
    parameter int MU = 8396807,          // floor(2^(2k) / q)
    parameter int PRODUCT_WIDTH = 64  // Input product width
) (
    input  logic [PRODUCT_WIDTH-1:0] product,  // Input: a * b
    output logic [31:0] result                  // Output: (a * b) mod q
);

    // Intermediate values
    logic [PRODUCT_WIDTH-1:0] q1;
    logic [PRODUCT_WIDTH-1:0] q2_temp;
    logic [PRODUCT_WIDTH-1:0] r_temp;
    logic [31:0] r;
    
    // Step 1: q1 = product >> (k-1)
    assign q1 = product >> (K - 1);
    
    // Step 2: q2 = (q1 * μ) >> (k+1)
    assign q2_temp = q1 * MU;
    logic [31:0] q2;
    assign q2 = q2_temp[K+1 +: 32];  // Extract 32 bits starting at bit K+1
    
    // Step 3: r = product - q2 * q
    assign r_temp = product - (q2 * Q);
    assign r = r_temp[31:0];  // Truncate to 32 bits
    
    // Step 4: Correction (if r >= q, subtract q)
    assign result = (r >= Q) ? (r - Q) : r;

endmodule
