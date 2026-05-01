`timescale 1ns / 1ps

module ntt_forward #(
    parameter N              = 4096,
    parameter WIDTH          = 32,
    parameter Q              = 8380417,
    parameter PSI            = 283817,
    parameter ADDR_WIDTH     = $clog2(N),
    parameter REDUCTION_TYPE = 0,
    parameter PARALLEL       = 8,
    parameter MULT_PIPELINE  = 4,
    parameter TWIDDLE_FILE   = "twiddle_forward_4096.hex"
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  start,
    output wire                  done,
    output wire                  busy,
    input  wire                  load_coeff,
    input  wire [ADDR_WIDTH-1:0] load_addr,
    input  wire [WIDTH-1:0]      load_data,
    input  wire [ADDR_WIDTH-1:0] read_addr,
    output wire [WIDTH-1:0]      read_data
);

  localparam LOGN = $clog2(N);
  localparam TOTAL_BUTTERFLIES = N / 2;
  localparam BANKS = (N < PARALLEL) ? N : PARALLEL;
  localparam BANK_DEPTH = (N + BANKS - 1) / BANKS;
  localparam BANK_ADDR_WIDTH = $clog2(BANKS);
  localparam BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH);
  localparam OUTPUT_BANK = (LOGN % 2 == 0) ? 0 : 1;
  localparam TWIDDLE_ADDR_REG_LATENCY = 1;
  localparam BRAM_LATENCY = 2 + TWIDDLE_ADDR_REG_LATENCY;
  localparam WRITEBACK_LATENCY = 1;
  localparam TOTAL_PIPE_DEPTH = MULT_PIPELINE + BRAM_LATENCY + WRITEBACK_LATENCY;

  wire [LOGN-1:0] stage;
  wire [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  wire [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  wire [PARALLEL-1:0] lane_valid;
  wire ctrl_done;
  wire ctrl_busy;
  reg ctrl_done_latched;
  wire ctrl_draining;

  wire [PARALLEL*ADDR_WIDTH-1:0] addr0;
  wire [PARALLEL*ADDR_WIDTH-1:0] addr1;
  wire [PARALLEL*ADDR_WIDTH-1:0] twiddle_addr;
  wire [PARALLEL*ADDR_WIDTH-1:0] addr0_out;
  wire [PARALLEL*ADDR_WIDTH-1:0] addr1_out;
  wire [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_bank;
  wire [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_bank;
  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_index;
  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_index;
  wire [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_out_bank;
  wire [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_out_bank;
  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_out_index;
  wire [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_out_index;

  reg [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe [0:TOTAL_PIPE_DEPTH];
  reg [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe [0:TOTAL_PIPE_DEPTH];
  reg [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe [0:TOTAL_PIPE_DEPTH];
  reg [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe [0:TOTAL_PIPE_DEPTH];
  reg [PARALLEL-1:0] lane_valid_pipe [0:TOTAL_PIPE_DEPTH];

  wire [PARALLEL*WIDTH-1:0] coeff_a_raw;
  wire [PARALLEL*WIDTH-1:0] coeff_b_raw;
  reg [PARALLEL*WIDTH-1:0] coeff_a;
  reg [PARALLEL*WIDTH-1:0] coeff_b;
  reg [PARALLEL*WIDTH-1:0] coeff_a_aligned;
  reg [PARALLEL*WIDTH-1:0] coeff_b_aligned;
  wire [PARALLEL*WIDTH-1:0] a_out;
  wire [PARALLEL*WIDTH-1:0] b_out;
  reg [PARALLEL*WIDTH-1:0] wb_a_out;
  reg [PARALLEL*WIDTH-1:0] wb_b_out;
  reg [PARALLEL*ADDR_WIDTH-1:0] twiddle_addr_reg;
  wire [PARALLEL*WIDTH-1:0] twiddle;

  wire read_bank_sel;
  wire write_bank_sel;
  wire [TOTAL_PIPE_DEPTH:0] write_bank_sel_pipe;
  wire pipe_active;
  wire lane_valid_any;

  assign lane_valid_any = |lane_valid;

  ntt_control_parallel #(
      .N(N),
      .PARALLEL(PARALLEL),
      .PIPELINE_DEPTH(TOTAL_PIPE_DEPTH + 1)
  ) u_control (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .stall(1'b0),
      .done(ctrl_done),
      .busy(ctrl_busy),
      .draining(ctrl_draining),
      .stage(stage),
      .butterfly(butterfly_base),
      .cycle(cycle),
      .lane_valid(lane_valid)
  );

  twiddle_bram_multiport #(
      .DEPTH(N),
      .WIDTH(WIDTH),
      .PARALLEL(PARALLEL),
      .ADDR_WIDTH(ADDR_WIDTH),
      .HEX_FILE(TWIDDLE_FILE),
      .OUTPUT_PIPE_STAGES(BRAM_LATENCY)
  ) u_twiddle_bram (
      .clk(clk),
      .addr(twiddle_addr_reg),
      .data(twiddle)
  );

  ntt_cg_address_gen #(
      .N(N),
      .ADDR_WIDTH(ADDR_WIDTH),
      .PARALLEL(PARALLEL),
      .BANKS(BANKS),
      .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH),
      .BANK_DEPTH_WIDTH(BANK_DEPTH_WIDTH)
  ) u_addr_gen (
      .stage(stage),
      .butterfly_base(butterfly_base),
      .lane_valid(lane_valid),
      .addr0(addr0),
      .addr1(addr1),
      .addr0_out(addr0_out),
      .addr1_out(addr1_out),
      .twiddle_addr(twiddle_addr),
      .addr0_bank(addr0_bank),
      .addr1_bank(addr1_bank),
      .addr0_index(addr0_index),
      .addr1_index(addr1_index),
      .addr0_out_bank(addr0_out_bank),
      .addr1_out_bank(addr1_out_bank),
      .addr0_out_index(addr0_out_index),
      .addr1_out_index(addr1_out_index)
  );

  ntt_bank_switch #(
      .LOGN(LOGN),
      .PARALLEL(PARALLEL),
      .MULT_PIPELINE(MULT_PIPELINE),
      .TOTAL_PIPE_DEPTH(TOTAL_PIPE_DEPTH)
  ) u_bank_switch (
      .clk(clk),
      .rst_n(rst_n),
      .stage(stage),
      .lane_valid_any(lane_valid_any),
      .lane_valid_last(lane_valid_pipe[TOTAL_PIPE_DEPTH]),
      .read_bank_sel(read_bank_sel),
      .write_bank_sel(write_bank_sel),
      .write_bank_sel_pipe(write_bank_sel_pipe),
      .pipe_active(pipe_active)
  );

  ntt_coeff_banks #(
      .N(N),
      .WIDTH(WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .PARALLEL(PARALLEL),
      .BANKS(BANKS),
      .BANK_DEPTH(BANK_DEPTH),
      .BANK_ADDR_WIDTH(BANK_ADDR_WIDTH),
      .BANK_DEPTH_WIDTH(BANK_DEPTH_WIDTH),
      .PIPE_DEPTH(TOTAL_PIPE_DEPTH),
      .OUTPUT_BANK(OUTPUT_BANK)
  ) u_coeff_banks (
      .clk(clk),
      .rst_n(rst_n),
      .load_enable(load_coeff && !busy),
      .load_addr(load_addr),
      .load_data(load_data),
      .read_addr(read_addr),
      .read_data(read_data),
      .read_bank_sel(read_bank_sel),
      .rd_bank_a(addr0_bank),
      .rd_index_a(addr0_index),
      .rd_bank_b(addr1_bank),
      .rd_index_b(addr1_index),
      .coeff_a(coeff_a_raw),
      .coeff_b(coeff_b_raw),
      .write_enable(busy),
      .write_bank_sel(write_bank_sel_pipe[TOTAL_PIPE_DEPTH]),
      .wr_valid(lane_valid_pipe[TOTAL_PIPE_DEPTH]),
      .wr_bank_a(addr0_out_bank_pipe[TOTAL_PIPE_DEPTH]),
      .wr_index_a(addr0_out_index_pipe[TOTAL_PIPE_DEPTH]),
      .wr_bank_b(addr1_out_bank_pipe[TOTAL_PIPE_DEPTH]),
      .wr_index_b(addr1_out_index_pipe[TOTAL_PIPE_DEPTH]),
      .result_a(wb_a_out),
      .result_b(wb_b_out)
  );

  integer stage_idx;
  always @(posedge clk) begin
    if (!rst_n) begin
      coeff_a <= 0;
      coeff_b <= 0;
      coeff_a_aligned <= 0;
      coeff_b_aligned <= 0;
      wb_a_out <= 0;
      wb_b_out <= 0;
      twiddle_addr_reg <= 0;
      for (stage_idx = 0; stage_idx <= TOTAL_PIPE_DEPTH; stage_idx = stage_idx + 1) begin
        addr0_out_bank_pipe[stage_idx] <= 0;
        addr1_out_bank_pipe[stage_idx] <= 0;
        addr0_out_index_pipe[stage_idx] <= 0;
        addr1_out_index_pipe[stage_idx] <= 0;
        lane_valid_pipe[stage_idx] <= 0;
      end
    end else begin
      coeff_a <= coeff_a_raw;
      coeff_b <= coeff_b_raw;
      coeff_a_aligned <= coeff_a;
      coeff_b_aligned <= coeff_b;
      wb_a_out <= a_out;
      wb_b_out <= b_out;
      twiddle_addr_reg <= twiddle_addr;
      lane_valid_pipe[0] <= lane_valid;
      if (|lane_valid) begin
        addr0_out_bank_pipe[0] <= addr0_out_bank;
        addr1_out_bank_pipe[0] <= addr1_out_bank;
        addr0_out_index_pipe[0] <= addr0_out_index;
        addr1_out_index_pipe[0] <= addr1_out_index;
      end

      for (stage_idx = 1; stage_idx <= TOTAL_PIPE_DEPTH; stage_idx = stage_idx + 1) begin
        addr0_out_bank_pipe[stage_idx] <= addr0_out_bank_pipe[stage_idx - 1];
        addr1_out_bank_pipe[stage_idx] <= addr1_out_bank_pipe[stage_idx - 1];
        addr0_out_index_pipe[stage_idx] <= addr0_out_index_pipe[stage_idx - 1];
        addr1_out_index_pipe[stage_idx] <= addr1_out_index_pipe[stage_idx - 1];
        lane_valid_pipe[stage_idx] <= lane_valid_pipe[stage_idx - 1];
      end
    end
  end

  genvar lane;
  generate
    for (lane = 0; lane < PARALLEL; lane = lane + 1) begin : gen_butterflies
      ntt_butterfly #(
          .WIDTH(WIDTH),
          .Q(Q),
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .MULT_PIPELINE(MULT_PIPELINE)
      ) u_butterfly (
          .clk(clk),
          .rst_n(rst_n),
          .a(coeff_a_aligned[lane*WIDTH +: WIDTH]),
          .b(coeff_b_aligned[lane*WIDTH +: WIDTH]),
          .twiddle(twiddle[lane*WIDTH +: WIDTH]),
          .a_out(a_out[lane*WIDTH +: WIDTH]),
          .b_out(b_out[lane*WIDTH +: WIDTH])
      );
    end
  endgenerate

  always @(posedge clk) begin
    if (!rst_n)
      ctrl_done_latched <= 1'b0;
    else begin
      if (ctrl_done)
        ctrl_done_latched <= 1'b1;
      else if (ctrl_done_latched && !pipe_active)
        ctrl_done_latched <= 1'b0;
    end
  end

  assign busy = ctrl_busy || pipe_active || ctrl_done_latched;
  assign done = ctrl_done_latched && !pipe_active;

endmodule
