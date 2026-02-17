`timescale 1ns / 1ps

//==============================================================================
// Polynomial Multiplication Top Level (NTT-based)
//==============================================================================
// Workflow:
//  1) Load A and B coefficients
//  2) Forward NTT on A
//  3) Forward NTT on B
//  4) Pointwise multiply
//  5) Inverse NTT
//  6) Read results
//==============================================================================

module ntt_poly_mult #(
    parameter int N              = 256,
    parameter int WIDTH          = 32,
    parameter int Q              = 8380417,
    parameter int ADDR_WIDTH     = 8,
    parameter int REDUCTION_TYPE = 0,
    parameter int PARALLEL       = 1,
    parameter bit POINTWISE_PARALLEL = 1'b0
) (
    input  logic clk,
    input  logic rst_n,

    // Control
    input  logic start,
    output logic done,
    output logic busy,

    // Load interface
    input  logic                  load_coeff,
    input  logic                  load_sel,   // 0 = A, 1 = B
    input  logic [ADDR_WIDTH-1:0] load_addr,
    input  logic [     WIDTH-1:0] load_data,

    // Read interface (result)
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [     WIDTH-1:0] read_data
);

  localparam int TOTAL_BUTTERFLIES = N / 2;
  localparam int READ_COUNT_WIDTH = $clog2(N + 1);

  typedef enum logic [3:0] {
    IDLE,
    LOAD_A,
    RUN_A,
    READ_A,
    LOAD_B,
    RUN_B,
    READ_B,
    POINTWISE,
    LOAD_INV,
    RUN_INV,
    DONE_STATE
  } state_t;

  state_t state, next_state;

  // Local coefficient storage
  logic [WIDTH-1:0] a_mem[0:N-1];
  logic [WIDTH-1:0] b_mem[0:N-1];
  logic [WIDTH-1:0] a_ntt[0:N-1];
  logic [WIDTH-1:0] b_ntt[0:N-1];
  logic [WIDTH-1:0] c_ntt[0:N-1];

  // Initialize coefficient storage for simulation
  initial begin
    for (int i = 0; i < N; i++) begin
      a_mem[i] = '0;
      b_mem[i] = '0;
    end
  end

  // Forward NTT interface
  logic fwd_start;
  logic fwd_done;
  logic fwd_busy;
  logic fwd_load;
  logic [ADDR_WIDTH-1:0] fwd_load_addr;
  logic [WIDTH-1:0] fwd_load_data;
  logic [ADDR_WIDTH-1:0] fwd_read_addr;
  logic [WIDTH-1:0] fwd_read_data;

  // Inverse NTT interface
  logic inv_start;
  logic inv_done;
  logic inv_busy;
  logic inv_load;
  logic [ADDR_WIDTH-1:0] inv_load_addr;
  logic [WIDTH-1:0] inv_load_data;
  logic [ADDR_WIDTH-1:0] inv_read_addr;
  logic [WIDTH-1:0] inv_read_data;

  // Counters
  logic [READ_COUNT_WIDTH-1:0] load_index;
  logic [READ_COUNT_WIDTH-1:0] read_index;
  logic read_pending;
  logic [READ_COUNT_WIDTH-1:0] point_index;

  logic fwd_started;
  logic inv_started;
  logic clear_ntt;

  // Pointwise multiplier
  logic [WIDTH-1:0] mul_a;
  logic [WIDTH-1:0] mul_b;
  logic [WIDTH-1:0] mul_result;
  logic [N*WIDTH-1:0] a_ntt_flat;
  logic [N*WIDTH-1:0] b_ntt_flat;
  logic [N*WIDTH-1:0] c_ntt_flat;
  logic [WIDTH-1:0] c_ntt_parallel[0:N-1];

  //==============================================================================
  // Coefficient load storage
  //==============================================================================
  always_ff @(posedge clk) begin
    if (load_coeff && state == IDLE) begin
      if (load_sel) begin
        b_mem[load_addr] <= load_data;
      end else begin
        a_mem[load_addr] <= load_data;
      end
    end
  end

  //==============================================================================
  // Forward NTT instance
  //==============================================================================
  ntt_forward #(
      .N(N),
      .WIDTH(WIDTH),
      .Q(Q),
      .ADDR_WIDTH(ADDR_WIDTH),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PARALLEL(PARALLEL)
  ) u_forward (
      .clk       (clk),
      .rst_n     (rst_n),
      .start     (fwd_start),
      .done      (fwd_done),
      .busy      (fwd_busy),
      .load_coeff(fwd_load),
      .load_addr (fwd_load_addr),
      .load_data (fwd_load_data),
      .read_addr (fwd_read_addr),
      .read_data (fwd_read_data)
  );

  //==============================================================================
  // Inverse NTT instance
  //==============================================================================
  ntt_inverse #(
      .N(N),
      .WIDTH(WIDTH),
      .Q(Q),
      .ADDR_WIDTH(ADDR_WIDTH),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PARALLEL(PARALLEL)
  ) u_inverse (
      .clk       (clk),
      .rst_n     (rst_n),
      .start     (inv_start),
      .done      (inv_done),
      .busy      (inv_busy),
      .load_coeff(inv_load),
      .load_addr (inv_load_addr),
      .load_data (inv_load_data),
      .read_addr (inv_read_addr),
      .read_data (inv_read_data)
  );

  //==============================================================================
  // Pointwise multiplier
  //==============================================================================
  always_comb begin
    for (int i = 0; i < N; i++) begin
      a_ntt_flat[i * WIDTH +: WIDTH] = a_ntt[i];
      b_ntt_flat[i * WIDTH +: WIDTH] = b_ntt[i];
    end
  end

  for (genvar i = 0; i < N; i++) begin : gen_unpack_parallel
    assign c_ntt_parallel[i] = c_ntt_flat[i * WIDTH +: WIDTH];
  end

  generate
    if (POINTWISE_PARALLEL) begin : gen_pointwise_parallel
      ntt_pointwise_mult #(
          .N(N),
          .WIDTH(WIDTH),
          .Q(Q),
          .REDUCTION_TYPE(REDUCTION_TYPE)
      ) u_pointwise_mult_parallel (
          .poly_a_flat(a_ntt_flat),
          .poly_b_flat(b_ntt_flat),
          .poly_c_flat(c_ntt_flat)
      );
    end else begin : gen_pointwise_serial
      mod_mult #(
          .WIDTH(WIDTH),
          .Q(Q),
          .REDUCTION_TYPE(REDUCTION_TYPE)
      ) u_pointwise_mult (
          .a(mul_a),
          .b(mul_b),
          .result(mul_result)
      );
    end
  endgenerate

  //==============================================================================
  // FSM
  //==============================================================================
  assign clear_ntt = (state == IDLE && next_state == LOAD_A);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      load_index <= '0;
      read_index <= '0;
      read_pending <= 1'b0;
      point_index <= '0;
      fwd_started <= 1'b0;
      inv_started <= 1'b0;
    end else begin
      state <= next_state;

      if (state != next_state) begin
        if (next_state == LOAD_A || next_state == LOAD_B || next_state == LOAD_INV) begin
          load_index <= '0;
        end
        if (next_state == READ_A || next_state == READ_B) begin
          read_index <= '0;
          read_pending <= 1'b0;
        end
        if (next_state == POINTWISE) begin
          point_index <= '0;
        end
        if (next_state != RUN_A) begin
          fwd_started <= 1'b0;
        end
        if (next_state != RUN_INV) begin
          inv_started <= 1'b0;
        end
      end

      case (state)
        LOAD_A, LOAD_B, LOAD_INV: begin
          if (load_index < N) begin
            load_index <= load_index + 1'b1;
          end
        end
        READ_A: begin
          if (read_index < N) begin
            read_index <= read_index + 1'b1;
            read_pending <= 1'b1;
          end else begin
            read_pending <= 1'b0;
          end
        end
        READ_B: begin
          if (read_index < N) begin
            read_index <= read_index + 1'b1;
            read_pending <= 1'b1;
          end else begin
            read_pending <= 1'b0;
          end
        end
        POINTWISE: begin
          if (POINTWISE_PARALLEL) begin
            point_index <= N[READ_COUNT_WIDTH-1:0];
          end else begin
            if (point_index < N) begin
              point_index <= point_index + 1'b1;
            end
          end
        end
        RUN_A: begin
          if (fwd_start) begin
            fwd_started <= 1'b1;
          end
        end
        RUN_INV: begin
          if (inv_start) begin
            inv_started <= 1'b1;
          end
        end
        default: begin
        end
      endcase
    end
  end

  //==============================================================================
  // NTT coefficient storage
  //==============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < N; i++) begin
        a_ntt[i] <= '0;
        b_ntt[i] <= '0;
        c_ntt[i] <= '0;
      end
    end else if (clear_ntt) begin
      for (int i = 0; i < N; i++) begin
        a_ntt[i] <= '0;
        b_ntt[i] <= '0;
        c_ntt[i] <= '0;
      end
    end else begin
      case (state)
        READ_A: begin
          if (read_pending) begin
            a_ntt[read_index - 1] <= fwd_read_data;
          end
        end
        READ_B: begin
          if (read_pending) begin
            b_ntt[read_index - 1] <= fwd_read_data;
          end
        end
        POINTWISE: begin
          if (POINTWISE_PARALLEL) begin
            for (int i = 0; i < N; i++) begin
              c_ntt[i] <= c_ntt_parallel[i];
            end
          end else begin
            if (point_index < N) begin
              c_ntt[point_index] <= mul_result;
            end
          end
        end
        default: begin
        end
      endcase
    end
  end

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start) next_state = LOAD_A;
      end
      LOAD_A: begin
        if (load_index >= N) next_state = RUN_A;
      end
      RUN_A: begin
        if (fwd_done) next_state = READ_A;
      end
      READ_A: begin
        if (read_index >= N && !read_pending) next_state = LOAD_B;
      end
      LOAD_B: begin
        if (load_index >= N) next_state = RUN_B;
      end
      RUN_B: begin
        if (fwd_done) next_state = READ_B;
      end
      READ_B: begin
        if (read_index >= N && !read_pending) next_state = POINTWISE;
      end
      POINTWISE: begin
        if (point_index >= N) next_state = LOAD_INV;
      end
      LOAD_INV: begin
        if (load_index >= N) next_state = RUN_INV;
      end
      RUN_INV: begin
        if (inv_done) next_state = DONE_STATE;
      end
      DONE_STATE: begin
        if (!start) next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  assign busy = (state != IDLE) && (state != DONE_STATE);
  assign done = (state == DONE_STATE);

  //==============================================================================
  // Forward NTT drive
  //==============================================================================
  assign fwd_start = (state == RUN_A || state == RUN_B) && !fwd_started;

  assign fwd_load = (state == LOAD_A || state == LOAD_B) && (load_index < N);
  assign fwd_load_addr = load_index[ADDR_WIDTH-1:0];
  assign fwd_load_data = (load_index < N)
                         ? ((state == LOAD_A) ? a_mem[load_index] : b_mem[load_index])
                         : '0;

  assign fwd_read_addr = (state == READ_A || state == READ_B) ?
                         (read_index < N ? read_index[ADDR_WIDTH-1:0] : ADDR_WIDTH'(N - 1)) :
                         '0;

  //==============================================================================
  // Pointwise multiply drive
  //==============================================================================
  assign mul_a = (point_index < N) ? a_ntt[point_index] : '0;
  assign mul_b = (point_index < N) ? b_ntt[point_index] : '0;

  //==============================================================================
  // Inverse NTT drive
  //==============================================================================
  assign inv_start = (state == RUN_INV) && !inv_started;
  assign inv_load = (state == LOAD_INV) && (load_index < N);
  assign inv_load_addr = load_index[ADDR_WIDTH-1:0];
  assign inv_load_data = (load_index < N) ? c_ntt[load_index] : '0;

  assign inv_read_addr = (state == DONE_STATE || state == IDLE) ? read_addr : '0;
  assign read_data = inv_read_data;

endmodule
