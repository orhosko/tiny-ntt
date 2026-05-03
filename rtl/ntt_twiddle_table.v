`timescale 1ns / 1ps

module ntt_twiddle_table #(
    parameter WIDTH          = 32,
    parameter Q              = 8380417,
    parameter PSI            = 283817,
    parameter ADDR_WIDTH     = 12,
    parameter TWIDDLE_DEPTH  = 4096,
    parameter REDUCTION_TYPE = 0,
    parameter MULT_PIPELINE  = 4
) (
    input  wire                           clk,
    input  wire                           rst_n,
    output reg                            tw_ready,
    output wire [TWIDDLE_DEPTH*WIDTH-1:0] twiddle_flat
);

  localparam MULT_LATENCY = (MULT_PIPELINE == 0) ? 1 : (MULT_PIPELINE + 1);
  localparam [1:0] TW_IDLE  = 2'b00;
  localparam [1:0] TW_TABLE = 2'b01;
  localparam [1:0] TW_READY = 2'b10;
  localparam [WIDTH-1:0] PSI_VALUE = PSI;

  reg [1:0] tw_state;
  reg [ADDR_WIDTH-1:0] tw_index;
  reg [WIDTH-1:0] tw_mul_a;
  reg [WIDTH-1:0] tw_mul_b;
  wire [WIDTH-1:0] tw_mul_result;
  reg [ADDR_WIDTH-1:0] tw_mul_count;
  reg tw_mul_start;
  wire tw_mul_done;
  reg [WIDTH-1:0] twiddle_table [0:TWIDDLE_DEPTH-1];

  mod_mult #(
      .WIDTH(WIDTH),
      .Q(Q),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) u_twiddle_mult (
      .clk(clk),
      .rst_n(rst_n),
      .a(tw_mul_a),
      .b(tw_mul_b),
      .result(tw_mul_result)
  );

  always @(posedge clk) begin
    if (!rst_n)
      tw_mul_count <= 0;
    else if (tw_mul_start)
      tw_mul_count <= MULT_LATENCY[ADDR_WIDTH-1:0];
    else if (tw_mul_count != 0)
      tw_mul_count <= tw_mul_count - 1'b1;
  end

  assign tw_mul_done = (tw_mul_count == 1);

  genvar i;
  generate
    for (i = 0; i < TWIDDLE_DEPTH; i = i + 1) begin : gen_twiddle_table
      always @(posedge clk) begin
        if (!rst_n) begin
          if (i == 0)
            twiddle_table[i] <= {{(WIDTH-1){1'b0}}, 1'b1};
          else
            twiddle_table[i] <= 0;
        end else if (!tw_ready) begin
          if (tw_state == TW_IDLE) begin
            if (i == 0)
              twiddle_table[i] <= {{(WIDTH-1){1'b0}}, 1'b1};
          end else if (tw_state == TW_TABLE && tw_mul_done && tw_index == i[ADDR_WIDTH-1:0]) begin
            twiddle_table[i] <= tw_mul_result;
          end
        end
      end

      assign twiddle_flat[i*WIDTH +: WIDTH] = twiddle_table[i];
    end
  endgenerate

  always @(posedge clk) begin
    if (!rst_n) begin
      tw_state <= TW_IDLE;
      tw_ready <= 1'b0;
      tw_index <= 0;
      tw_mul_start <= 1'b0;
      tw_mul_a <= 0;
      tw_mul_b <= 0;
    end else begin
      tw_mul_start <= 1'b0;
      if (!tw_ready) begin
        if (tw_state == TW_IDLE) begin
          if (TWIDDLE_DEPTH == 1) begin
            tw_state <= TW_READY;
            tw_ready <= 1'b1;
          end else begin
            tw_state <= TW_TABLE;
            tw_index <= 1;
            tw_mul_a <= {{(WIDTH-1){1'b0}}, 1'b1};
            tw_mul_b <= PSI_VALUE;
            tw_mul_start <= 1'b1;
          end
        end else if (tw_state == TW_TABLE) begin
          if (tw_mul_done) begin
            if (tw_index == (TWIDDLE_DEPTH - 1)) begin
              tw_state <= TW_READY;
              tw_ready <= 1'b1;
            end else begin
              tw_index <= tw_index + 1'b1;
              tw_mul_a <= tw_mul_result;
              tw_mul_b <= PSI_VALUE;
              tw_mul_start <= 1'b1;
            end
          end
        end
      end
    end
  end

endmodule
