`timescale 1ns / 1ps

//==============================================================================
// Montgomery Reduction Module (REDC)
//==============================================================================
// Implements Montgomery reduction algorithm for efficient modular reduction.
//
// Algorithm (REDC - Reduce from Montgomery domain):
//   Given T (product in Montgomery domain), compute T / R mod q
//   1. m = (T * q') mod R
//   2. t = (T + m * q) >> k  (where R = 2^k)
//   3. if (t >= q) t = t - q  (correction step)
//
// Note: This assumes inputs are already in Montgomery domain.
// For standalone use: convert inputs with a_M = (a * R) mod q first.
//
// Precomputed constants (for q = 8380417):
//   k = 23 (R = 2^23 = 8388608, next power of 2 above q)
//   R = 8388608
//   q' = -q^-1 mod R = 8380415
//   R mod q = 8191 (used for domain conversion)
//==============================================================================

module montgomery_reduction #(
    parameter int Q = 8380417,           // Modulus
    parameter int K = 23,                // Bit width of R (R = 2^k)
    parameter int Q_PRIME = 8380415,     // -q^-1 mod R
    parameter int PRODUCT_WIDTH = 64  // Input product width
) (
    input  logic [PRODUCT_WIDTH-1:0] product,  // Input: T (in Montgomery domain)
    output logic [31:0] result                  // Output: T/R mod q (in Montgomery domain)
);

    // R = 2^K
    localparam int R = (1 << K);
    localparam int R_MASK = R - 1;  // Mask for mod R operation
    
    // Intermediate values
    logic [PRODUCT_WIDTH-1:0] m_temp;
    logic [K-1:0] m;              // m = (T * q') mod R
    logic [PRODUCT_WIDTH-1:0] t_temp;
    logic [31:0] t;
    
    // Step 1: m = (product * q') mod R
    // Since R is power of 2, mod R is just taking lower K bits
    assign m_temp = product * Q_PRIME;
    assign m = m_temp[K-1:0];  // mod R (take lower K bits)
    
    // Step 2: t = (product + m * q) >> k
    assign t_temp = product + (m * Q);
    assign t = t_temp[K +: 32];  // Extract 32 bits starting at bit K (divide by R = 2^k)
    
    // Step 3: Correction (if t >= q, subtract q)
    assign result = (t >= Q) ? (t - Q) : t;

endmodule
