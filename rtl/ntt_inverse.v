`timescale 1ns / 1ps

//==============================================================================
// Inverse NTT Module
//==============================================================================
// Complete N=1024 inverse radix-2 Cooley-Tukey NTT pipeline
//
// Performs INTT with final scaling by N^(-1) = 8347681
//
// Flow:
//   1. Load NTT-transformed coefficients
//   2. Run inverse NTT
//   3. Scale by N^(-1)
//   4. Read results
//
// Twiddle factors are stored in BRAM for efficient resource usage.
//==============================================================================

module ntt_inverse #(
    parameter int N              = 1024,
    parameter int WIDTH          = 32,
    parameter int Q              = 8380417,
    parameter int PSI_INV        = 2320879,
    parameter int ADDR_WIDTH     = $clog2(N),
    parameter int REDUCTION_TYPE = 0,
    parameter int N_INV          = 8372233,
    parameter int PARALLEL       = 8,
    parameter int MULT_PIPELINE  = 3,
    parameter     TWIDDLE_FILE   = "twiddle_inverse_1024.hex"
) (
    input logic clk,
    input logic rst_n,

    // Control interface
    input  logic start,
    output logic done,
    output logic busy,

    // Load interface
    input logic                  load_coeff,
    input logic [ADDR_WIDTH-1:0] load_addr,
    input logic [WIDTH-1:0]      load_data,

    // Read interface
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [WIDTH-1:0]      read_data
);

  typedef enum logic [1:0] {
    IDLE = 2'b00,
    INTT_COMPUTE = 2'b01,
    SCALE = 2'b10,
    DONE_STATE = 2'b11
  } state_t;

  state_t state, next_state;

  localparam int LOGN = $clog2(N);
  localparam int TOTAL_BUTTERFLIES = N / 2;

  logic intt_start, intt_done, intt_busy;
  logic intt_done_latched;
  logic [LOGN-1:0] stage;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  logic [PARALLEL-1:0] lane_valid;
  logic ctrl_draining;

  localparam int BANKS = (N < (PARALLEL * 2)) ? N : (PARALLEL * 2);
  localparam int BANK_DEPTH = (N + BANKS - 1) / BANKS;
  localparam int BANK_ADDR_WIDTH = $clog2(BANKS);
  localparam int BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH);

  logic [WIDTH-1:0] mem_bank_a[0:BANKS-1][0:BANK_DEPTH-1];
  logic [WIDTH-1:0] mem_bank_b[0:BANKS-1][0:BANK_DEPTH-1];

  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] twiddle_addr;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_bank;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_bank;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_index;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_index;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0_out;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1_out;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index;

  localparam int BRAM_LATENCY = 1;
  localparam int TOTAL_PIPE_DEPTH = MULT_PIPELINE + BRAM_LATENCY;

  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0] lane_valid_pipe[0:TOTAL_PIPE_DEPTH];
  logic read_bank_sel;
  logic write_bank_sel;
  logic [TOTAL_PIPE_DEPTH:0] write_bank_sel_pipe;
  localparam int OUTPUT_BANK = (LOGN % 2 == 0) ? 0 : 1;

  logic [PARALLEL-1:0][WIDTH-1:0] a_in_comb;
  logic [PARALLEL-1:0][WIDTH-1:0] b_in_comb;
  logic [PARALLEL-1:0][WIDTH-1:0] a_in;
  logic [PARALLEL-1:0][WIDTH-1:0] b_in;
  logic [PARALLEL-1:0][WIDTH-1:0] twiddle;
  logic [PARALLEL-1:0][WIDTH-1:0] a_out;
  logic [PARALLEL-1:0][WIDTH-1:0] b_out;

  logic [ADDR_WIDTH:0] scale_addr;
  logic [WIDTH-1:0] scale_result;
  logic [ADDR_WIDTH:0] scale_addr_pipe[0:MULT_PIPELINE];
  logic [MULT_PIPELINE:0] scale_valid_pipe;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else state <= next_state;
  end

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start) next_state = INTT_COMPUTE;
      end

      INTT_COMPUTE: begin
        if (intt_done_latched && !lane_valid_pipe[TOTAL_PIPE_DEPTH]) begin
          next_state = SCALE;
        end
      end

      SCALE: begin
        if (scale_addr >= N && !scale_valid_pipe[MULT_PIPELINE]) begin
          next_state = DONE_STATE;
        end
      end

      DONE_STATE: begin
        if (!start) next_state = IDLE;
      end
    endcase
  end

  assign done = (state == DONE_STATE);
  assign busy = (state != IDLE) && (state != DONE_STATE);
  assign intt_start = (state == IDLE && start);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      intt_done_latched <= 1'b0;
    end else if (state != INTT_COMPUTE) begin
      intt_done_latched <= 1'b0;
    end else begin
      if (intt_done) begin
        intt_done_latched <= 1'b1;
      end else if (intt_done_latched && !lane_valid_pipe[TOTAL_PIPE_DEPTH]) begin
        intt_done_latched <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scale_addr <= '0;
      for (int stage_idx = 0; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        scale_addr_pipe[stage_idx] <= '0;
        scale_valid_pipe[stage_idx] <= 1'b0;
      end
    end else begin
      if (state == SCALE) begin
        if (scale_addr < N) begin
          scale_addr <= scale_addr + 1'b1;
        end
      end else begin
        scale_addr <= '0;
      end

      scale_addr_pipe[0] <= scale_addr;
      scale_valid_pipe[0] <= (state == SCALE) && (scale_addr < N);
      for (int stage_idx = 1; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        scale_addr_pipe[stage_idx] <= scale_addr_pipe[stage_idx - 1];
        scale_valid_pipe[stage_idx] <= scale_valid_pipe[stage_idx - 1];
      end
    end
  end

  function automatic [BANK_ADDR_WIDTH-1:0] bank_sel(input logic [ADDR_WIDTH-1:0] addr);
    return addr % BANKS;
  endfunction

  function automatic [ADDR_WIDTH-1:0] bit_reverse(input logic [ADDR_WIDTH-1:0] value);
    automatic logic [ADDR_WIDTH-1:0] reversed;
    for (int i = 0; i < ADDR_WIDTH; i++) begin
      reversed[i] = value[ADDR_WIDTH - 1 - i];
    end
    return reversed;
  endfunction

  function automatic [BANK_DEPTH_WIDTH-1:0] bank_index(input logic [ADDR_WIDTH-1:0] addr);
    return addr / BANKS;
  endfunction

  logic [ADDR_WIDTH-1:0] scale_read_addr;
  assign scale_read_addr = scale_addr[ADDR_WIDTH-1:0];

  always_ff @(posedge clk) begin
    if (OUTPUT_BANK == 0) begin
      read_data <= mem_bank_a[bank_sel(read_addr)][bank_index(read_addr)];
    end else begin
      read_data <= mem_bank_b[bank_sel(read_addr)][bank_index(read_addr)];
    end
  end

  assign read_bank_sel = stage[0];
  assign write_bank_sel = ~stage[0];

  always_comb begin
    int unsigned block_size_int;

    block_size_int = N >> stage;

    for (int lane = 0; lane < PARALLEL; lane++) begin
      int unsigned butterfly_idx;
      int unsigned group;
      int unsigned addr0_int;
      int unsigned addr1_int;
      int unsigned twiddle_exp;

      butterfly_idx = butterfly_base + lane;

      if (lane_valid[lane]) begin
        group = butterfly_idx >> (LOGN - stage - 1);

        addr0_int = 2 * butterfly_idx;
        addr1_int = addr0_int + 1;

        addr0[lane] = ADDR_WIDTH'(addr0_int);
        addr1[lane] = ADDR_WIDTH'(addr1_int);

        addr0_bank[lane] = bank_sel(addr0[lane]);
        addr1_bank[lane] = bank_sel(addr1[lane]);
        addr0_index[lane] = bank_index(addr0[lane]);
        addr1_index[lane] = bank_index(addr1[lane]);

        addr0_out[lane] = ADDR_WIDTH'(butterfly_idx);
        addr1_out[lane] = ADDR_WIDTH'(butterfly_idx + (N >> 1));
        addr0_out_bank[lane] = bank_sel(addr0_out[lane]);
        addr1_out_bank[lane] = bank_sel(addr1_out[lane]);
        addr0_out_index[lane] = bank_index(addr0_out[lane]);
        addr1_out_index[lane] = bank_index(addr1_out[lane]);

        twiddle_exp = block_size_int * group;
        twiddle_addr[lane] = ADDR_WIDTH'(twiddle_exp);
      end else begin
        addr0[lane] = '0;
        addr1[lane] = '0;
        addr0_bank[lane] = '0;
        addr1_bank[lane] = '0;
        addr0_index[lane] = '0;
        addr1_index[lane] = '0;
        addr0_out[lane] = '0;
        addr1_out[lane] = '0;
        addr0_out_bank[lane] = '0;
        addr1_out_bank[lane] = '0;
        addr0_out_index[lane] = '0;
        addr1_out_index[lane] = '0;
        twiddle_addr[lane] = '0;
      end
    end
  end

  twiddle_bram_multiport #(
      .DEPTH(N),
      .WIDTH(WIDTH),
      .PARALLEL(PARALLEL),
      .ADDR_WIDTH(ADDR_WIDTH),
      .HEX_FILE(TWIDDLE_FILE)
  ) u_twiddle_bram (
      .clk(clk),
      .addr(twiddle_addr),
      .data(twiddle)
  );

  always_comb begin
    for (int lane = 0; lane < PARALLEL; lane++) begin
      if (read_bank_sel) begin
        a_in_comb[lane] = mem_bank_b[addr0_bank[lane]][addr0_index[lane]];
        b_in_comb[lane] = mem_bank_b[addr1_bank[lane]][addr1_index[lane]];
      end else begin
        a_in_comb[lane] = mem_bank_a[addr0_bank[lane]][addr0_index[lane]];
        b_in_comb[lane] = mem_bank_a[addr1_bank[lane]][addr1_index[lane]];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int lane = 0; lane < PARALLEL; lane++) begin
        a_in[lane] <= '0;
        b_in[lane] <= '0;
      end
    end else begin
      a_in <= a_in_comb;
      b_in <= b_in_comb;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      write_bank_sel_pipe <= '0;
      for (int stage_idx = 0; stage_idx <= TOTAL_PIPE_DEPTH; stage_idx++) begin
        for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
          addr0_out_bank_pipe[stage_idx][lane_idx] <= '0;
          addr1_out_bank_pipe[stage_idx][lane_idx] <= '0;
          addr0_out_index_pipe[stage_idx][lane_idx] <= '0;
          addr1_out_index_pipe[stage_idx][lane_idx] <= '0;
          lane_valid_pipe[stage_idx][lane_idx] <= 1'b0;
        end
      end
    end else begin
      addr0_out_bank_pipe[0] <= addr0_out_bank;
      addr1_out_bank_pipe[0] <= addr1_out_bank;
      addr0_out_index_pipe[0] <= addr0_out_index;
      addr1_out_index_pipe[0] <= addr1_out_index;
      lane_valid_pipe[0] <= lane_valid;
      write_bank_sel_pipe[0] <= write_bank_sel;

      for (int stage_idx = 1; stage_idx <= TOTAL_PIPE_DEPTH; stage_idx++) begin
        addr0_out_bank_pipe[stage_idx] <= addr0_out_bank_pipe[stage_idx - 1];
        addr1_out_bank_pipe[stage_idx] <= addr1_out_bank_pipe[stage_idx - 1];
        addr0_out_index_pipe[stage_idx] <= addr0_out_index_pipe[stage_idx - 1];
        addr1_out_index_pipe[stage_idx] <= addr1_out_index_pipe[stage_idx - 1];
        lane_valid_pipe[stage_idx] <= lane_valid_pipe[stage_idx - 1];
      end
      write_bank_sel_pipe[TOTAL_PIPE_DEPTH:1] <= write_bank_sel_pipe[TOTAL_PIPE_DEPTH-1:0];
    end
  end

  generate
    for (genvar lane = 0; lane < PARALLEL; lane++) begin : gen_inv_butterflies
      ntt_butterfly #(
          .WIDTH         (WIDTH),
          .Q             (Q),
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .MULT_PIPELINE (MULT_PIPELINE)
      ) u_inv_butterfly (
          .clk    (clk),
          .rst_n  (rst_n),
          .a      (a_in[lane]),
          .b      (b_in[lane]),
          .twiddle(twiddle[lane]),
          .a_out  (a_out[lane]),
          .b_out  (b_out[lane])
      );
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (load_coeff && state == IDLE) begin
      mem_bank_a[bank_sel(bit_reverse(load_addr))][bank_index(bit_reverse(load_addr))] <= load_data;
    end else if (state == INTT_COMPUTE) begin
      for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
        if (lane_valid_pipe[TOTAL_PIPE_DEPTH][lane_idx]) begin
          if (write_bank_sel_pipe[TOTAL_PIPE_DEPTH]) begin
            mem_bank_b[addr0_out_bank_pipe[TOTAL_PIPE_DEPTH][lane_idx]]
                [addr0_out_index_pipe[TOTAL_PIPE_DEPTH][lane_idx]] <= a_out[lane_idx];
            mem_bank_b[addr1_out_bank_pipe[TOTAL_PIPE_DEPTH][lane_idx]]
                [addr1_out_index_pipe[TOTAL_PIPE_DEPTH][lane_idx]] <= b_out[lane_idx];
          end else begin
            mem_bank_a[addr0_out_bank_pipe[TOTAL_PIPE_DEPTH][lane_idx]]
                [addr0_out_index_pipe[TOTAL_PIPE_DEPTH][lane_idx]] <= a_out[lane_idx];
            mem_bank_a[addr1_out_bank_pipe[TOTAL_PIPE_DEPTH][lane_idx]]
                [addr1_out_index_pipe[TOTAL_PIPE_DEPTH][lane_idx]] <= b_out[lane_idx];
          end
        end
      end
    end else if (state == SCALE && scale_valid_pipe[MULT_PIPELINE]) begin
      if (OUTPUT_BANK == 0) begin
        mem_bank_a[bank_sel(scale_addr_pipe[MULT_PIPELINE][ADDR_WIDTH-1:0])]
            [bank_index(scale_addr_pipe[MULT_PIPELINE][ADDR_WIDTH-1:0])] <= scale_result;
      end else begin
        mem_bank_b[bank_sel(scale_addr_pipe[MULT_PIPELINE][ADDR_WIDTH-1:0])]
            [bank_index(scale_addr_pipe[MULT_PIPELINE][ADDR_WIDTH-1:0])] <= scale_result;
      end
    end
  end

  logic [WIDTH-1:0] scaling_factor;
  assign scaling_factor = N_INV;

  logic [WIDTH-1:0] scale_read_data;
  assign scale_read_data = (OUTPUT_BANK == 0)
                               ? mem_bank_a[bank_sel(scale_read_addr)][bank_index(scale_read_addr)]
                               : mem_bank_b[bank_sel(scale_read_addr)][bank_index(scale_read_addr)];

  mod_mult #(
      .WIDTH         (WIDTH),
      .Q             (Q),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) scale_mult (
      .clk   (clk),
      .rst_n (rst_n),
      .a     (scale_read_data),
      .b     (scaling_factor),
      .result(scale_result)
  );

  ntt_control_parallel #(
      .N             (N),
      .PARALLEL      (PARALLEL),
      .PIPELINE_DEPTH(TOTAL_PIPE_DEPTH + 1)
  ) u_control (
      .clk        (clk),
      .rst_n      (rst_n),
      .start      (intt_start),
      .stall      (1'b0),
      .done       (intt_done),
      .busy       (intt_busy),
      .draining   (ctrl_draining),
      .stage      (stage),
      .butterfly  (butterfly_base),
      .cycle      (cycle),
      .lane_valid (lane_valid)
  );

endmodule
