`timescale 1ns / 1ps

module mod_mult #(
    parameter WIDTH           = 32,
    parameter Q               = 8380417,
    parameter REDUCTION_TYPE  = 0,
    parameter PIPELINE_STAGES = 0,
    parameter K_BARRETT       = 23,
    parameter MU              = 8396807,
    parameter K_MONTGOMERY    = 23,
    parameter Q_PRIME         = 8380415,
    parameter R_MOD_Q         = 8191
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] result
);

  localparam MOD_WIDTH = (Q > 0) ? $clog2(Q) : WIDTH;

  wire [MOD_WIDTH-1:0] a_trim = a[MOD_WIDTH-1:0];
  wire [MOD_WIDTH-1:0] b_trim = b[MOD_WIDTH-1:0];

  generate
    if (REDUCTION_TYPE == 0) begin : gen_simple_mod
      wire [2*MOD_WIDTH-1:0] product_comb = a_trim * b_trim;
      wire [WIDTH-1:0] simple_result_comb = product_comb % Q;

      if (PIPELINE_STAGES == 0) begin : gen_no_pipe
        assign result = rst_n ? simple_result_comb : {WIDTH{1'b0}};
      end else if (PIPELINE_STAGES == 1) begin : gen_pipe_1
        reg [MOD_WIDTH-1:0] a_reg;
        reg [MOD_WIDTH-1:0] b_reg;
        reg [WIDTH-1:0] result_reg;

        always @(posedge clk) begin
          a_reg <= a_trim;
          b_reg <= b_trim;
          result_reg <= (a_reg * b_reg) % Q;
        end

        assign result = rst_n ? result_reg : {WIDTH{1'b0}};
      end else begin : gen_pipe
        reg [MOD_WIDTH-1:0] a_reg;
        reg [MOD_WIDTH-1:0] b_reg;
        reg [2*MOD_WIDTH-1:0] product_pipe [0:PIPELINE_STAGES-2];
        reg [WIDTH-1:0] result_reg;
        integer pipe_idx;

        always @(posedge clk) begin
          a_reg <= a_trim;
          b_reg <= b_trim;
          product_pipe[0] <= a_reg * b_reg;
          for (pipe_idx = 1; pipe_idx < PIPELINE_STAGES - 1; pipe_idx = pipe_idx + 1)
            product_pipe[pipe_idx] <= product_pipe[pipe_idx - 1];
          result_reg <= product_pipe[PIPELINE_STAGES-2] % Q;
        end

        assign result = rst_n ? result_reg : {WIDTH{1'b0}};
      end
    end else if (REDUCTION_TYPE == 1) begin : gen_barrett
      barrett_mult #(
          .WIDTH          (WIDTH),
          .Q              (Q),
          .PIPELINE_STAGES(PIPELINE_STAGES),
          .K              (K_BARRETT),
          .MU             (MU)
      ) u_barrett_mult (
          .clk   (clk),
          .rst_n (rst_n),
          .a     (a),
          .b     (b),
          .result(result)
      );
    end else if (REDUCTION_TYPE == 2) begin : gen_montgomery
      wire [2*MOD_WIDTH-1:0] mult_result;
      wire [WIDTH-1:0] montgomery_result_comb;

      montgomery_reduction #(
          .Q            (Q),
          .K            (K_MONTGOMERY),
          .Q_PRIME      (Q_PRIME),
          .PRODUCT_WIDTH(2 * MOD_WIDTH)
      ) montgomery_inst (
          .product(mult_result),
          .result (montgomery_result_comb)
      );

      if (PIPELINE_STAGES == 0) begin : gen_no_pipe
        assign mult_result = a_trim * b_trim;
        assign result = rst_n ? montgomery_result_comb : {WIDTH{1'b0}};
      end else if (PIPELINE_STAGES == 1) begin : gen_pipe_1
        reg [MOD_WIDTH-1:0] a_reg;
        reg [MOD_WIDTH-1:0] b_reg;
        reg [2*MOD_WIDTH-1:0] product_reg;
        reg [WIDTH-1:0] result_reg;

        always @(posedge clk) begin
          a_reg <= a_trim;
          b_reg <= b_trim;
          product_reg <= a_reg * b_reg;
          result_reg <= montgomery_result_comb;
        end

        assign mult_result = product_reg;
        assign result = rst_n ? result_reg : {WIDTH{1'b0}};
      end else begin : gen_pipe
        reg [MOD_WIDTH-1:0] a_reg;
        reg [MOD_WIDTH-1:0] b_reg;
        reg [2*MOD_WIDTH-1:0] product_pipe [0:PIPELINE_STAGES-2];
        reg [WIDTH-1:0] result_reg;
        integer pipe_idx;

        always @(posedge clk) begin
          a_reg <= a_trim;
          b_reg <= b_trim;
          product_pipe[0] <= a_reg * b_reg;
          for (pipe_idx = 1; pipe_idx < PIPELINE_STAGES - 1; pipe_idx = pipe_idx + 1)
            product_pipe[pipe_idx] <= product_pipe[pipe_idx - 1];
          result_reg <= montgomery_result_comb;
        end

        assign mult_result = product_pipe[PIPELINE_STAGES-2];
        assign result = rst_n ? result_reg : {WIDTH{1'b0}};
      end
    end else begin : gen_invalid
      initial begin
        $error("Unsupported REDUCTION_TYPE=%0d in mod_mult", REDUCTION_TYPE);
      end
      assign result = {WIDTH{1'b0}};
    end
  endgenerate

endmodule
