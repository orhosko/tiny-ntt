`timescale 1ns / 1ps

module ntt_butterfly #(
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

  wire [WIDTH-1:0] twiddle_mult_b;
  wire [WIDTH-1:0] a_aligned;

  generate
    if (MULT_PIPELINE == 0) begin : gen_align_comb
      assign a_aligned = a;
    end else begin : gen_align_pipe
      integer i;
      reg [WIDTH-1:0] a_pipe [0:MULT_PIPELINE];

      always @(posedge clk) begin
        if (!rst_n) begin
          for (i = 0; i <= MULT_PIPELINE; i = i + 1)
            a_pipe[i] <= 0;
        end else begin
          a_pipe[0] <= a;
          for (i = 1; i <= MULT_PIPELINE; i = i + 1)
            a_pipe[i] <= a_pipe[i-1];
        end
      end

      assign a_aligned = a_pipe[MULT_PIPELINE];
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
      .a     (twiddle),
      .b     (b),
      .result(twiddle_mult_b)
  );

  mod_add #(
      .WIDTH(WIDTH),
      .Q    (Q)
  ) add_inst (
      .a     (a_aligned),
      .b     (twiddle_mult_b),
      .result(a_out)
  );

  mod_sub #(
      .WIDTH(WIDTH),
      .Q    (Q)
  ) sub_inst (
      .a     (a_aligned),
      .b     (twiddle_mult_b),
      .result(b_out)
  );

endmodule
