`timescale 1ns / 1ps

//==============================================================================
// NTT Forward Transform - Top Level
//==============================================================================
// Complete N=256 radix-2 Cooley-Tukey NTT pipeline
//
// Integrates:
//   - Dual-port coefficient RAM
//   - Twiddle factor ROM
//   - Butterfly computation unit
//   - Control FSM
//
// Usage:
//   1. Load coefficients via load interface
//   2. Assert start for one cycle
//   3. Wait for done signal
//   4. Read results via read interface
//==============================================================================

module ntt_forward #(
    parameter int N              = 256,      // NTT size
    parameter int WIDTH          = 32,       // Data width
    parameter int Q              = 8380417,  // Modulus
    parameter int ADDR_WIDTH     = 8,        // log₂(N)
    parameter int REDUCTION_TYPE = 0         // 0=Simple, 1=Barrett, 2=Montgomery
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

  //============================================================================
  // Internal Signals
  //============================================================================

  // Control FSM signals
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

  // Twiddle ROM signal
  logic [WIDTH-1:0] twiddle_factor;

  // Butterfly signals
  logic [WIDTH-1:0] butterfly_in_a, butterfly_in_b, butterfly_twiddle;
  logic [WIDTH-1:0] butterfly_out_a, butterfly_out_b;

  // Pipeline registers for butterfly outputs
  logic [WIDTH-1:0] butterfly_out_a_reg, butterfly_out_b_reg;
  logic butterfly_valid_reg;

  //============================================================================
  // RAM Port Multiplexing
  //============================================================================
  // Port A: Controlled by FSM during computation
  // Port B: User interface for load/read

  always_comb begin
    if (busy) begin
      // During computation: FSM controls Port A
      ram_addr_a = fsm_addr_a;
      ram_addr_b = fsm_addr_b;
      ram_we_a   = fsm_we_a;
      ram_we_b   = fsm_we_b;
      ram_din_a  = butterfly_out_a_reg;
      ram_din_b  = butterfly_out_b_reg;
    end else begin
      // Idle: User interface on Port B
      ram_addr_a = '0;
      ram_addr_b = load_coeff ? load_addr : read_addr;
      ram_we_a   = 1'b0;
      ram_we_b   = load_coeff;
      ram_din_a  = '0;
      ram_din_b  = load_data;
    end
  end

  // Read data output
  assign read_data = ram_dout_b;

  //============================================================================
  // Butterfly Input/Output Pipeline
  //============================================================================

  // Butterfly inputs come directly from RAM
  assign butterfly_in_a = ram_dout_a;
  assign butterfly_in_b = ram_dout_b;
  assign butterfly_twiddle = twiddle_factor;

  // Register butterfly outputs for better timing
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
      // Port A
      .addr_a(ram_addr_a),
      .din_a (ram_din_a),
      .dout_a(ram_dout_a),
      .we_a  (ram_we_a),
      // Port B
      .addr_b(ram_addr_b),
      .din_b (ram_din_b),
      .dout_b(ram_dout_b),
      .we_b  (ram_we_b)
  );

  // Twiddle Factor ROM
  twiddle_rom u_twiddle_rom (
      .addr   (twiddle_addr),
      .twiddle(twiddle_factor)
  );

  // Butterfly Unit
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

  // Control FSM
  ntt_control #(
      .N         (N),
      .ADDR_WIDTH(ADDR_WIDTH),
      .INVERSE   (1'b0),
      .DIF       (1'b1)
  ) u_control (
      .clk            (clk),
      .rst_n          (rst_n),
      .start          (start),
      .done           (done),
      .busy           (busy),
      .ram_addr_a     (fsm_addr_a),
      .ram_addr_b     (fsm_addr_b),
      .ram_we_a       (fsm_we_a),
      .ram_we_b       (fsm_we_b),
      .ram_re         (fsm_re),
      .twiddle_addr   (twiddle_addr),
      .butterfly_valid(butterfly_valid)
  );

endmodule
