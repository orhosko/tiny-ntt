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

    end else begin : gen_pipe_3_dsp_optimized
      reg [MOD_WIDTH-1:0] a_reg, b_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage1_reg;
      reg [2*MOD_WIDTH-1:0] mult_stage2_reg;
      reg [WIDTH-1:0]       result_reg;

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          a_reg          <= 0;
          b_reg          <= 0;
          mult_stage1_reg <= 0;
          mult_stage2_reg <= 0;
          result_reg     <= 0;
        end else begin
          a_reg           <= a_trim;
          b_reg           <= b_trim;
          mult_stage1_reg <= a_reg * b_reg;
          mult_stage2_reg <= mult_stage1_reg;
          result_reg      <= result_comb;
        end
      end

      assign mult_result   = mult_stage2_reg;
      assign result        = result_reg;
    end
  endgenerate

endmodule
