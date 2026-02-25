`timescale 1ns / 1ps

//==============================================================================
// Inverse NTT Module
//==============================================================================
// Complete N=256 inverse radix-2 Cooley-Tukey NTT pipeline
//
// Performs INTT with final scaling by N^(-1) = 8347681
//
// Flow:
//   1. Load NTT-transformed coefficients
//   2. Run inverse NTT (4096 cycles)
//   3. Scale by N^(-1) (256 cycles)
//   4. Read results
//
// Total: ~4352 cycles
//==============================================================================

module ntt_inverse #(
    parameter int N              = 256,   // NTT size
    parameter int WIDTH          = 32,    // Data width
    parameter int Q              = 8380417,  // Modulus
    parameter int ADDR_WIDTH     = 8,        // log₂(N)
    parameter int REDUCTION_TYPE = 0,        // 0=Simple, 1=Barrett, 2=Montgomery
    parameter int N_INV          = 8347681,  // N^(-1) mod Q = 256^(-1) mod 8380417
    parameter int PARALLEL       = 8,        // Butterflies per cycle
    parameter int MULT_PIPELINE  = 3
) (
    input logic clk,
    input logic rst_n,

    // Control interface
    input  logic start,  // Start INTT computation
    output logic done,   // Computation complete
    output logic busy,   // Currently computing

    // Load interface (write NTT coefficients before computation)
    input logic                  load_coeff,  // Load coefficient enable
    input logic [ADDR_WIDTH-1:0] load_addr,   // Load address
    input logic [     WIDTH-1:0] load_data,   // Load data

    // Read interface (read results after computation)
    input  logic [ADDR_WIDTH-1:0] read_addr,  // Read address
    output logic [     WIDTH-1:0] read_data   // Read data
);

  //============================================================================
  // Internal Signals
  //============================================================================

  // INTT computation state
  typedef enum logic [1:0] {
    IDLE = 2'b00,
    INTT_COMPUTE = 2'b01,
    SCALE = 2'b10,
    DONE_STATE = 2'b11
  } state_t;

  state_t state, next_state;

  localparam int LOGN = $clog2(N);
  localparam int TOTAL_BUTTERFLIES = N / 2;

  // Control FSM signals (for INTT)
  logic intt_start, intt_done, intt_busy;
  logic intt_done_latched;
  logic [LOGN-1:0] stage;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  logic [PARALLEL-1:0] lane_valid;

  // Banked coefficient storage
  localparam int BANKS = PARALLEL * 3;
  localparam int BANK_DEPTH = (N + BANKS - 1) / BANKS;
  localparam int BANK_ADDR_WIDTH = $clog2(BANKS);
  localparam int BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH);

  logic [WIDTH-1:0] mem_bank[0:BANKS-1][0:BANK_DEPTH-1];

  // Address generation
  logic [ADDR_WIDTH-1:0] half_block;
  logic [ADDR_WIDTH-1:0] block_size;
  logic [ADDR_WIDTH-1:0] twiddle_input;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] twiddle_addr;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_bank;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_bank;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_index;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_index;

  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0] lane_valid_pipe[0:MULT_PIPELINE];

  // Twiddle and butterfly signals
  logic [PARALLEL-1:0][WIDTH-1:0] twiddle_raw;
  logic [PARALLEL-1:0][WIDTH-1:0] a_in;
  logic [PARALLEL-1:0][WIDTH-1:0] b_in;
  logic [PARALLEL-1:0][WIDTH-1:0] a_out;
  logic [PARALLEL-1:0][WIDTH-1:0] b_out;

  // Scaling logic (needs 9 bits to reach N=256)
  localparam int SCALE_LATENCY = 0;
  logic [ADDR_WIDTH:0] scale_addr;  // 9 bits: 0-256
  logic [   WIDTH-1:0] scale_result;
  logic [ADDR_WIDTH:0] scale_addr_pipe[0:MULT_PIPELINE];
  logic [MULT_PIPELINE:0] scale_valid_pipe;


  //============================================================================
  // State Machine
  //============================================================================

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
        if (intt_done_latched && !lane_valid_pipe[MULT_PIPELINE]) begin
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

  // Outputs
  assign done = (state == DONE_STATE);
  assign busy = (state != IDLE) && (state != DONE_STATE);

  // Start INTT when entering INTT_COMPUTE state
  assign intt_start = (state == IDLE && start);

  // Latch INTT completion until pipeline drains
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      intt_done_latched <= 1'b0;
    end else if (state != INTT_COMPUTE) begin
      intt_done_latched <= 1'b0;
    end else begin
      if (intt_done) begin
        intt_done_latched <= 1'b1;
      end else if (intt_done_latched && !lane_valid_pipe[MULT_PIPELINE]) begin
        intt_done_latched <= 1'b0;
      end
    end
  end

  //============================================================================
  // Scaling Counter
  //============================================================================

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

  //============================================================================
  // Memory Interface
  //============================================================================

  function automatic [ADDR_WIDTH-1:0] bit_reverse(input logic [ADDR_WIDTH-1:0] value);
    automatic logic [ADDR_WIDTH-1:0] reversed;
    for (int i = 0; i < ADDR_WIDTH; i++) begin
      reversed[i] = value[ADDR_WIDTH - 1 - i];
    end
    return reversed;
  endfunction

  function automatic [BANK_ADDR_WIDTH-1:0] bank_sel(input logic [ADDR_WIDTH-1:0] addr);
    return addr % BANKS;
  endfunction

  function automatic [BANK_DEPTH_WIDTH-1:0] bank_index(input logic [ADDR_WIDTH-1:0] addr);
    return addr / BANKS;
  endfunction

  // Temporary variables for scaling address computation
  logic [ADDR_WIDTH-1:0] scale_read_addr;

  assign scale_read_addr = scale_addr[ADDR_WIDTH-1:0];


  // Read interface (synchronous)
  always_ff @(posedge clk) begin
    read_data <= mem_bank[bank_sel(read_addr)][bank_index(read_addr)];
  end

  // Address generation for each lane
  always_comb begin
    half_block = ADDR_WIDTH'(1 << stage);
    block_size = ADDR_WIDTH'(1 << (stage + 1));

    for (int lane = 0; lane < PARALLEL; lane++) begin
      int unsigned butterfly_idx;
      int unsigned group;
      int unsigned position;

      butterfly_idx = butterfly_base + lane;

      if (lane_valid[lane]) begin
        group = butterfly_idx >> stage;
        position = butterfly_idx & (half_block - 1);

        addr0[lane] = ADDR_WIDTH'(group * block_size + position);
        addr1[lane] = addr0[lane] + half_block;

        addr0_bank[lane] = bank_sel(addr0[lane]);
        addr1_bank[lane] = bank_sel(addr1[lane]);
        addr0_index[lane] = bank_index(addr0[lane]);
        addr1_index[lane] = bank_index(addr1[lane]);

        twiddle_input = ADDR_WIDTH'(1 << (LOGN - stage - 1)) + group;
        twiddle_addr[lane] = bit_reverse(twiddle_input);
      end else begin
        addr0[lane] = '0;
        addr1[lane] = '0;
        addr0_bank[lane] = '0;
        addr1_bank[lane] = '0;
        addr0_index[lane] = '0;
        addr1_index[lane] = '0;
        twiddle_addr[lane] = '0;
      end
    end
  end

  // Combinational reads
  always_comb begin
    for (int lane = 0; lane < PARALLEL; lane++) begin
      a_in[lane] = mem_bank[addr0_bank[lane]][addr0_index[lane]];
      b_in[lane] = mem_bank[addr1_bank[lane]][addr1_index[lane]];
    end
  end

  // Pipeline address/valid alignment for mult latency
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int stage_idx = 0; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
          addr0_bank_pipe[stage_idx][lane_idx] <= '0;
          addr1_bank_pipe[stage_idx][lane_idx] <= '0;
          addr0_index_pipe[stage_idx][lane_idx] <= '0;
          addr1_index_pipe[stage_idx][lane_idx] <= '0;
          lane_valid_pipe[stage_idx][lane_idx] <= 1'b0;
        end
      end
    end else begin
      addr0_bank_pipe[0] <= addr0_bank;
      addr1_bank_pipe[0] <= addr1_bank;
      addr0_index_pipe[0] <= addr0_index;
      addr1_index_pipe[0] <= addr1_index;
      lane_valid_pipe[0] <= lane_valid;
      for (int stage_idx = 1; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        addr0_bank_pipe[stage_idx] <= addr0_bank_pipe[stage_idx - 1];
        addr1_bank_pipe[stage_idx] <= addr1_bank_pipe[stage_idx - 1];
        addr0_index_pipe[stage_idx] <= addr0_index_pipe[stage_idx - 1];
        addr1_index_pipe[stage_idx] <= addr1_index_pipe[stage_idx - 1];
        lane_valid_pipe[stage_idx] <= lane_valid_pipe[stage_idx - 1];
      end
    end
  end

  // Twiddle ROM + butterfly per lane
  genvar lane;
  generate
    for (lane = 0; lane < PARALLEL; lane++) begin : gen_inv_butterflies
      inverse_twiddle_rom u_inverse_twiddle_rom (
          .addr   (twiddle_addr[lane]),
          .twiddle(twiddle_raw[lane])
      );

      ntt_butterfly_inverse #(
          .WIDTH         (WIDTH),
          .Q             (Q),
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .MULT_PIPELINE (MULT_PIPELINE)
      ) u_inv_butterfly (
          .clk    (clk),
          .rst_n  (rst_n),
          .a      (a_in[lane]),
          .b      (b_in[lane]),
          .twiddle(twiddle_raw[lane]),
          .a_out  (a_out[lane]),
          .b_out  (b_out[lane])
      );
    end
  endgenerate

  // Write-back results / load coefficients
  always_ff @(posedge clk) begin
    if (load_coeff && state == IDLE) begin
      mem_bank[bank_sel(load_addr)][bank_index(load_addr)] <= load_data;
    end else if (state == INTT_COMPUTE) begin
      for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
        if (lane_valid_pipe[MULT_PIPELINE][lane_idx]) begin
          mem_bank[addr0_bank_pipe[MULT_PIPELINE][lane_idx]]
              [addr0_index_pipe[MULT_PIPELINE][lane_idx]] <= a_out[lane_idx];
          mem_bank[addr1_bank_pipe[MULT_PIPELINE][lane_idx]]
              [addr1_index_pipe[MULT_PIPELINE][lane_idx]] <= b_out[lane_idx];
        end
      end
    end else if (state == SCALE && scale_valid_pipe[MULT_PIPELINE]) begin
      mem_bank[bank_sel(scale_addr_pipe[MULT_PIPELINE][ADDR_WIDTH-1:0])]
          [bank_index(scale_addr_pipe[MULT_PIPELINE][ADDR_WIDTH-1:0])] <= scale_result;
    end
  end

  //============================================================================
  // Scaling Logic
  //============================================================================
  // Multiply each coefficient by N^(-1) = 8347681
  // Pipeline: Read (1 cycle) → Multiply (1 cycle) → Write (1 cycle)

  logic [WIDTH-1:0] scaling_factor;
  assign scaling_factor = N_INV;


  // Modular multiplication for scaling
  mod_mult #(
      .WIDTH         (WIDTH),
      .Q             (Q),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) scale_mult (
      .clk   (clk),
      .rst_n (rst_n),
      .a     (mem_bank[bank_sel(scale_read_addr)][bank_index(scale_read_addr)]),
      .b     (scaling_factor),
      .result(scale_result)
  );

  // Control FSM (parallel scheduling)
  ntt_control_parallel #(
      .N        (N),
      .PARALLEL (PARALLEL)
  ) u_control (
      .clk        (clk),
      .rst_n      (rst_n),
      .start      (intt_start),
      .done       (intt_done),
      .busy       (intt_busy),
      .stage      (stage),
      .butterfly  (butterfly_base),
      .cycle      (cycle),
      .lane_valid (lane_valid)
  );

endmodule
