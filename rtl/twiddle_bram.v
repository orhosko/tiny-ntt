`timescale 1ns / 1ps

module twiddle_bram #(
    parameter WIDTH      = 32,
    parameter DEPTH      = 4096,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter HEX_FILE   = "",
    parameter OUTPUT_PIPE_STAGES = 2
) (
    input  wire                  clk,

    input  wire [ADDR_WIDTH-1:0] addr_a,
    output wire [WIDTH-1:0]      data_a,

    input  wire [ADDR_WIDTH-1:0] addr_b,
    output wire [WIDTH-1:0]      data_b
);

  wire [WIDTH-1:0] bram_data_a;
  wire [WIDTH-1:0] bram_data_b;

  bram_tdp #(
      .WIDTH     (WIDTH),
      .DEPTH     (DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .WRITE_MODE(0),
      .INIT_FILE (HEX_FILE),
      .INIT_ZERO (1)
  ) u_mem (
      .clk   (clk),
      .en_a  (1'b1),
      .we_a  (1'b0),
      .addr_a(addr_a),
      .din_a ({WIDTH{1'b0}}),
      .dout_a(bram_data_a),
      .en_b  (1'b1),
      .we_b  (1'b0),
      .addr_b(addr_b),
      .din_b ({WIDTH{1'b0}}),
      .dout_b(bram_data_b)
  );

  generate
    if (OUTPUT_PIPE_STAGES <= 1) begin : gen_single_stage
      assign data_a = bram_data_a;
      assign data_b = bram_data_b;
    end else begin : gen_two_stage
      reg [WIDTH-1:0] data_a_q;
      reg [WIDTH-1:0] data_b_q;

      // Extra output pipelining improves BRAM read timing. Vivado can often
      // absorb the first register into the BRAM output path and leave the
      // second as a fabric stage.
      always @(posedge clk) begin
        data_a_q <= bram_data_a;
        data_b_q <= bram_data_b;
      end

      assign data_a = data_a_q;
      assign data_b = data_b_q;
    end
  endgenerate

endmodule
