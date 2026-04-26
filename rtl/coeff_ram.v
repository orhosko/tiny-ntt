`timescale 1ns / 1ps

module coeff_ram #(
    parameter WIDTH      = 32,
    parameter DEPTH      = 1024,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [WIDTH-1:0]      din_a,
    output reg  [WIDTH-1:0]      dout_a,
    input  wire                  we_a,

    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [WIDTH-1:0]      din_b,
    output reg  [WIDTH-1:0]      dout_b,
    input  wire                  we_b
);

  integer i;
  (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

  initial begin
    for (i = 0; i < DEPTH; i = i + 1)
      mem[i] = 0;
  end

  always @(posedge clk) begin
    if (we_a) begin
      mem[addr_a] <= din_a;
      dout_a      <= din_a;
    end else begin
      dout_a <= mem[addr_a];
    end
  end

  always @(posedge clk) begin
    if (we_b) begin
      mem[addr_b] <= din_b;
      dout_b      <= din_b;
    end else begin
      dout_b <= mem[addr_b];
    end
  end

endmodule
