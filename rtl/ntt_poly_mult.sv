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
    parameter int N                = 4096,
    parameter int WIDTH            = 24,
    parameter int Q                = 8380417,
    parameter int ADDR_WIDTH       = $clog2(N),
    parameter int REDUCTION_TYPE   = 1,
    parameter int PARALLEL         = 8,
    parameter int PSI              = 283817,
    parameter int PSI_INV          = 7893065,
    parameter int N_INV            = 8378371,
    parameter     FWD_TWIDDLE_FILE = "twiddle_forward_4096.hex",
    parameter     INV_TWIDDLE_FILE = "twiddle_inverse_4096.hex",
    parameter bit POINTWISE_PARALLEL = 1'b0,
    parameter int MULT_PIPELINE    = 4
) (
    input  logic clk,
    input  logic rst_n,

    input  logic start,
    output logic done,
    output logic busy,
    output logic [3:0] debug_state,
    output logic fwd_done,
    output logic inv_done,
    output logic fwd_started,
    output logic inv_started,

    input  logic                  load_coeff,
    input  logic                  load_sel,
    input  logic [ADDR_WIDTH-1:0] load_addr,
    input  logic [WIDTH-1:0]      load_data,

    input  logic                  debug_read_sel,
    input  logic [ADDR_WIDTH-1:0] debug_read_addr,
    output logic [WIDTH-1:0]      debug_read_data,

    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [WIDTH-1:0]      read_data
);

  localparam int READ_COUNT_WIDTH = $clog2(N + 1);
  localparam int C_RAM_READ_LATENCY = 1;

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

  assign debug_state = state;

  logic [WIDTH-1:0] a_ntt[0:N-1];
  logic [WIDTH-1:0] b_ntt[0:N-1];
  logic [WIDTH-1:0] c_ntt[0:N-1];

  logic fwd_start;
  logic fwd_busy;
  logic fwd_load;
  logic [ADDR_WIDTH-1:0] fwd_load_addr;
  logic [WIDTH-1:0] fwd_load_data;
  logic [ADDR_WIDTH-1:0] fwd_read_addr;
  logic [WIDTH-1:0] fwd_read_data;

  logic inv_start;
  logic inv_busy;
  logic inv_load;
  logic [ADDR_WIDTH-1:0] inv_load_addr;
  logic [WIDTH-1:0] inv_load_data;
  logic [ADDR_WIDTH-1:0] inv_read_addr;
  logic [WIDTH-1:0] inv_read_data;

  logic [READ_COUNT_WIDTH-1:0] load_index;
  logic [READ_COUNT_WIDTH-1:0] read_index;
  logic read_pending;
  logic [READ_COUNT_WIDTH-1:0] point_index;
  logic [READ_COUNT_WIDTH-1:0] bram_data_index;
  logic bram_data_valid;
  logic [READ_COUNT_WIDTH-1:0] mul_index_pipe[0:MULT_PIPELINE];
  logic [MULT_PIPELINE:0] mul_valid_pipe;

  logic clear_ntt;

  logic [WIDTH-1:0] mul_a;
  logic [WIDTH-1:0] mul_b;
  logic [WIDTH-1:0] mul_result;
  logic [WIDTH-1:0] a_ntt_dout_b;
  logic [WIDTH-1:0] b_ntt_dout_b;
  logic [ADDR_WIDTH-1:0] a_ntt_addr_b;
  logic [ADDR_WIDTH-1:0] b_ntt_addr_b;
  logic a_ntt_we_a;
  logic b_ntt_we_a;
  logic [ADDR_WIDTH-1:0] a_ntt_wr_addr;
  logic [ADDR_WIDTH-1:0] b_ntt_wr_addr;
  logic [WIDTH-1:0] a_ntt_wr_data;
  logic [WIDTH-1:0] b_ntt_wr_data;
  logic [WIDTH-1:0] c_ntt_dout_b;
  logic [ADDR_WIDTH-1:0] c_ntt_addr_b;
  logic c_ntt_we_a;
  logic [ADDR_WIDTH-1:0] c_ntt_wr_addr;
  logic [WIDTH-1:0] c_ntt_wr_data;
  logic [N*WIDTH-1:0] a_ntt_flat;
  logic [N*WIDTH-1:0] b_ntt_flat;
  logic [N*WIDTH-1:0] c_ntt_flat;
  logic [WIDTH-1:0] c_ntt_parallel[0:N-1];
  logic [WIDTH-1:0] a_mem_read_data;
  logic [WIDTH-1:0] b_mem_read_data;
  wire input_mem_read_active = (state == LOAD_A) || (state == LOAD_B);
  wire [ADDR_WIDTH-1:0] input_mem_read_addr =
      (input_mem_read_active && (load_index < N)) ? load_index[ADDR_WIDTH-1:0]
                                                  : debug_read_addr;

  bram_tdp #(
      .WIDTH     (WIDTH),
      .DEPTH     (N),
      .ADDR_WIDTH(ADDR_WIDTH),
      .WRITE_MODE(1),
      .INIT_ZERO (1)
  ) u_a_input_mem (
      .clk   (clk),
      .en_a  (1'b1),
      .we_a  (load_coeff && (state == IDLE) && !load_sel),
      .addr_a(load_addr),
      .din_a (load_data),
      .dout_a(),
      .en_b  (1'b1),
      .we_b  (1'b0),
      .addr_b(input_mem_read_addr),
      .din_b ({WIDTH{1'b0}}),
      .dout_b(a_mem_read_data)
  );

  bram_tdp #(
      .WIDTH     (WIDTH),
      .DEPTH     (N),
      .ADDR_WIDTH(ADDR_WIDTH),
      .WRITE_MODE(1),
      .INIT_ZERO (1)
  ) u_b_input_mem (
      .clk   (clk),
      .en_a  (1'b1),
      .we_a  (load_coeff && (state == IDLE) && load_sel),
      .addr_a(load_addr),
      .din_a (load_data),
      .dout_a(),
      .en_b  (1'b1),
      .we_b  (1'b0),
      .addr_b(input_mem_read_addr),
      .din_b ({WIDTH{1'b0}}),
      .dout_b(b_mem_read_data)
  );

  ntt_forward #(
      .N(N),
      .WIDTH(WIDTH),
      .Q(Q),
      .PSI(PSI),
      .ADDR_WIDTH(ADDR_WIDTH),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .PARALLEL(PARALLEL),
      .MULT_PIPELINE(MULT_PIPELINE),
      .TWIDDLE_FILE(FWD_TWIDDLE_FILE)
  ) u_forward (
      .clk(clk),
      .rst_n(rst_n),
      .start(fwd_start),
      .done(fwd_done),
      .busy(fwd_busy),
      .load_coeff(fwd_load),
      .load_addr(fwd_load_addr),
      .load_data(fwd_load_data),
      .read_addr(fwd_read_addr),
      .read_data(fwd_read_data)
  );

  ntt_inverse #(
      .N(N),
      .WIDTH(WIDTH),
      .Q(Q),
      .PSI_INV(PSI_INV),
      .ADDR_WIDTH(ADDR_WIDTH),
      .REDUCTION_TYPE(REDUCTION_TYPE),
      .N_INV(N_INV),
      .PARALLEL(PARALLEL),
      .MULT_PIPELINE(MULT_PIPELINE),
      .TWIDDLE_FILE(INV_TWIDDLE_FILE)
  ) u_inverse (
      .clk(clk),
      .rst_n(rst_n),
      .start(inv_start),
      .done(inv_done),
      .busy(inv_busy),
      .load_coeff(inv_load),
      .load_addr(inv_load_addr),
      .load_data(inv_load_data),
      .read_addr(inv_read_addr),
      .read_data(inv_read_data)
  );

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
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .MULT_PIPELINE(MULT_PIPELINE)
      ) u_pointwise_mult_parallel (
          .clk(clk),
          .rst_n(rst_n),
          .poly_a_flat(a_ntt_flat),
          .poly_b_flat(b_ntt_flat),
          .poly_c_flat(c_ntt_flat)
      );
    end else begin : gen_pointwise_serial
      coeff_ram #(
          .WIDTH(WIDTH),
          .DEPTH(N),
          .ADDR_WIDTH(ADDR_WIDTH)
      ) u_a_ntt_mem (
          .clk(clk),
          .rst_n(rst_n),
          .addr_a(a_ntt_wr_addr),
          .din_a(a_ntt_wr_data),
          .dout_a(),
          .we_a(a_ntt_we_a),
          .addr_b(a_ntt_addr_b),
          .din_b('0),
          .dout_b(a_ntt_dout_b),
          .we_b(1'b0)
      );

      coeff_ram #(
          .WIDTH(WIDTH),
          .DEPTH(N),
          .ADDR_WIDTH(ADDR_WIDTH)
      ) u_b_ntt_mem (
          .clk(clk),
          .rst_n(rst_n),
          .addr_a(b_ntt_wr_addr),
          .din_a(b_ntt_wr_data),
          .dout_a(),
          .we_a(b_ntt_we_a),
          .addr_b(b_ntt_addr_b),
          .din_b('0),
          .dout_b(b_ntt_dout_b),
          .we_b(1'b0)
      );

      coeff_ram #(
          .WIDTH(WIDTH),
          .DEPTH(N),
          .ADDR_WIDTH(ADDR_WIDTH)
      ) u_c_ntt_mem (
          .clk(clk),
          .rst_n(rst_n),
          .addr_a(c_ntt_wr_addr),
          .din_a(c_ntt_wr_data),
          .dout_a(),
          .we_a(c_ntt_we_a),
          .addr_b(c_ntt_addr_b),
          .din_b('0),
          .dout_b(c_ntt_dout_b),
          .we_b(1'b0)
      );

      mod_mult #(
          .WIDTH(WIDTH),
          .Q(Q),
          .REDUCTION_TYPE(REDUCTION_TYPE),
          .PIPELINE_STAGES(MULT_PIPELINE)
      ) u_pointwise_mult (
          .clk(clk),
          .rst_n(rst_n),
          .a(mul_a),
          .b(mul_b),
          .result(mul_result)
      );
    end
  endgenerate

  assign clear_ntt = (state == IDLE && next_state == LOAD_A);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE;
      load_index <= '0;
      read_index <= '0;
      read_pending <= 1'b0;
      point_index <= '0;
      bram_data_index <= '0;
      bram_data_valid <= 1'b0;
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
          bram_data_index <= '0;
          bram_data_valid <= 1'b0;
        end
        if (next_state != RUN_A) begin
          fwd_started <= 1'b0;
        end
        if (next_state != RUN_INV) begin
          inv_started <= 1'b0;
        end
      end

      case (state)
        LOAD_A, LOAD_B: begin
          if (load_index <= N[READ_COUNT_WIDTH-1:0]) begin
            load_index <= load_index + 1'b1;
          end
        end
        LOAD_INV: begin
          if (POINTWISE_PARALLEL) begin
            if (load_index < N) begin
              load_index <= load_index + 1'b1;
            end
          end else begin
            if (load_index <= N) begin
              load_index <= load_index + 1'b1;
            end
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
          if (!POINTWISE_PARALLEL) begin
            bram_data_index <= point_index;
            bram_data_valid <= (point_index < N);
          end
          if (POINTWISE_PARALLEL) begin
            if (point_index < MULT_PIPELINE[READ_COUNT_WIDTH-1:0]) begin
              point_index <= point_index + 1'b1;
            end else begin
              point_index <= N[READ_COUNT_WIDTH-1:0];
            end
          end else begin
            if (point_index < N) begin
              point_index <= point_index + 1'b1;
            end
          end
        end
        default: begin
          bram_data_valid <= 1'b0;
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
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int stage_idx = 0; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        mul_index_pipe[stage_idx] <= '0;
        mul_valid_pipe[stage_idx] <= 1'b0;
      end
    end else if (state == POINTWISE && !POINTWISE_PARALLEL) begin
      mul_index_pipe[0] <= bram_data_index;
      mul_valid_pipe[0] <= bram_data_valid;
      for (int stage_idx = 1; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        mul_index_pipe[stage_idx] <= mul_index_pipe[stage_idx - 1];
        mul_valid_pipe[stage_idx] <= mul_valid_pipe[stage_idx - 1];
      end
    end else begin
      for (int stage_idx = 0; stage_idx <= MULT_PIPELINE; stage_idx++) begin
        mul_index_pipe[stage_idx] <= '0;
        mul_valid_pipe[stage_idx] <= 1'b0;
      end
    end
  end

  generate
    if (POINTWISE_PARALLEL) begin : gen_ntt_storage_parallel
      for (genvar i = 0; i < N; i++) begin : gen_ntt_storage
        always_ff @(posedge clk) begin
          if (!rst_n) begin
            a_ntt[i] <= '0;
            b_ntt[i] <= '0;
            c_ntt[i] <= '0;
          end else if (clear_ntt) begin
            a_ntt[i] <= '0;
            b_ntt[i] <= '0;
            c_ntt[i] <= '0;
          end else begin
            case (state)
              READ_A: begin
                if (read_pending && (read_index - 1'b1) == READ_COUNT_WIDTH'(i)) begin
                  a_ntt[i] <= fwd_read_data;
                end
              end
              READ_B: begin
                if (read_pending && (read_index - 1'b1) == READ_COUNT_WIDTH'(i)) begin
                  b_ntt[i] <= fwd_read_data;
                end
              end
              POINTWISE: begin
                if (point_index == MULT_PIPELINE[READ_COUNT_WIDTH-1:0]) begin
                  c_ntt[i] <= c_ntt_parallel[i];
                end
              end
              default: begin
              end
            endcase
          end
        end
      end
    end
  endgenerate

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start) next_state = LOAD_A;
      end
      LOAD_A: begin
        if (load_index > N[READ_COUNT_WIDTH-1:0]) next_state = RUN_A;
      end
      RUN_A: begin
        if (fwd_done) next_state = READ_A;
      end
      READ_A: begin
        if (read_index >= N && !read_pending) next_state = LOAD_B;
      end
      LOAD_B: begin
        if (load_index > N[READ_COUNT_WIDTH-1:0]) next_state = RUN_B;
      end
      RUN_B: begin
        if (fwd_done) next_state = READ_B;
      end
      READ_B: begin
        if (read_index >= N && !read_pending) next_state = POINTWISE;
      end
      POINTWISE: begin
        if (POINTWISE_PARALLEL) begin
          if (point_index >= N) next_state = LOAD_INV;
        end else if (MULT_PIPELINE == 0) begin
          if (point_index >= N) next_state = LOAD_INV;
        end else begin
          if (point_index >= N && !mul_valid_pipe[MULT_PIPELINE]) begin
            next_state = LOAD_INV;
          end
        end
      end
      LOAD_INV: begin
        if (POINTWISE_PARALLEL) begin
          if (load_index >= N) next_state = RUN_INV;
        end else begin
          if (load_index > N) next_state = RUN_INV;
        end
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

  assign fwd_start = (state == RUN_A || state == RUN_B) && !fwd_started;

  assign fwd_load = (state == LOAD_A || state == LOAD_B) &&
                    (load_index > 0) &&
                    (load_index <= N[READ_COUNT_WIDTH-1:0]);
  assign fwd_load_addr = load_index[ADDR_WIDTH-1:0] - ADDR_WIDTH'(1);
  assign fwd_load_data = (state == LOAD_A) ? a_mem_read_data :
                         (state == LOAD_B) ? b_mem_read_data : '0;

  assign fwd_read_addr = (state == READ_A || state == READ_B) ?
                         (read_index < N ? read_index[ADDR_WIDTH-1:0] : ADDR_WIDTH'(N - 1)) :
                         '0;

  assign a_ntt_we_a = !POINTWISE_PARALLEL && (state == READ_A) && read_pending;
  assign a_ntt_wr_addr = read_index[ADDR_WIDTH-1:0] - ADDR_WIDTH'(1);
  assign a_ntt_wr_data = fwd_read_data;
  assign a_ntt_addr_b = (!POINTWISE_PARALLEL && state == POINTWISE && point_index < N)
                        ? point_index[ADDR_WIDTH-1:0] : '0;

  assign b_ntt_we_a = !POINTWISE_PARALLEL && (state == READ_B) && read_pending;
  assign b_ntt_wr_addr = read_index[ADDR_WIDTH-1:0] - ADDR_WIDTH'(1);
  assign b_ntt_wr_data = fwd_read_data;
  assign b_ntt_addr_b = (!POINTWISE_PARALLEL && state == POINTWISE && point_index < N)
                        ? point_index[ADDR_WIDTH-1:0] : '0;

  assign mul_a = POINTWISE_PARALLEL ? ((point_index < N) ? a_ntt[point_index] : '0)
                                    : a_ntt_dout_b;
  assign mul_b = POINTWISE_PARALLEL ? ((point_index < N) ? b_ntt[point_index] : '0)
                                    : b_ntt_dout_b;

  assign inv_start = (state == RUN_INV) && !inv_started;
  assign c_ntt_we_a = !POINTWISE_PARALLEL &&
                      ((MULT_PIPELINE == 0) ? bram_data_valid
                                            : mul_valid_pipe[MULT_PIPELINE]);
  assign c_ntt_wr_addr = (MULT_PIPELINE == 0) ? bram_data_index[ADDR_WIDTH-1:0]
                                              : mul_index_pipe[MULT_PIPELINE][ADDR_WIDTH-1:0];
  assign c_ntt_wr_data = mul_result;
  assign c_ntt_addr_b = (!POINTWISE_PARALLEL && state == LOAD_INV && load_index < N)
                        ? load_index[ADDR_WIDTH-1:0] : '0;

  assign inv_load = POINTWISE_PARALLEL ? ((state == LOAD_INV) && (load_index < N))
                                       : ((state == LOAD_INV) &&
                                          (load_index >= C_RAM_READ_LATENCY) &&
                                          (load_index <= N));
  assign inv_load_addr = POINTWISE_PARALLEL ? load_index[ADDR_WIDTH-1:0]
                                            : (load_index[ADDR_WIDTH-1:0] - C_RAM_READ_LATENCY);
  assign inv_load_data = POINTWISE_PARALLEL ? ((load_index < N) ? c_ntt[load_index] : '0)
                                            : c_ntt_dout_b;

  assign inv_read_addr = (state == DONE_STATE || state == IDLE) ? read_addr : '0;
  assign read_data = inv_read_data;

  assign debug_read_data = debug_read_sel ? b_mem_read_data : a_mem_read_data;

endmodule
