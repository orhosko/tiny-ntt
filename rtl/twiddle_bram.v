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

  always @(posedge clk)
    data_a <= mem[addr_a];

  always @(posedge clk)
    data_b <= mem[addr_b];

endmodule
