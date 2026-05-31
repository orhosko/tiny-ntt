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
    output wire [WIDTH-1:0]      dout_a,
    input  wire                  we_a,

    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [WIDTH-1:0]      din_b,
    output wire [WIDTH-1:0]      dout_b,
    input  wire                  we_b
);

  bram_tdp #(
      .WIDTH     (WIDTH),
      .DEPTH     (DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .WRITE_MODE(1),
      .INIT_ZERO (1)
  ) u_mem (
      .clk   (clk),
      .en_a  (1'b1),
      .we_a  (we_a),
      .addr_a(addr_a),
      .din_a (din_a),
      .dout_a(dout_a),
      .en_b  (1'b1),
      .we_b  (we_b),
      .addr_b(addr_b),
      .din_b (din_b),
      .dout_b(dout_b)
  );

endmodule
