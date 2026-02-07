`timescale 1ns / 1ps

//==============================================================================
// Modular Multiplier Module (Configurable)
//==============================================================================
// Computes (a * b) mod q with selectable reduction algorithm
//
// Supported reduction methods (REDUCTION_TYPE):
//   0: Simple modulo operation (for simulation/verification)
//   1: Barrett reduction (shift-multiply-subtract)
//   2: Montgomery reduction (for Montgomery domain operations)
//==============================================================================

module mod_mult #(
    parameter int WIDTH = 32,              // Coefficient bit width
    parameter int Q = 3329,                // Modulus (Kyber/Dilithium prime)
    parameter int REDUCTION_TYPE = 0,      // 0=SIMPLE, 1=BARRETT, 2=MONTGOMERY
    
    // Barrett reduction constants (q = 3329)
    parameter int K_BARRETT = 12,          // Bit width
    parameter int MU = 5039,               // floor(2^24 / 3329)
    
    // Montgomery reduction constants (q = 3329)
    parameter int K_MONTGOMERY = 13,       // R = 2^13 = 8192
    parameter int Q_PRIME = 7039,          // -q^-1 mod R
    parameter int R_MOD_Q = 1534           // R mod q (for conversion)
) (
    input  logic [WIDTH-1:0] a,            // First operand
    input  logic [WIDTH-1:0] b,            // Second operand
    output logic [WIDTH-1:0] result        // (a * b) mod q
);

    // Intermediate 64-bit multiplication result
    logic [2*WIDTH-1:0] mult_result;
    
    // Perform multiplication
    assign mult_result = a * b;
    
    // Select reduction method based on parameter
    generate
        if (REDUCTION_TYPE == 0) begin : gen_simple
            // Simple modulo operation (for simulation/verification)
            // Cast to proper widths to avoid Verilator warnings
            logic [2*WIDTH-1:0] q_extended;
            logic [2*WIDTH-1:0] mod_temp;
            assign q_extended = {{WIDTH{1'b0}}, Q};
            assign mod_temp = mult_result % q_extended;
            assign result = mod_temp[WIDTH-1:0];
            
        end else if (REDUCTION_TYPE == 1) begin : gen_barrett
            // Barrett reduction
            logic [WIDTH-1:0] barrett_out;
            
            barrett_reduction #(
                .Q(Q),
                .K(K_BARRETT),
                .MU(MU),
                .PRODUCT_WIDTH(2*WIDTH)
            ) barrett_inst (
                .product(mult_result),
                .result(barrett_out)
            );
            
            assign result = barrett_out;
            
        end else if (REDUCTION_TYPE == 2) begin : gen_montgomery
            // Montgomery reduction
            // Note: This assumes inputs are already in Montgomery domain
            logic [WIDTH-1:0] mont_out;
            
            montgomery_reduction #(
                .Q(Q),
                .K(K_MONTGOMERY),
                .Q_PRIME(Q_PRIME),
                .PRODUCT_WIDTH(2*WIDTH)
            ) montgomery_inst (
                .product(mult_result),
                .result(mont_out)
            );
            
            assign result = mont_out;
            
        end else begin : gen_error
            // Invalid reduction type
            initial begin
                $error("Invalid REDUCTION_TYPE: %0d. Must be 0 (SIMPLE), 1 (BARRETT), or 2 (MONTGOMERY)", 
                       REDUCTION_TYPE);
            end
            assign result = '0;
        end
    endgenerate

endmodule
