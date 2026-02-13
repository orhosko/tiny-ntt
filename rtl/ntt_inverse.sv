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
    parameter int N_INV          = 8347681   // N^(-1) mod Q = 256^(-1) mod 8380417
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

  // Control FSM signals (for INTT)
  logic intt_start, intt_done, intt_busy;
  logic [ADDR_WIDTH-1:0] fsm_addr_a, fsm_addr_b;
  logic fsm_we_a, fsm_we_b;
  logic                  fsm_re;
  logic [ADDR_WIDTH-1:0] twiddle_addr;
  logic                  butterfly_valid;

  // RAM signals
  logic [ADDR_WIDTH-1:0] ram_addr_a, ram_addr_b;
  logic [WIDTH-1:0] ram_din_a, ram_din_b;
  logic [WIDTH-1:0] ram_dout_a, ram_dout_b;
  logic ram_we_a, ram_we_b;

  // Inverse twiddle ROM signal
  logic [WIDTH-1:0] twiddle_factor;

  // Butterfly signals
  logic [WIDTH-1:0] butterfly_in_a, butterfly_in_b, butterfly_twiddle;
  logic [WIDTH-1:0] butterfly_out_a, butterfly_out_b;

  // Pipeline registers for butterfly outputs
  logic [WIDTH-1:0] butterfly_out_a_reg, butterfly_out_b_reg;
  logic                butterfly_valid_reg;

  // Scaling logic (needs 9 bits to reach N=256)
  logic [ADDR_WIDTH:0] scale_addr;  // 9 bits: 0-256
  logic [   WIDTH-1:0] scale_result;
  logic                scale_we;

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
        if (intt_done) next_state = SCALE;
      end

      SCALE: begin
        if (scale_addr >= N) next_state = DONE_STATE;
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

  //============================================================================
  // Scaling Counter
  //============================================================================

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scale_addr <= '0;
    end else begin
      if (state == SCALE) begin
        if (scale_addr < N) scale_addr <= scale_addr + 1;
      end else begin
        scale_addr <= '0;
      end
    end
  end

  //============================================================================
  // RAM Port Multiplexing
  //============================================================================

  // Temporary variables for address computation
  logic [ADDR_WIDTH-1:0] scale_read_addr, scale_write_addr;

  always_comb begin
    // Extract addresses (avoid part-select in always_comb for Icarus)
    scale_read_addr  = scale_addr[ADDR_WIDTH-1:0];
    scale_write_addr = scale_addr_pipe2[ADDR_WIDTH-1:0];

    if (state == INTT_COMPUTE) begin
      // INTT computation: FSM controls both ports
      ram_addr_a = fsm_addr_a;
      ram_addr_b = fsm_addr_b;
      ram_we_a   = fsm_we_a;
      ram_we_b   = fsm_we_b;
      ram_din_a  = butterfly_out_a_reg;
      ram_din_b  = butterfly_out_b_reg;
    end else if (state == SCALE) begin
      // Scaling: Read coefficient, multiply by N_INV, write back to Port A
      // Use pipelined address for write to match data flow
      ram_addr_a = scale_we ? scale_write_addr : scale_read_addr;
      ram_addr_b = load_coeff ? load_addr : '0;  // Allow loading during scale
      ram_we_a   = scale_we;
      ram_we_b   = load_coeff;
      ram_din_a  = scale_result;
      ram_din_b  = load_data;
    end else begin
      // IDLE or DONE: User interface - use Port A for reads (where data was written)
      ram_addr_a = load_coeff ? '0 : read_addr;  // Read from Port A
      ram_addr_b = load_coeff ? load_addr : '0;  // Load via Port B
      ram_we_a   = 1'b0;
      ram_we_b   = load_coeff;
      ram_din_a  = '0;
      ram_din_b  = load_data;
    end
  end

  // Read data from Port A (where INTT/scaling wrote results)
  assign read_data = ram_dout_a;

  //============================================================================
  // Butterfly Input/Output Pipeline
  //============================================================================

  assign butterfly_in_a = ram_dout_a;
  assign butterfly_in_b = ram_dout_b;
  assign butterfly_twiddle = twiddle_factor;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      butterfly_out_a_reg <= '0;
      butterfly_out_b_reg <= '0;
      butterfly_valid_reg <= 1'b0;
    end else begin
      butterfly_out_a_reg <= butterfly_out_a;
      butterfly_out_b_reg <= butterfly_out_b;
      butterfly_valid_reg <= butterfly_valid;
    end
  end

  //============================================================================
  // Scaling Logic
  //============================================================================
  // Multiply each coefficient by N^(-1) = 8347681
  // Pipeline: Read (1 cycle) → Multiply (1 cycle) → Write (1 cycle)

  logic [WIDTH-1:0] scaling_factor;
  assign scaling_factor = N_INV;

  // Pipeline the address to match data flow
  logic [ADDR_WIDTH:0] scale_addr_pipe1, scale_addr_pipe2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scale_addr_pipe1 <= '0;
      scale_addr_pipe2 <= '0;
    end else begin
      if (state == SCALE) begin
        // Pipeline the address through the multiply stages
        scale_addr_pipe1 <= scale_addr;
        scale_addr_pipe2 <= scale_addr_pipe1;
      end else begin
        scale_addr_pipe1 <= '0;
        scale_addr_pipe2 <= '0;
      end
    end
  end

  // Write enable: valid when we have data 2 cycles after read
  assign scale_we = (state == SCALE) && (scale_addr_pipe2 < N);

  // Modular multiplication for scaling
  mod_mult #(
      .WIDTH         (WIDTH),
      .Q             (Q),
      .REDUCTION_TYPE(REDUCTION_TYPE)
  ) scale_mult (
      .a     (ram_dout_a),
      .b     (scaling_factor),
      .result(scale_result)
  );

  //============================================================================
  // Component Instantiation
  //============================================================================

  // Coefficient RAM (Dual-Port)
  coeff_ram #(
      .WIDTH     (WIDTH),
      .DEPTH     (N),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_coeff_ram (
      .clk   (clk),
      .rst_n (rst_n),
      .addr_a(ram_addr_a),
      .din_a (ram_din_a),
      .dout_a(ram_dout_a),
      .we_a  (ram_we_a),
      .addr_b(ram_addr_b),
      .din_b (ram_din_b),
      .dout_b(ram_dout_b),
      .we_b  (ram_we_b)
  );

  // Inverse Twiddle Factor ROM
  inverse_twiddle_rom u_inverse_twiddle_rom (
      .addr   (twiddle_addr),
      .twiddle(twiddle_factor)
  );

  // Butterfly Unit (Cooley-Tukey - same as forward NTT!)
  // INTT uses SAME butterfly as forward NTT, but with inverse twiddles
  ntt_butterfly #(
      .WIDTH         (WIDTH),
      .Q             (Q),
      .REDUCTION_TYPE(REDUCTION_TYPE)
  ) u_butterfly (
      .a      (butterfly_in_a),
      .b      (butterfly_in_b),
      .twiddle(butterfly_twiddle),
      .a_out  (butterfly_out_a),
      .b_out  (butterfly_out_b)
  );

  // Control FSM (same as forward NTT)
  ntt_control #(
      .N         (N),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) u_control (
      .clk            (clk),
      .rst_n          (rst_n),
      .start          (intt_start),
      .done           (intt_done),
      .busy           (intt_busy),
      .ram_addr_a     (fsm_addr_a),
      .ram_addr_b     (fsm_addr_b),
      .ram_we_a       (fsm_we_a),
      .ram_we_b       (fsm_we_b),
      .ram_re         (fsm_re),
      .twiddle_addr   (twiddle_addr),
      .butterfly_valid(butterfly_valid)
  );

endmodule
