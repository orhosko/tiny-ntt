`timescale 1ns / 1ps

//==============================================================================
// NTT Forward Transform - Configurable Parallelism
//==============================================================================
// Implements radix-2 Cooley-Tukey NTT with PARALLEL butterflies per cycle.
//==============================================================================

module ntt_forward #(
    parameter int N              = 256,      // NTT size
    parameter int WIDTH          = 32,       // Data width
    parameter int Q              = 8380417,  // Modulus
    parameter int ADDR_WIDTH     = 8,        // log₂(N)
    parameter int REDUCTION_TYPE = 0,        // 0=Simple, 1=Barrett, 2=Montgomery
    parameter int PARALLEL       = 8,        // Butterflies per cycle
    parameter int MULT_PIPELINE  = 3
) (
    input logic clk,
    input logic rst_n,

    // Control interface
    input  logic start,  // Start NTT computation
    output logic done,   // Computation complete
    output logic busy,   // Currently computing

    // Load interface (write coefficients before computation)
    input logic                  load_coeff,  // Load coefficient enable
    input logic [ADDR_WIDTH-1:0] load_addr,   // Load address
    input logic [     WIDTH-1:0] load_data,   // Load data

    // Read interface (read results after computation)
    input  logic [ADDR_WIDTH-1:0] read_addr,  // Read address
    output logic [     WIDTH-1:0] read_data   // Read data
);

  localparam int LOGN = $clog2(N);
  localparam int TOTAL_BUTTERFLIES = N / 2;
  localparam int TWIDDLE_WIDTH = 24;

  // Banked coefficient storage
  localparam int BANKS = PARALLEL * 3;
  localparam int BANK_DEPTH = (N + BANKS - 1) / BANKS;
  localparam int BANK_ADDR_WIDTH = $clog2(BANKS);
  localparam int BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH);

  logic [WIDTH-1:0] mem_bank[0:BANKS-1][0:BANK_DEPTH-1];

  // Control signals
  logic [LOGN-1:0] stage;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  logic [PARALLEL-1:0] lane_valid;
  logic ctrl_done;
  logic ctrl_busy;
  logic ctrl_done_latched;

  // Address generation
  logic [ADDR_WIDTH-1:0] half_block;
  logic [ADDR_WIDTH-1:0] block_size;
  logic [ADDR_WIDTH-1:0] twiddle_input;

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

  // Butterfly signals
  logic [PARALLEL-1:0][WIDTH-1:0] a_in;
  logic [PARALLEL-1:0][WIDTH-1:0] b_in;
  logic [PARALLEL-1:0][WIDTH-1:0] a_out;
  logic [PARALLEL-1:0][WIDTH-1:0] b_out;
  logic [PARALLEL-1:0][TWIDDLE_WIDTH-1:0] twiddle_raw;
  logic [PARALLEL-1:0][WIDTH-1:0] twiddle;


  // Read interface (synchronous)
  always_ff @(posedge clk) begin
    read_data <= mem_bank[bank_sel(read_addr)][bank_index(read_addr)];
  end

  // Control FSM (parallel scheduling)
  ntt_control_parallel #(
      .N        (N),
      .PARALLEL (PARALLEL)
  ) u_control (
      .clk        (clk),
      .rst_n      (rst_n),
      .start      (start),
      .done       (ctrl_done),
      .busy       (ctrl_busy),
      .stage      (stage),
      .butterfly  (butterfly_base),
      .cycle      (cycle),
      .lane_valid (lane_valid)
  );

  // Address generation for each lane
  always_comb begin
    half_block = ADDR_WIDTH'(N >> (stage + 1));
    block_size = ADDR_WIDTH'(N >> stage);

    for (int lane = 0; lane < PARALLEL; lane++) begin
      int unsigned butterfly_idx;
      int unsigned group;
      int unsigned position;

      butterfly_idx = butterfly_base + lane;

      if (lane_valid[lane]) begin
        group = butterfly_idx >> (LOGN - stage - 1);
        position = butterfly_idx & (half_block - 1);

        addr0[lane] = ADDR_WIDTH'(group * block_size + position);
        addr1[lane] = addr0[lane] + half_block;

        addr0_bank[lane] = bank_sel(addr0[lane]);
        addr1_bank[lane] = bank_sel(addr1[lane]);
        addr0_index[lane] = bank_index(addr0[lane]);
        addr1_index[lane] = bank_index(addr1[lane]);

        twiddle_input = ADDR_WIDTH'(1 << stage) + group;
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
      twiddle[lane] = {{(WIDTH-TWIDDLE_WIDTH){1'b0}}, twiddle_raw[lane]};
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

  logic pipe_active;
  assign pipe_active = |lane_valid_pipe[MULT_PIPELINE];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_done_latched <= 1'b0;
    end else begin
      if (ctrl_done) begin
        ctrl_done_latched <= 1'b1;
      end else if (ctrl_done_latched && !pipe_active) begin
        ctrl_done_latched <= 1'b0;
      end
    end
  end

  assign busy = ctrl_busy || pipe_active || ctrl_done_latched;
  assign done = ctrl_done_latched && !pipe_active;

  // Butterfly instantiation
  genvar lane;
  generate
    for (lane = 0; lane < PARALLEL; lane++) begin : gen_butterflies
      twiddle_rom u_twiddle_rom (
          .addr   (twiddle_addr[lane]),
          .twiddle(twiddle_raw[lane])
      );

      ntt_butterfly #(
          .WIDTH         (WIDTH),
          .Q             (Q),
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .MULT_PIPELINE (MULT_PIPELINE)
      ) u_butterfly (
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

  // Write-back results / load coefficients
  always_ff @(posedge clk) begin
    if (load_coeff && !busy) begin
      mem_bank[bank_sel(load_addr)][bank_index(load_addr)] <= load_data;
    end else if (busy) begin
      for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
        if (lane_valid_pipe[MULT_PIPELINE][lane_idx]) begin
          mem_bank[addr0_bank_pipe[MULT_PIPELINE][lane_idx]]
              [addr0_index_pipe[MULT_PIPELINE][lane_idx]] <= a_out[lane_idx];
          mem_bank[addr1_bank_pipe[MULT_PIPELINE][lane_idx]]
              [addr1_index_pipe[MULT_PIPELINE][lane_idx]] <= b_out[lane_idx];
        end
      end
    end
  end

endmodule
