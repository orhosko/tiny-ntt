`timescale 1ns / 1ps

module ntt_pointwise_mult #(
    parameter N              = 4096,
    parameter WIDTH          = 32,
    parameter Q              = 8380417,
    parameter REDUCTION_TYPE = 0,
    parameter MULT_PIPELINE  = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire [N*WIDTH-1:0] poly_a_flat,
    input  wire [N*WIDTH-1:0] poly_b_flat,
    output wire [N*WIDTH-1:0] poly_c_flat
);

  genvar i;
  generate
    for (i = 0; i < N; i = i + 1) begin : gen_mult
      wire [WIDTH-1:0] a_coeff;
      wire [WIDTH-1:0] b_coeff;
      wire [WIDTH-1:0] c_coeff;

      assign a_coeff = poly_a_flat[i*WIDTH +: WIDTH];
      assign b_coeff = poly_b_flat[i*WIDTH +: WIDTH];

      mod_mult #(
          .WIDTH          (WIDTH),
          .Q              (Q),
          .REDUCTION_TYPE (REDUCTION_TYPE),
          .PIPELINE_STAGES(MULT_PIPELINE)
      ) mult_inst (
          .clk   (clk),
          .rst_n (rst_n),
          .a     (a_coeff),
          .b     (b_coeff),
          .result(c_coeff)
      );

      assign poly_c_flat[i*WIDTH +: WIDTH] = c_coeff;
    end
  endgenerate

endmodule
