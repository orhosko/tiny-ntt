`timescale 1ns / 1ps

//==============================================================================
// NTT Forward Transform - Configurable Parallelism
//==============================================================================
// Implements radix-2 Cooley-Tukey NTT with PARALLEL butterflies per cycle.
// Constant-Geometry (bit-reversed input, CT butterflies).
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
  localparam int OUTPUT_BANK = (LOGN % 2 == 0) ? 0 : 1;

  logic [WIDTH-1:0] mem_bank_a[0:BANKS-1][0:BANK_DEPTH-1];
  logic [WIDTH-1:0] mem_bank_b[0:BANKS-1][0:BANK_DEPTH-1];

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

  // Control signals
  logic [LOGN-1:0] stage;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  logic [PARALLEL-1:0] lane_valid;
  logic ctrl_done;
  logic ctrl_busy;
  logic ctrl_done_latched;

  // Address generation
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] twiddle_addr;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr0_out;
  logic [PARALLEL-1:0][ADDR_WIDTH-1:0] addr1_out;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_bank;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_bank;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_index;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_index;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank;
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index;
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index;

  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe[0:MULT_PIPELINE];
  logic [PARALLEL-1:0] lane_valid_pipe[0:MULT_PIPELINE];

  // Butterfly signals
  logic [PARALLEL-1:0][WIDTH-1:0] a_in;
  logic [PARALLEL-1:0][WIDTH-1:0] b_in;
  logic [PARALLEL-1:0][WIDTH-1:0] a_out;
  logic [PARALLEL-1:0][WIDTH-1:0] b_out;
  logic [PARALLEL-1:0][WIDTH-1:0] twiddle;

  localparam int TWIDDLE_DEPTH = N;
  localparam longint PSI_SQR = longint'(PSI) * longint'(PSI);
  localparam int OMEGA = int'(PSI_SQR % Q);
  localparam int TWIDDLE_BASE = PSI;
  logic [TWIDDLE_DEPTH*WIDTH-1:0] twiddle_flat;
  logic [WIDTH-1:0] twiddle_table[0:TWIDDLE_DEPTH-1];
  logic tw_ready;
  logic twiddle_stall;
  localparam int CYCLES_PER_STAGE = (TOTAL_BUTTERFLIES + PARALLEL - 1) / PARALLEL;

  logic read_bank_sel;
  logic write_bank_sel;
  logic [MULT_PIPELINE:0] write_bank_sel_pipe;  // Packed array
  logic pipe_active;

  // Stage flush is now handled inside the control FSM with STAGE_DRAIN state.
  // The FSM waits for PIPELINE_DEPTH cycles after each stage before advancing,
  // allowing the butterfly pipeline to drain and writes to complete.

  // Control FSM (parallel scheduling)
  logic ctrl_draining;
  
  ntt_control_parallel #(
      .N             (N),
      .PARALLEL      (PARALLEL),
      .PIPELINE_DEPTH(MULT_PIPELINE + 1)  // +1 for output register stage
  ) u_control (
      .clk        (clk),
      .rst_n      (rst_n),
      .start      (start),
      .stall      (twiddle_stall),
      .done       (ctrl_done),
      .busy       (ctrl_busy),
      .draining   (ctrl_draining),
      .stage      (stage),
      .butterfly  (butterfly_base),
      .cycle      (cycle),
      .lane_valid (lane_valid)
  );

  // Twiddle table generation
  ntt_twiddle_table #(
      .WIDTH         (WIDTH),
      .Q             (Q),
      .PSI           (TWIDDLE_BASE),
      .ADDR_WIDTH    (ADDR_WIDTH),
      .TWIDDLE_DEPTH (TWIDDLE_DEPTH),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .MULT_PIPELINE (MULT_PIPELINE)
  ) u_twiddle_table (
      .clk         (clk),
      .rst_n       (rst_n),
      .tw_ready    (tw_ready),
      .twiddle_flat(twiddle_flat)
  );

  // Only stall for twiddle table generation - stage drain is in the FSM
  assign twiddle_stall = !tw_ready;

  // Constant-geometry address generation
  ntt_cg_address_gen #(
      .N               (N),
      .ADDR_WIDTH      (ADDR_WIDTH),
      .PARALLEL        (PARALLEL),
      .BANKS           (BANKS),
      .BANK_ADDR_WIDTH (BANK_ADDR_WIDTH),
      .BANK_DEPTH_WIDTH(BANK_DEPTH_WIDTH)
  ) u_addr_gen (
      .stage           (stage),
      .butterfly_base  (butterfly_base),
      .lane_valid      (lane_valid),
      .addr0           (addr0),
      .addr1           (addr1),
      .addr0_out       (addr0_out),
      .addr1_out       (addr1_out),
      .twiddle_addr    (twiddle_addr),
      .addr0_bank      (addr0_bank),
      .addr1_bank      (addr1_bank),
      .addr0_index     (addr0_index),
      .addr1_index     (addr1_index),
      .addr0_out_bank  (addr0_out_bank),
      .addr1_out_bank  (addr1_out_bank),
      .addr0_out_index (addr0_out_index),
      .addr1_out_index (addr1_out_index)
  );

  // Unpack twiddle table
  always_comb begin
    for (int idx = 0; idx < TWIDDLE_DEPTH; idx++) begin
      twiddle_table[idx] = twiddle_flat[idx * WIDTH +: WIDTH];
    end
  end

  // Map twiddle table to lanes
  always_comb begin
    for (int lane = 0; lane < PARALLEL; lane++) begin
      twiddle[lane] = twiddle_table[twiddle_addr[lane]];
    end
  end

  // Pipeline address/valid alignment for mult latency
  // NOTE: Only capture addresses when lane_valid_any is high to prevent
  // capturing garbage addresses during stage flush (when lane_valid becomes 0
  // combinationally but butterflies from the previous cycle are still valid)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int stage_idx = 0; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        for (int lane_idx = 0; lane_idx < PARALLEL; lane_idx++) begin
          addr0_out_bank_pipe[stage_idx][lane_idx] <= '0;
          addr1_out_bank_pipe[stage_idx][lane_idx] <= '0;
          addr0_out_index_pipe[stage_idx][lane_idx] <= '0;
          addr1_out_index_pipe[stage_idx][lane_idx] <= '0;
          lane_valid_pipe[stage_idx][lane_idx] <= 1'b0;
        end
      end
    end else begin
      // Always capture lane_valid to track pipeline state
      lane_valid_pipe[0] <= lane_valid;
      
      // Only capture addresses when there are valid butterflies being issued
      // This prevents capturing 0s during stage flush
      if (|lane_valid) begin
        addr0_out_bank_pipe[0] <= addr0_out_bank;
        addr1_out_bank_pipe[0] <= addr1_out_bank;
        addr0_out_index_pipe[0] <= addr0_out_index;
        addr1_out_index_pipe[0] <= addr1_out_index;
      end
      
      // Always shift the pipeline to maintain synchronization
      for (int stage_idx = 1; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        addr0_out_bank_pipe[stage_idx] <= addr0_out_bank_pipe[stage_idx - 1];
        addr1_out_bank_pipe[stage_idx] <= addr1_out_bank_pipe[stage_idx - 1];
        addr0_out_index_pipe[stage_idx] <= addr0_out_index_pipe[stage_idx - 1];
        addr1_out_index_pipe[stage_idx] <= addr1_out_index_pipe[stage_idx - 1];
        lane_valid_pipe[stage_idx] <= lane_valid_pipe[stage_idx - 1];
      end
    end
  end

  // Bank switch pipeline
  logic lane_valid_any;
  assign lane_valid_any = |lane_valid;

  ntt_bank_switch #(
      .LOGN         (LOGN),
      .PARALLEL     (PARALLEL),
      .MULT_PIPELINE(MULT_PIPELINE)
  ) u_bank_switch (
      .clk                 (clk),
      .rst_n               (rst_n),
      .stage               (stage),
      .lane_valid_any      (lane_valid_any),
      .lane_valid_pipe     (lane_valid_pipe),
      .read_bank_sel       (read_bank_sel),
      .write_bank_sel      (write_bank_sel),
      .write_bank_sel_pipe (write_bank_sel_pipe),
      .pipe_active         (pipe_active)
  );

  // Read interface (synchronous)
  always_ff @(posedge clk) begin
    if (OUTPUT_BANK == 0) begin
      read_data <= mem_bank_a[bank_sel(read_addr)][bank_index(read_addr)];
    end else begin
      read_data <= mem_bank_b[bank_sel(read_addr)][bank_index(read_addr)];
    end
  end

  // Combinational reads for butterflies
  always_comb begin
    for (int lane = 0; lane < PARALLEL; lane++) begin
      if (read_bank_sel) begin
        a_in[lane] = mem_bank_b[addr0_bank[lane]][addr0_index[lane]];
        b_in[lane] = mem_bank_b[addr1_bank[lane]][addr1_index[lane]];
      end else begin
        a_in[lane] = mem_bank_a[addr0_bank[lane]][addr0_index[lane]];
        b_in[lane] = mem_bank_a[addr1_bank[lane]][addr1_index[lane]];
      end
    end
  end

  // Write-back results / load coefficients
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int bank = 0; bank < BANKS; bank++) begin
        for (int idx = 0; idx < BANK_DEPTH; idx++) begin
          mem_bank_a[bank][idx] <= '0;
          mem_bank_b[bank][idx] <= '0;
        end
      end
    end else if (load_coeff && !busy) begin
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

  // Done/busy handling
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

endmodule
