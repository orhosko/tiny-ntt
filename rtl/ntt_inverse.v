`timescale 1ns / 1ps

//==============================================================================
// Inverse NTT Module
//==============================================================================
// Complete inverse radix-2 Cooley-Tukey NTT pipeline
//
// Performs INTT with final scaling by N^(-1)
//
// Flow:
//   1. Load NTT-transformed coefficients
//   2. Run inverse NTT
//   3. Scale by N^(-1)
//   4. Read results
//==============================================================================

module ntt_inverse #(
    parameter int N              = 4096,
    parameter int WIDTH          = 32,
    parameter int Q              = 8380417,
    parameter int PSI_INV        = 7893065,
    parameter int ADDR_WIDTH     = $clog2(N),
    parameter int REDUCTION_TYPE = 0,
    parameter int N_INV          = 8378371,
    parameter int PARALLEL       = 8,
    parameter int MULT_PIPELINE  = 3,
    parameter     TWIDDLE_FILE   = "twiddle_inverse_4096.hex"
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  start,
    output logic                  done,
    output logic                  busy,
    input  logic                  load_coeff,
    input  logic [ADDR_WIDTH-1:0] load_addr,
    input  logic [WIDTH-1:0]      load_data,
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [WIDTH-1:0]      read_data
);

  typedef enum logic [1:0] {
    IDLE         = 2'b00,
    INTT_COMPUTE = 2'b01,
    SCALE        = 2'b10,
    DONE_STATE   = 2'b11
  } state_t;

  localparam int LOGN = $clog2(N);
  localparam int TOTAL_BUTTERFLIES = N / 2;
  localparam int BANKS = (N < PARALLEL) ? N : PARALLEL;
  localparam int BANK_DEPTH = (N + BANKS - 1) / BANKS;
  localparam int BANK_ADDR_WIDTH = $clog2(BANKS);
  localparam int BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH);
  localparam int OUTPUT_BANK = (LOGN % 2 == 0) ? 0 : 1;
  localparam int BRAM_LATENCY = 2;
  localparam int TOTAL_PIPE_DEPTH = MULT_PIPELINE + BRAM_LATENCY;
  localparam int SCALE_PIPE_DEPTH = MULT_PIPELINE + 1;

  state_t state, next_state;

  logic intt_done;
  logic ctrl_busy;
  logic ctrl_draining;
  logic intt_done_latched;

  logic [LOGN-1:0] stage;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  logic [PARALLEL-1:0] lane_valid;

  logic [PARALLEL*ADDR_WIDTH-1:0] addr0;
  logic [PARALLEL*ADDR_WIDTH-1:0] addr1;
  logic [PARALLEL*ADDR_WIDTH-1:0] twiddle_addr;
  logic [PARALLEL*ADDR_WIDTH-1:0] addr0_out;
  logic [PARALLEL*ADDR_WIDTH-1:0] addr1_out;
  logic [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_bank;
  logic [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_bank;
  logic [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_index;
  logic [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_index;
  logic [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_out_bank;
  logic [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_out_bank;
  logic [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_out_index;
  logic [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_out_index;

  logic [PARALLEL*BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe [0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL*BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe [0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe [0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL*BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe [0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0] lane_valid_pipe [0:TOTAL_PIPE_DEPTH];

  logic [PARALLEL*WIDTH-1:0] coeff_a_raw;
  logic [PARALLEL*WIDTH-1:0] coeff_b_raw;
  logic [PARALLEL*WIDTH-1:0] coeff_a;
  logic [PARALLEL*WIDTH-1:0] coeff_b;
  logic [PARALLEL*WIDTH-1:0] a_out;
  logic [PARALLEL*WIDTH-1:0] b_out;
  logic [PARALLEL*WIDTH-1:0] twiddle;

  logic read_bank_sel;
  logic write_bank_sel;
  logic [TOTAL_PIPE_DEPTH:0] write_bank_sel_pipe;
  logic pipe_active;
  logic lane_valid_any;

  logic [ADDR_WIDTH:0] scale_addr;
  logic [ADDR_WIDTH:0] scale_addr_pipe[0:SCALE_PIPE_DEPTH];
  logic [SCALE_PIPE_DEPTH:0] scale_valid_pipe;
  logic [WIDTH-1:0] scale_result;
  logic [ADDR_WIDTH-1:0] coeff_read_addr;
  logic [WIDTH-1:0] coeff_read_data;
  logic scale_write_enable;
  logic [ADDR_WIDTH-1:0] scale_write_addr;
  logic [WIDTH-1:0] scaling_factor;

  assign lane_valid_any = |lane_valid;
  assign scaling_factor = N_INV;
  assign coeff_read_addr = (state == SCALE) ? scale_addr[ADDR_WIDTH-1:0] : read_addr;
  assign scale_write_enable = scale_valid_pipe[SCALE_PIPE_DEPTH];
  assign scale_write_addr = scale_addr_pipe[SCALE_PIPE_DEPTH][ADDR_WIDTH-1:0];

  always_ff @(posedge clk) begin
    if (!rst_n)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start)
          next_state = INTT_COMPUTE;
      end

      INTT_COMPUTE: begin
        if (intt_done_latched && !pipe_active)
          next_state = SCALE;
      end

      SCALE: begin
        if (scale_addr >= N && !scale_valid_pipe[SCALE_PIPE_DEPTH])
          next_state = DONE_STATE;
      end

      DONE_STATE: begin
        if (!start)
          next_state = IDLE;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      intt_done_latched <= 1'b0;
    end else if (state != INTT_COMPUTE) begin
      intt_done_latched <= 1'b0;
    end else begin
      if (intt_done)
        intt_done_latched <= 1'b1;
      else if (intt_done_latched && !pipe_active)
        intt_done_latched <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    integer stage_idx;
    if (!rst_n) begin
      scale_addr <= '0;
      for (stage_idx = 0; stage_idx <= SCALE_PIPE_DEPTH; stage_idx = stage_idx + 1) begin
        scale_addr_pipe[stage_idx] <= '0;
        scale_valid_pipe[stage_idx] <= 1'b0;
      end
    end else begin
      if (state == SCALE && scale_addr < N)
        scale_addr <= scale_addr + 1'b1;
      else if (state != SCALE)
        scale_addr <= '0;

      scale_addr_pipe[0] <= scale_addr;
      scale_valid_pipe[0] <= (state == SCALE) && (scale_addr < N);

      for (stage_idx = 1; stage_idx <= SCALE_PIPE_DEPTH; stage_idx = stage_idx + 1) begin
        scale_addr_pipe[stage_idx] <= scale_addr_pipe[stage_idx - 1];
        scale_valid_pipe[stage_idx] <= scale_valid_pipe[stage_idx - 1];
      end
    end
  end

  ntt_control_parallel #(
      .N             (N),
      .PARALLEL      (PARALLEL),
      .PIPELINE_DEPTH(TOTAL_PIPE_DEPTH + 1)
  ) u_control (
      .clk       (clk),
      .rst_n     (rst_n),
      .start     ((state == IDLE) && start),
      .stall     (1'b0),
      .done      (intt_done),
      .busy      (ctrl_busy),
      .draining  (ctrl_draining),
      .stage     (stage),
      .butterfly (butterfly_base),
      .cycle     (cycle),
      .lane_valid(lane_valid)
  );

  ntt_cg_address_gen #(
      .N               (N),
      .ADDR_WIDTH      (ADDR_WIDTH),
      .PARALLEL        (PARALLEL),
      .BANKS           (BANKS),
      .BANK_ADDR_WIDTH (BANK_ADDR_WIDTH),
      .BANK_DEPTH_WIDTH(BANK_DEPTH_WIDTH)
  ) u_addr_gen (
      .stage         (stage),
      .butterfly_base(butterfly_base),
      .lane_valid    (lane_valid),
      .addr0         (addr0),
      .addr1         (addr1),
      .addr0_out     (addr0_out),
      .addr1_out     (addr1_out),
      .twiddle_addr  (twiddle_addr),
      .addr0_bank    (addr0_bank),
      .addr1_bank    (addr1_bank),
      .addr0_index   (addr0_index),
      .addr1_index   (addr1_index),
      .addr0_out_bank(addr0_out_bank),
      .addr1_out_bank(addr1_out_bank),
      .addr0_out_index(addr0_out_index),
      .addr1_out_index(addr1_out_index)
  );

  twiddle_bram_multiport #(
      .DEPTH             (N),
      .WIDTH             (WIDTH),
      .PARALLEL          (PARALLEL),
      .ADDR_WIDTH        (ADDR_WIDTH),
      .HEX_FILE          (TWIDDLE_FILE),
      .OUTPUT_PIPE_STAGES(BRAM_LATENCY)
  ) u_twiddle_bram (
      .clk (clk),
      .addr(twiddle_addr),
      .data(twiddle)
  );

  ntt_bank_switch #(
      .LOGN           (LOGN),
      .PARALLEL       (PARALLEL),
      .MULT_PIPELINE  (MULT_PIPELINE),
      .TOTAL_PIPE_DEPTH(TOTAL_PIPE_DEPTH)
  ) u_bank_switch (
      .clk               (clk),
      .rst_n             (rst_n),
      .stage             (stage),
      .lane_valid_any    (lane_valid_any),
      .lane_valid_last   (lane_valid_pipe[TOTAL_PIPE_DEPTH]),
      .read_bank_sel     (read_bank_sel),
      .write_bank_sel    (write_bank_sel),
      .write_bank_sel_pipe(write_bank_sel_pipe),
      .pipe_active       (pipe_active)
  );

  ntt_coeff_banks #(
      .N               (N),
      .WIDTH           (WIDTH),
      .ADDR_WIDTH      (ADDR_WIDTH),
      .PARALLEL        (PARALLEL),
      .BANKS           (BANKS),
      .BANK_DEPTH      (BANK_DEPTH),
      .BANK_ADDR_WIDTH (BANK_ADDR_WIDTH),
      .BANK_DEPTH_WIDTH(BANK_DEPTH_WIDTH),
      .PIPE_DEPTH      (TOTAL_PIPE_DEPTH),
      .OUTPUT_BANK     (OUTPUT_BANK)
  ) u_coeff_banks (
      .clk            (clk),
      .rst_n          (rst_n),
      .load_enable    (load_coeff && (state == IDLE)),
      .load_addr      (load_addr),
      .load_data      (load_data),
      .read_addr      (coeff_read_addr),
      .read_data      (coeff_read_data),
      .ext_write_enable(scale_write_enable),
      .ext_write_addr (scale_write_addr),
      .ext_write_data (scale_result),
      .read_bank_sel  (read_bank_sel),
      .rd_bank_a      (addr0_bank),
      .rd_index_a     (addr0_index),
      .rd_bank_b      (addr1_bank),
      .rd_index_b     (addr1_index),
      .coeff_a        (coeff_a_raw),
      .coeff_b        (coeff_b_raw),
      .write_enable   (state == INTT_COMPUTE),
      .write_bank_sel (write_bank_sel_pipe[TOTAL_PIPE_DEPTH]),
      .wr_valid       (lane_valid_pipe[TOTAL_PIPE_DEPTH]),
      .wr_bank_a      (addr0_out_bank_pipe[TOTAL_PIPE_DEPTH]),
      .wr_index_a     (addr0_out_index_pipe[TOTAL_PIPE_DEPTH]),
      .wr_bank_b      (addr1_out_bank_pipe[TOTAL_PIPE_DEPTH]),
      .wr_index_b     (addr1_out_index_pipe[TOTAL_PIPE_DEPTH]),
      .result_a       (a_out),
      .result_b       (b_out)
  );

  integer pipe_stage_idx;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      coeff_a <= '0;
      coeff_b <= '0;
      for (pipe_stage_idx = 0; pipe_stage_idx <= TOTAL_PIPE_DEPTH; pipe_stage_idx = pipe_stage_idx + 1) begin
        addr0_out_bank_pipe[pipe_stage_idx] <= '0;
        addr1_out_bank_pipe[pipe_stage_idx] <= '0;
        addr0_out_index_pipe[pipe_stage_idx] <= '0;
        addr1_out_index_pipe[pipe_stage_idx] <= '0;
        lane_valid_pipe[pipe_stage_idx] <= '0;
      end
    end else begin
      coeff_a <= coeff_a_raw;
      coeff_b <= coeff_b_raw;
      lane_valid_pipe[0] <= lane_valid;
      if (lane_valid_any) begin
        addr0_out_bank_pipe[0] <= addr0_out_bank;
        addr1_out_bank_pipe[0] <= addr1_out_bank;
        addr0_out_index_pipe[0] <= addr0_out_index;
        addr1_out_index_pipe[0] <= addr1_out_index;
      end

      for (pipe_stage_idx = 1; pipe_stage_idx <= TOTAL_PIPE_DEPTH; pipe_stage_idx = pipe_stage_idx + 1) begin
        addr0_out_bank_pipe[pipe_stage_idx] <= addr0_out_bank_pipe[pipe_stage_idx - 1];
        addr1_out_bank_pipe[pipe_stage_idx] <= addr1_out_bank_pipe[pipe_stage_idx - 1];
        addr0_out_index_pipe[pipe_stage_idx] <= addr0_out_index_pipe[pipe_stage_idx - 1];
        addr1_out_index_pipe[pipe_stage_idx] <= addr1_out_index_pipe[pipe_stage_idx - 1];
        lane_valid_pipe[pipe_stage_idx] <= lane_valid_pipe[pipe_stage_idx - 1];
      end
    end
  end

  genvar lane;
  generate
    for (lane = 0; lane < PARALLEL; lane = lane + 1) begin : gen_inv_butterflies
      ntt_butterfly #(
          .WIDTH         (WIDTH),
          .Q             (Q),
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .MULT_PIPELINE (MULT_PIPELINE)
      ) u_inv_butterfly (
          .clk    (clk),
          .rst_n  (rst_n),
          .a      (coeff_a[lane*WIDTH +: WIDTH]),
          .b      (coeff_b[lane*WIDTH +: WIDTH]),
          .twiddle(twiddle[lane*WIDTH +: WIDTH]),
          .a_out  (a_out[lane*WIDTH +: WIDTH]),
          .b_out  (b_out[lane*WIDTH +: WIDTH])
      );
    end
  endgenerate

  mod_mult #(
      .WIDTH          (WIDTH),
      .Q              (Q),
      .REDUCTION_TYPE (REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) scale_mult (
      .clk   (clk),
      .rst_n (rst_n),
      .a     (coeff_read_data),
      .b     (scaling_factor),
      .result(scale_result)
  );

  assign busy = (state != IDLE) && (state != DONE_STATE);
  assign done = (state == DONE_STATE);
  assign read_data = coeff_read_data;

endmodule
