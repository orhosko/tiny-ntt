`timescale 1ns / 1ps

// Parameterized true dual-port block RAM wrapper.
//
// This is intended for storage that must infer BRAM instead of LUTRAM.
// Both ports are synchronous read/write. Do not use asynchronous reads if
// BRAM inference is required.
//
// WRITE_MODE:
//   0 = READ_FIRST  : dout shows old memory value on write cycle
//   1 = WRITE_FIRST : dout shows din on write cycle
//   2 = NO_CHANGE   : dout keeps previous value on write cycle
//
// If both ports write the same address in the same cycle, the stored value is
// device/tool dependent. Avoid that collision at the caller.
module bram_tdp #(
    parameter WIDTH      = 24,
    parameter DEPTH      = 4096,
    parameter ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter WRITE_MODE = 1,
    parameter INIT_FILE  = "",
    parameter INIT_ZERO  = 1
) (
    input  wire                  clk,

    input  wire                  en_a,
    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [WIDTH-1:0]      din_a,
    output reg  [WIDTH-1:0]      dout_a,

    input  wire                  en_b,
    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [WIDTH-1:0]      din_b,
    output reg  [WIDTH-1:0]      dout_b
);

  integer init_i;
  (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:DEPTH-1];

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end else if (INIT_ZERO) begin
      for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
        mem[init_i] = {WIDTH{1'b0}};
    end
  end

  always @(posedge clk) begin
    if (en_a) begin
      if (we_a) begin
        if (WRITE_MODE == 0)
          dout_a <= mem[addr_a];
        else if (WRITE_MODE == 1)
          dout_a <= din_a;

        mem[addr_a] <= din_a;
      end else begin
        dout_a <= mem[addr_a];
      end
    end
  end

  always @(posedge clk) begin
    if (en_b) begin
      if (we_b) begin
        if (WRITE_MODE == 0)
          dout_b <= mem[addr_b];
        else if (WRITE_MODE == 1)
          dout_b <= din_b;

        mem[addr_b] <= din_b;
      end else begin
        dout_b <= mem[addr_b];
      end
    end
  end

endmodule
