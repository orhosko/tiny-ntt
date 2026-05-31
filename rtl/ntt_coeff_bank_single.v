`timescale 1ns / 1ps

module ntt_coeff_bank_single #(
    parameter WIDTH      = 32,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  wire                  clk,

    input  wire [ADDR_WIDTH-1:0] rd_addr_a,
    output wire [WIDTH-1:0]      rd_data_a,

    input  wire [ADDR_WIDTH-1:0] rd_addr_b,
    output wire [WIDTH-1:0]      rd_data_b,

    input  wire                  wr_en_1,
    input  wire [ADDR_WIDTH-1:0] wr_addr_1,
    input  wire [WIDTH-1:0]      wr_data_1,

    input  wire                  wr_en_2,
    input  wire [ADDR_WIDTH-1:0] wr_addr_2,
    input  wire [WIDTH-1:0]      wr_data_2
);

  localparam HALF_DEPTH = DEPTH / 2;
  localparam HALF_ADDR_WIDTH = (HALF_DEPTH <= 1) ? 1 : $clog2(HALF_DEPTH);

  wire rd_a_hi = rd_addr_a[ADDR_WIDTH-1];
  wire rd_b_hi = rd_addr_b[ADDR_WIDTH-1];
  wire wr_1_hi = wr_addr_1[ADDR_WIDTH-1];
  wire wr_2_hi = wr_addr_2[ADDR_WIDTH-1];

  wire [HALF_ADDR_WIDTH-1:0] rd_addr_a_half = rd_addr_a[HALF_ADDR_WIDTH-1:0];
  wire [HALF_ADDR_WIDTH-1:0] rd_addr_b_half = rd_addr_b[HALF_ADDR_WIDTH-1:0];
  wire [HALF_ADDR_WIDTH-1:0] wr_addr_1_half = wr_addr_1[HALF_ADDR_WIDTH-1:0];
  wire [HALF_ADDR_WIDTH-1:0] wr_addr_2_half = wr_addr_2[HALF_ADDR_WIDTH-1:0];

  reg rd_a_hi_q;
  reg rd_b_hi_q;
  wire [WIDTH-1:0] rd_data_a_lo;
  wire [WIDTH-1:0] rd_data_a_hi;
  wire [WIDTH-1:0] rd_data_b_lo;
  wire [WIDTH-1:0] rd_data_b_hi;

  wire lo_wr_en = (wr_en_2 && !wr_2_hi) || (wr_en_1 && !wr_1_hi);
  wire hi_wr_en = (wr_en_2 &&  wr_2_hi) || (wr_en_1 &&  wr_1_hi);
  wire [HALF_ADDR_WIDTH-1:0] lo_wr_addr = (wr_en_2 && !wr_2_hi) ? wr_addr_2_half
                                                               : wr_addr_1_half;
  wire [HALF_ADDR_WIDTH-1:0] hi_wr_addr = (wr_en_2 &&  wr_2_hi) ? wr_addr_2_half
                                                               : wr_addr_1_half;
  wire [WIDTH-1:0] lo_wr_data = (wr_en_2 && !wr_2_hi) ? wr_data_2 : wr_data_1;
  wire [WIDTH-1:0] hi_wr_data = (wr_en_2 &&  wr_2_hi) ? wr_data_2 : wr_data_1;

  wire [HALF_ADDR_WIDTH-1:0] lo_port_b_addr = lo_wr_en ? lo_wr_addr : rd_addr_b_half;
  wire [HALF_ADDR_WIDTH-1:0] hi_port_b_addr = hi_wr_en ? hi_wr_addr : rd_addr_b_half;

  assign rd_data_a = rd_a_hi_q ? rd_data_a_hi : rd_data_a_lo;
  assign rd_data_b = rd_b_hi_q ? rd_data_b_hi : rd_data_b_lo;

  bram_tdp #(
      .WIDTH     (WIDTH),
      .DEPTH     (HALF_DEPTH),
      .ADDR_WIDTH(HALF_ADDR_WIDTH),
      .WRITE_MODE(1),
      .INIT_ZERO (1)
  ) u_mem_lo (
      .clk   (clk),
      .en_a  (1'b1),
      .we_a  (1'b0),
      .addr_a(rd_addr_a_half),
      .din_a ({WIDTH{1'b0}}),
      .dout_a(rd_data_a_lo),
      .en_b  (1'b1),
      .we_b  (lo_wr_en),
      .addr_b(lo_port_b_addr),
      .din_b (lo_wr_data),
      .dout_b(rd_data_b_lo)
  );

  bram_tdp #(
      .WIDTH     (WIDTH),
      .DEPTH     (HALF_DEPTH),
      .ADDR_WIDTH(HALF_ADDR_WIDTH),
      .WRITE_MODE(1),
      .INIT_ZERO (1)
  ) u_mem_hi (
      .clk   (clk),
      .en_a  (1'b1),
      .we_a  (1'b0),
      .addr_a(rd_addr_a_half),
      .din_a ({WIDTH{1'b0}}),
      .dout_a(rd_data_a_hi),
      .en_b  (1'b1),
      .we_b  (hi_wr_en),
      .addr_b(hi_port_b_addr),
      .din_b (hi_wr_data),
      .dout_b(rd_data_b_hi)
  );

  // Port A is read-only on both physical halves. The registered half select
  // preserves the original one-cycle synchronous read latency.
  always @(posedge clk) begin
    rd_a_hi_q <= rd_a_hi;
  end

  // Port B is either a write or a read on each physical half. This is the
  // legal true-dual-port BRAM shape Vivado can infer.
  always @(posedge clk) begin
    rd_b_hi_q <= rd_b_hi;
  end

endmodule
