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
    parameter int PSI            = 1239911, // Primitive 2N-th root of unity
    parameter int ADDR_WIDTH     = $clog2(N),        // log₂(N)
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

  // Banked coefficient storage
  localparam int BANKS = (N < (PARALLEL * 2)) ? N : (PARALLEL * 2);
  localparam int BANK_DEPTH = (N + BANKS - 1) / BANKS;
  localparam int BANK_ADDR_WIDTH = $clog2(BANKS);
  localparam int BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH);

  logic [WIDTH-1:0] mem_bank_a[0:BANKS-1][0:BANK_DEPTH-1];
  logic [WIDTH-1:0] mem_bank_b[0:BANKS-1][0:BANK_DEPTH-1];

  // Control signals
  logic [LOGN-1:0] stage;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  logic [PARALLEL-1:0] lane_valid;
  logic ctrl_done;
  logic ctrl_busy;
  logic ctrl_done_latched;

  // Address generation

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
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0_out;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1_out;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index;

  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0] lane_valid_pipe[0:MULT_PIPELINE];
  logic read_bank_sel;
  logic write_bank_sel;
  logic write_bank_sel_pipe[0:MULT_PIPELINE];
  localparam int OUTPUT_BANK = (LOGN % 2 == 0) ? 0 : 1;

  // Butterfly signals
  logic [PARALLEL-1:0][WIDTH-1:0] a_in;
  logic [PARALLEL-1:0][WIDTH-1:0] b_in;
  logic [PARALLEL-1:0][WIDTH-1:0] a_out;
  logic [PARALLEL-1:0][WIDTH-1:0] b_out;
  logic [PARALLEL-1:0][WIDTH-1:0] twiddle;

  localparam int TWIDDLE_DEPTH = N;
  localparam int MULT_LATENCY = (MULT_PIPELINE == 0) ? 1 : (MULT_PIPELINE + 1);

  logic [WIDTH-1:0] twiddle_table[0:TWIDDLE_DEPTH-1];

  typedef enum logic [1:0] {
    TW_IDLE = 2'b00,
    TW_TABLE = 2'b01,
    TW_READY = 2'b10
  } tw_state_t;

  tw_state_t tw_state;
  logic tw_ready;
  logic [ADDR_WIDTH-1:0] tw_index;
  logic [WIDTH-1:0] tw_mul_a;
  logic [WIDTH-1:0] tw_mul_b;
  logic [WIDTH-1:0] tw_mul_result;
  logic [ADDR_WIDTH-1:0] tw_mul_count;
  logic tw_mul_start;
  logic tw_mul_done;
  logic twiddle_stall;


  // Read interface (synchronous)
  always_ff @(posedge clk) begin
    if (OUTPUT_BANK == 0) begin
      read_data <= mem_bank_a[bank_sel(read_addr)][bank_index(read_addr)];
    end else begin
      read_data <= mem_bank_b[bank_sel(read_addr)][bank_index(read_addr)];
    end
  end

  // Control FSM (parallel scheduling)
  ntt_control_parallel #(
      .N        (N),
      .PARALLEL (PARALLEL)
  ) u_control (
      .clk        (clk),
      .rst_n      (rst_n),
      .start      (start),
      .stall      (twiddle_stall),
      .done       (ctrl_done),
      .busy       (ctrl_busy),
      .stage      (stage),
      .butterfly  (butterfly_base),
      .cycle      (cycle),
      .lane_valid (lane_valid)
  );

  assign read_bank_sel = stage[0];
  assign write_bank_sel = ~stage[0];

  mod_mult #(
      .WIDTH         (WIDTH),
      .Q             (Q),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PIPELINE_STAGES(MULT_PIPELINE)
  ) u_twiddle_mult (
      .clk   (clk),
      .rst_n (rst_n),
      .a     (tw_mul_a),
      .b     (tw_mul_b),
      .result(tw_mul_result)
  );

  assign twiddle_stall = !tw_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tw_mul_count <= '0;
    end else if (tw_mul_start) begin
      tw_mul_count <= MULT_LATENCY[ADDR_WIDTH-1:0];
    end else if (tw_mul_count != 0) begin
      tw_mul_count <= tw_mul_count - 1'b1;
    end
  end

  assign tw_mul_done = (tw_mul_count == 1);

  generate
    for (genvar i = 0; i < TWIDDLE_DEPTH; i++) begin : gen_twiddle_table
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          if (i == 0) begin
            twiddle_table[i] <= {{(WIDTH-1){1'b0}}, 1'b1};
          end else begin
            twiddle_table[i] <= '0;
          end
        end else if (!tw_ready) begin
          if (tw_state == TW_IDLE) begin
            if (i == 0) begin
              twiddle_table[i] <= {{(WIDTH-1){1'b0}}, 1'b1};
            end
          end else if (tw_state == TW_TABLE && tw_mul_done && tw_index == ADDR_WIDTH'(i)) begin
            twiddle_table[i] <= tw_mul_result;
          end
        end
      end
    end
  endgenerate

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tw_state <= TW_IDLE;
      tw_ready <= 1'b0;
      tw_index <= '0;
      tw_mul_start <= 1'b0;
      tw_mul_a <= '0;
      tw_mul_b <= '0;
    end else begin
      tw_mul_start <= 1'b0;
      if (!tw_ready) begin
        if (tw_state == TW_IDLE) begin
          if (TWIDDLE_DEPTH == 1) begin
            tw_state <= TW_READY;
            tw_ready <= 1'b1;
          end else begin
            tw_state <= TW_TABLE;
            tw_index <= 1;
            tw_mul_a <= {{(WIDTH-1){1'b0}}, 1'b1};
            tw_mul_b <= WIDTH'(PSI);
            tw_mul_start <= 1'b1;
          end
        end else if (tw_state == TW_TABLE) begin
          if (tw_mul_done) begin
            if (tw_index == (TWIDDLE_DEPTH - 1)) begin
              tw_state <= TW_READY;
              tw_ready <= 1'b1;
            end else begin
              tw_index <= tw_index + 1'b1;
              tw_mul_a <= tw_mul_result;
              tw_mul_b <= WIDTH'(PSI);
              tw_mul_start <= 1'b1;
            end
          end
        end
      end
    end
  end

  // Address generation for each lane
  always_comb begin
    int unsigned half_block_int;
    int unsigned block_size_int;

    half_block_int = N >> (stage + 1);
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

  // Combinational reads
  always_comb begin
    for (int lane = 0; lane < PARALLEL; lane++) begin
      if (read_bank_sel) begin
        a_in[lane] = mem_bank_b[addr0_bank[lane]][addr0_index[lane]];
        b_in[lane] = mem_bank_b[addr1_bank[lane]][addr1_index[lane]];
      end else begin
        a_in[lane] = mem_bank_a[addr0_bank[lane]][addr0_index[lane]];
        b_in[lane] = mem_bank_a[addr1_bank[lane]][addr1_index[lane]];
      end
      twiddle[lane] = twiddle_table[twiddle_addr[lane]];
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
          addr0_out_bank_pipe[stage_idx][lane_idx] <= '0;
          addr1_out_bank_pipe[stage_idx][lane_idx] <= '0;
          addr0_out_index_pipe[stage_idx][lane_idx] <= '0;
          addr1_out_index_pipe[stage_idx][lane_idx] <= '0;
          lane_valid_pipe[stage_idx][lane_idx] <= 1'b0;
          write_bank_sel_pipe[stage_idx] <= 1'b0;
        end
      end
    end else begin
      addr0_bank_pipe[0] <= addr0_bank;
      addr1_bank_pipe[0] <= addr1_bank;
      addr0_index_pipe[0] <= addr0_index;
      addr1_index_pipe[0] <= addr1_index;
      addr0_out_bank_pipe[0] <= addr0_out_bank;
      addr1_out_bank_pipe[0] <= addr1_out_bank;
      addr0_out_index_pipe[0] <= addr0_out_index;
      addr1_out_index_pipe[0] <= addr1_out_index;
      lane_valid_pipe[0] <= lane_valid;
      write_bank_sel_pipe[0] <= write_bank_sel;
      for (int stage_idx = 1; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        addr0_bank_pipe[stage_idx] <= addr0_bank_pipe[stage_idx - 1];
        addr1_bank_pipe[stage_idx] <= addr1_bank_pipe[stage_idx - 1];
        addr0_index_pipe[stage_idx] <= addr0_index_pipe[stage_idx - 1];
        addr1_index_pipe[stage_idx] <= addr1_index_pipe[stage_idx - 1];
        addr0_out_bank_pipe[stage_idx] <= addr0_out_bank_pipe[stage_idx - 1];
        addr1_out_bank_pipe[stage_idx] <= addr1_out_bank_pipe[stage_idx - 1];
        addr0_out_index_pipe[stage_idx] <= addr0_out_index_pipe[stage_idx - 1];
        addr1_out_index_pipe[stage_idx] <= addr1_out_index_pipe[stage_idx - 1];
        lane_valid_pipe[stage_idx] <= lane_valid_pipe[stage_idx - 1];
        write_bank_sel_pipe[stage_idx] <= write_bank_sel_pipe[stage_idx - 1];
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
      mem_bank_a[bank_sel(bit_reverse(load_addr))][bank_index(bit_reverse(load_addr))] <= load_data;
    end else if (busy) begin
      for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
        if (lane_valid_pipe[MULT_PIPELINE][lane_idx]) begin
          if (write_bank_sel_pipe[MULT_PIPELINE]) begin
            mem_bank_b[addr0_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr0_out_index_pipe[MULT_PIPELINE][lane_idx]] <= a_out[lane_idx];
            mem_bank_b[addr1_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr1_out_index_pipe[MULT_PIPELINE][lane_idx]] <= b_out[lane_idx];
          end else begin
            mem_bank_a[addr0_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr0_out_index_pipe[MULT_PIPELINE][lane_idx]] <= a_out[lane_idx];
            mem_bank_a[addr1_out_bank_pipe[MULT_PIPELINE][lane_idx]]
                [addr1_out_index_pipe[MULT_PIPELINE][lane_idx]] <= b_out[lane_idx];
          end
        end
      end
    end
  end

endmodule
