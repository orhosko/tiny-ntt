`timescale 1ns / 1ps

//==============================================================================
// NTT Forward Transform - Configurable Parallelism
//==============================================================================
// Implements radix-2 Cooley-Tukey NTT with PARALLEL butterflies per cycle.
// Constant-Geometry (bit-reversed input, CT butterflies).
//
// Twiddle factors are stored in BRAM for efficient resource usage.
// Coefficient storage is in a separate ntt_coeff_banks module.
//==============================================================================

module ntt_forward #(
    parameter int N              = 256,      // NTT size
    parameter int WIDTH          = 32,       // Data width
    parameter int Q              = 8380417,  // Modulus
    parameter int PSI            = 1239911,  // Primitive 2N-th root of unity (unused, twiddles precomputed)
    parameter int ADDR_WIDTH     = $clog2(N),        // log2(N)
    parameter int REDUCTION_TYPE = 0,        // 0=Simple, 1=Barrett, 2=Montgomery
    parameter int PARALLEL       = 8,        // Butterflies per cycle
    parameter int MULT_PIPELINE  = 3,
    parameter     TWIDDLE_FILE   = "twiddle_forward.hex"  // Hex file for twiddle BRAM
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

  // Banked coefficient storage parameters
  localparam int BANKS = (N < (PARALLEL * 2)) ? N : (PARALLEL * 2);
  localparam int BANK_DEPTH = (N + BANKS - 1) / BANKS;
  localparam int BANK_ADDR_WIDTH = $clog2(BANKS);
  localparam int BANK_DEPTH_WIDTH = $clog2(BANK_DEPTH);
  localparam int OUTPUT_BANK = (LOGN % 2 == 0) ? 0 : 1;

  // Pipeline depth: MULT_PIPELINE (butterfly) + 1 (BRAM read latency)
  localparam int BRAM_LATENCY = 1;
  localparam int TOTAL_PIPE_DEPTH = MULT_PIPELINE + BRAM_LATENCY;

  //============================================================================
  // Control Signals
  //============================================================================
  logic [LOGN-1:0] stage;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] butterfly_base;
  logic [$clog2(TOTAL_BUTTERFLIES)-1:0] cycle;
  logic [PARALLEL-1:0] lane_valid;
  logic ctrl_done;
  logic ctrl_busy;
  logic ctrl_done_latched;
  logic ctrl_draining;

  //============================================================================
  // Address Generation Signals
  //============================================================================
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

  //============================================================================
  // Pipeline Registers for Write-back Alignment
  //============================================================================
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr0_out_bank_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0][BANK_ADDR_WIDTH-1:0] addr1_out_bank_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr0_out_index_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0][BANK_DEPTH_WIDTH-1:0] addr1_out_index_pipe[0:TOTAL_PIPE_DEPTH];
  logic [PARALLEL-1:0] lane_valid_pipe[0:TOTAL_PIPE_DEPTH];

  //============================================================================
  // Butterfly Signals
  //============================================================================
  logic [PARALLEL-1:0][WIDTH-1:0] coeff_a_comb;  // From coefficient banks (combinational)
  logic [PARALLEL-1:0][WIDTH-1:0] coeff_b_comb;  // From coefficient banks (combinational)
  logic [PARALLEL-1:0][WIDTH-1:0] a_in;          // Registered to match BRAM twiddle latency
  logic [PARALLEL-1:0][WIDTH-1:0] b_in;          // Registered to match BRAM twiddle latency
  logic [PARALLEL-1:0][WIDTH-1:0] a_out;         // Butterfly outputs
  logic [PARALLEL-1:0][WIDTH-1:0] b_out;         // Butterfly outputs
  logic [PARALLEL-1:0][WIDTH-1:0] twiddle;       // From BRAM (1-cycle latency)

  //============================================================================
  // Bank Selection Signals
  //============================================================================
  logic read_bank_sel;
  logic write_bank_sel;
  logic [TOTAL_PIPE_DEPTH:0] write_bank_sel_pipe;
  logic pipe_active;
  logic lane_valid_any;

  assign lane_valid_any = |lane_valid;

  //============================================================================
  // Control FSM
  //============================================================================
  ntt_control_parallel #(
      .N             (N),
      .PARALLEL      (PARALLEL),
      .PIPELINE_DEPTH(TOTAL_PIPE_DEPTH + 1)
  ) u_control (
      .clk        (clk),
      .rst_n      (rst_n),
      .start      (start),
      .stall      (1'b0),
      .done       (ctrl_done),
      .busy       (ctrl_busy),
      .draining   (ctrl_draining),
      .stage      (stage),
      .butterfly  (butterfly_base),
      .cycle      (cycle),
      .lane_valid (lane_valid)
  );

  //============================================================================
  // Twiddle Factor BRAM
  //============================================================================
  twiddle_bram_multiport #(
      .DEPTH     (N),
      .WIDTH     (WIDTH),
      .PARALLEL  (PARALLEL),
      .ADDR_WIDTH(ADDR_WIDTH),
      .HEX_FILE  (TWIDDLE_FILE)
  ) u_twiddle_bram (
      .clk (clk),
      .addr(twiddle_addr),
      .data(twiddle)
  );

  //============================================================================
  // Address Generation
  //============================================================================
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

  //============================================================================
  // Bank Switch Logic
  //============================================================================
  ntt_bank_switch #(
      .LOGN           (LOGN),
      .PARALLEL       (PARALLEL),
      .MULT_PIPELINE  (MULT_PIPELINE),
      .TOTAL_PIPE_DEPTH(TOTAL_PIPE_DEPTH)
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

  //============================================================================
  // Coefficient Banks (Separate Module for LUT Analysis)
  //============================================================================
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
      // Load interface
      .load_enable    (load_coeff && !busy),
      .load_addr      (load_addr),
      .load_data      (load_data),
      // Read interface
      .read_addr      (read_addr),
      .read_data      (read_data),
      // Butterfly read interface
      .read_bank_sel  (read_bank_sel),
      .rd_bank_a      (addr0_bank),
      .rd_index_a     (addr0_index),
      .rd_bank_b      (addr1_bank),
      .rd_index_b     (addr1_index),
      .coeff_a        (coeff_a_comb),
      .coeff_b        (coeff_b_comb),
      // Butterfly write interface
      .write_enable   (busy),
      .write_bank_sel (write_bank_sel_pipe[TOTAL_PIPE_DEPTH]),
      .wr_valid       (lane_valid_pipe[TOTAL_PIPE_DEPTH]),
      .wr_bank_a      (addr0_out_bank_pipe[TOTAL_PIPE_DEPTH]),
      .wr_index_a     (addr0_out_index_pipe[TOTAL_PIPE_DEPTH]),
      .wr_bank_b      (addr1_out_bank_pipe[TOTAL_PIPE_DEPTH]),
      .wr_index_b     (addr1_out_index_pipe[TOTAL_PIPE_DEPTH]),
      .result_a       (a_out),
      .result_b       (b_out)
  );

  //============================================================================
  // Pipeline: Register Coefficient Reads to Match BRAM Twiddle Latency
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int lane = 0; lane < PARALLEL; lane++) begin
        a_in[lane] <= '0;
        b_in[lane] <= '0;
      end
    end else begin
      a_in <= coeff_a_comb;
      b_in <= coeff_b_comb;
    end
  end

  //============================================================================
  // Pipeline: Address/Valid Alignment for Write-back
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
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
      lane_valid_pipe[0] <= lane_valid;
      
      if (|lane_valid) begin
        addr0_out_bank_pipe[0] <= addr0_out_bank;
        addr1_out_bank_pipe[0] <= addr1_out_bank;
        addr0_out_index_pipe[0] <= addr0_out_index;
        addr1_out_index_pipe[0] <= addr1_out_index;
      end
      
      for (int stage_idx = 1; stage_idx <= TOTAL_PIPE_DEPTH; stage_idx++) begin
        addr0_out_bank_pipe[stage_idx] <= addr0_out_bank_pipe[stage_idx - 1];
        addr1_out_bank_pipe[stage_idx] <= addr1_out_bank_pipe[stage_idx - 1];
        addr0_out_index_pipe[stage_idx] <= addr0_out_index_pipe[stage_idx - 1];
        addr1_out_index_pipe[stage_idx] <= addr1_out_index_pipe[stage_idx - 1];
        lane_valid_pipe[stage_idx] <= lane_valid_pipe[stage_idx - 1];
      end
    end
  end

  //============================================================================
  // Butterflies
  //============================================================================
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

  //============================================================================
  // Done/Busy Handling
  //============================================================================
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
