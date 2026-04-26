`timescale 1ns / 1ps

module twiddle_bram #(
    parameter WIDTH      = 32,
    parameter DEPTH      = 1024,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter HEX_FILE   = ""
) (
    input  wire                  clk,

    input  wire [ADDR_WIDTH-1:0] addr_a,
    output reg  [WIDTH-1:0]      data_a,

    input  wire [ADDR_WIDTH-1:0] addr_b,
    output reg  [WIDTH-1:0]      data_b
);

  integer i;
  (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

  initial begin
    if (HEX_FILE != "") begin
      $readmemh(HEX_FILE, mem);
    end else begin
      for (i = 0; i < DEPTH; i = i + 1)
        mem[i] = 0;
    end
  end

  generate
    if (OUTPUT_PIPE_STAGES <= 1) begin : gen_single_stage
      always @(posedge clk) begin
        data_a <= mem[addr_a];
        data_b <= mem[addr_b];
      end
    end else begin : gen_two_stage
      reg [WIDTH-1:0] mem_q_a;
      reg [WIDTH-1:0] mem_q_b;

      // Extra output pipelining improves BRAM read timing. Vivado can often
      // absorb the first register into the BRAM output path and leave the
      // second as a fabric stage.
      always @(posedge clk) begin
        mem_q_a <= mem[addr_a];
        mem_q_b <= mem[addr_b];
        data_a  <= mem_q_a;
        data_b  <= mem_q_b;
      end
    end
  endgenerate

endmodule
