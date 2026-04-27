`timescale 1ns / 1ps

module ntt_butterfly_inverse #(
    parameter WIDTH          = 32,
    parameter Q              = 8380417,
    parameter REDUCTION_TYPE = 0,
    parameter MULT_PIPELINE  = 4
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  a,
    input  wire [WIDTH-1:0]  b,
    input  wire [WIDTH-1:0]  twiddle,
    output wire [WIDTH-1:0]  a_out,
    output wire [WIDTH-1:0]  b_out
);

  localparam MOD_WIDTH = (Q > 0) ? $clog2(Q) : WIDTH;

  generate
    if (WIDTH > MOD_WIDTH) begin : gen_unused_inputs
      (* keep *) wire unused_twiddle;
      assign unused_twiddle = ^twiddle[WIDTH-1:MOD_WIDTH];
    end
  endgenerate

  wire [WIDTH-1:0] sum;
  wire [WIDTH-1:0] diff;
  wire [WIDTH-1:0] sum_aligned;

  mod_add #(.WIDTH(WIDTH), .Q(Q)) add_inst (
      .a(a), .b(b), .result(sum)
  );

  mod_sub #(.WIDTH(WIDTH), .Q(Q)) sub_inst (
      .a(a), .b(b), .result(diff)
  );

  generate
    if (MULT_PIPELINE == 0) begin : gen_sum_align_comb
      assign sum_aligned = sum;
    end else begin : gen_sum_align_pipe
      integer i;
      reg [WIDTH-1:0] sum_pipe [0:MULT_PIPELINE];

      always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (i = 0; i <= MULT_PIPELINE; i = i + 1)
            sum_pipe[i] <= 0;
        end else begin
          sum_pipe[0] <= sum;
          for (i = 1; i <= MULT_PIPELINE; i = i + 1)
            sum_pipe[i] <= sum_pipe[i-1];
        end
      end

      assign sum_aligned = sum_pipe[MULT_PIPELINE];
    end
  endgenerate

  mod_mult #(
      .WIDTH          (WIDTH),
      .Q              (Q),
      .REDUCTION_TYPE (REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) mult_inst (
      .clk   (clk),
      .rst_n (rst_n),
      .a     (diff),
      .b     (twiddle),
      .result(b_out)
  );

  assign a_out = sum_aligned;

endmodule
