`timescale 1ns / 1ps

module mod_mult #(
    parameter WIDTH          = 32,
    parameter Q              = 8380417,
    parameter REDUCTION_TYPE = 0,
    parameter PIPELINE_STAGES = 0,
    parameter K_BARRETT      = 23,
    parameter MU             = 8396807,
    parameter K_MONTGOMERY   = 23,
    parameter Q_PRIME        = 8380415,
    parameter R_MOD_Q        = 8191
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  a,
    input  wire [WIDTH-1:0]  b,
    output wire [WIDTH-1:0]  result
);

  localparam MOD_WIDTH = (Q > 0) ? $clog2(Q) : WIDTH;
  localparam Q2_WIDTH = (2 * MOD_WIDTH) + K_BARRETT;

  wire [2*MOD_WIDTH-1:0] mult_result;
  wire [WIDTH-1:0]       result_comb;

  wire [MOD_WIDTH-1:0] a_trim;
  wire [MOD_WIDTH-1:0] b_trim;
  assign a_trim = a[MOD_WIDTH-1:0];
  assign b_trim = b[MOD_WIDTH-1:0];

  // Barrett reduction
  wire [WIDTH-1:0] barrett_out;

  barrett_reduction #(
      .Q            (Q),
      .K            (K_BARRETT),
      .MU           (MU),
      .PRODUCT_WIDTH(2 * MOD_WIDTH)
  ) barrett_inst (
      .product(mult_result),
      .result (barrett_out)
  );

  assign result_comb = barrett_out;

  function automatic [31:0] barrett_q2_estimate;
    input [2*MOD_WIDTH-1:0] product_value;
    reg [2*MOD_WIDTH-1:0] q1_value;
    reg [Q2_WIDTH-1:0] q2_temp_value;
    reg [Q2_WIDTH-1:0] q2_shifted_value;
    begin
      q1_value = product_value >> (K_BARRETT - 1);
      q2_temp_value = q1_value * MU;
      q2_shifted_value = q2_temp_value >> (K_BARRETT + 1);
      barrett_q2_estimate = q2_shifted_value[31:0];
    end
  endfunction

  function automatic [WIDTH-1:0] barrett_finalize;
    input [2*MOD_WIDTH-1:0] product_value;
    input [31:0] q2_value;
    reg [2*MOD_WIDTH+31:0] r_temp_value;
    reg [31:0] r_value;
    begin
      r_temp_value = {{32{1'b0}}, product_value} - (q2_value * Q);
      r_value = r_temp_value[31:0];
      if (r_value >= Q)
        barrett_finalize = r_value - Q;
      else
        barrett_finalize = r_value;
    end
  endfunction

  generate
    if (WIDTH > MOD_WIDTH) begin : gen_unused_inputs
      (* keep *) wire unused_a;
      (* keep *) wire unused_b;
      assign unused_a = ^a[WIDTH-1:MOD_WIDTH];
      assign unused_b = ^b[WIDTH-1:MOD_WIDTH];
    end
  endgenerate

  generate
    if (PIPELINE_STAGES == 0) begin : gen_no_pipe
      assign mult_result = a_trim * b_trim;
      assign result = rst_n ? result_comb : {WIDTH{1'b0}};

    end else if (PIPELINE_STAGES <= 3) begin : gen_pipe_3_dsp_optimized
      reg [MOD_WIDTH-1:0] a_reg, b_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage1_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage2_reg;
      reg [WIDTH-1:0]       result_reg;

      // Leave the arithmetic pipeline unreset so DSP/register packing is not
      // blocked by asynchronous reset logic. The module output is still held
      // at zero while rst_n is low.
      always @(posedge clk) begin
        a_reg           <= a_trim;
        b_reg           <= b_trim;
        mult_stage1_reg <= a_reg * b_reg;
        mult_stage2_reg <= mult_stage1_reg;
        result_reg      <= result_comb;
      end

      assign mult_result   = mult_stage2_reg;
      assign result        = rst_n ? result_reg : {WIDTH{1'b0}};
    end else begin : gen_pipe_4_barrett_split
      reg [MOD_WIDTH-1:0] a_reg, b_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage1_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage2_reg;
      reg [2*MOD_WIDTH-1:0] product_reg;
      reg [31:0]            q2_reg;
      reg [WIDTH-1:0]       result_reg;

      wire [31:0]           q2_comb;
      wire [WIDTH-1:0]      result_pipe_comb;

      assign q2_comb = barrett_q2_estimate(mult_stage2_reg);
      assign result_pipe_comb = barrett_finalize(product_reg, q2_reg);

      // Split Barrett reduction into two cycles:
      // 1) quotient estimate q2 = ((product >> (k-1)) * mu) >> (k+1)
      // 2) remainder correction product - q2*q with final conditional subtract
      always @(posedge clk) begin
        a_reg           <= a_trim;
        b_reg           <= b_trim;
        mult_stage1_reg <= a_reg * b_reg;
        mult_stage2_reg <= mult_stage1_reg;
        product_reg     <= mult_stage2_reg;
        q2_reg          <= q2_comb;
        result_reg      <= result_pipe_comb;
      end

      assign mult_result = product_reg;
      assign result = rst_n ? result_reg : {WIDTH{1'b0}};
    end
  endgenerate

endmodule
