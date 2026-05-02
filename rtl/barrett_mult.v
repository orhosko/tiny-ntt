`timescale 1ns / 1ps

module barrett_mult #(
    parameter WIDTH           = 32,
    parameter Q               = 8380417,
    parameter PIPELINE_STAGES = 0,
    parameter K               = 23,
    parameter MU              = 8396807
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] result
);

  localparam MOD_WIDTH = (Q > 0) ? $clog2(Q) : WIDTH;
  localparam Q2_WIDTH = (2 * MOD_WIDTH) + K;

  wire [MOD_WIDTH-1:0] a_trim = a[MOD_WIDTH-1:0];
  wire [MOD_WIDTH-1:0] b_trim = b[MOD_WIDTH-1:0];
  wire [2*MOD_WIDTH-1:0] mult_result;
  wire [WIDTH-1:0] result_comb;

  barrett_reduction #(
      .Q            (Q),
      .K            (K),
      .MU           (MU),
      .PRODUCT_WIDTH(2 * MOD_WIDTH)
  ) barrett_inst (
      .product(mult_result),
      .result (result_comb)
  );

  function automatic [31:0] q2_estimate;
    input [2*MOD_WIDTH-1:0] product_value;
    reg [2*MOD_WIDTH-1:0] q1_value;
    reg [Q2_WIDTH-1:0] q2_temp_value;
    reg [Q2_WIDTH-1:0] q2_shifted_value;
    begin
      q1_value = product_value >> (K - 1);
      q2_temp_value = q1_value * MU;
      q2_shifted_value = q2_temp_value >> (K + 1);
      q2_estimate = q2_shifted_value[31:0];
    end
  endfunction

  function automatic [WIDTH-1:0] finalize;
    input [2*MOD_WIDTH-1:0] product_value;
    input [31:0] q2_value;
    reg [2*MOD_WIDTH+31:0] r_temp_value;
    reg [31:0] r_value;
    begin
      r_temp_value = {{32{1'b0}}, product_value} - (q2_value * Q);
      r_value = r_temp_value[31:0];
      if (r_value >= Q)
        finalize = r_value - Q;
      else
        finalize = r_value;
    end
  endfunction

  generate
    if (PIPELINE_STAGES == 0) begin : gen_no_pipe
      assign mult_result = a_trim * b_trim;
      assign result = rst_n ? result_comb : {WIDTH{1'b0}};
    end else if (PIPELINE_STAGES <= 3) begin : gen_pipe_3
      reg [MOD_WIDTH-1:0] a_reg, b_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage1_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage2_reg;
      reg [WIDTH-1:0] result_reg;

      always @(posedge clk) begin
        a_reg           <= a_trim;
        b_reg           <= b_trim;
        mult_stage1_reg <= a_reg * b_reg;
        mult_stage2_reg <= mult_stage1_reg;
        result_reg      <= result_comb;
      end

      assign mult_result = mult_stage2_reg;
      assign result = rst_n ? result_reg : {WIDTH{1'b0}};
    end else begin : gen_pipe_4_split
      reg [MOD_WIDTH-1:0] a_reg, b_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage1_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage2_reg;
      reg [2*MOD_WIDTH-1:0] product_reg;
      reg [31:0] q2_reg;
      reg [WIDTH-1:0] result_reg;

      wire [31:0] q2_comb = q2_estimate(mult_stage2_reg);
      wire [WIDTH-1:0] result_pipe_comb = finalize(product_reg, q2_reg);

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
