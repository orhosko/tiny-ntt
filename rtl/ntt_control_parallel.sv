`timescale 1ns / 1ps

//==============================================================================
// NTT Control FSM (Parallel Butterflies)
//==============================================================================
// Generates stage/butterfly scheduling for configurable parallelism.
//==============================================================================

module ntt_control_parallel #(
    parameter int N = 256,
    parameter int PARALLEL = 8
) (
    input  logic clk,
    input  logic rst_n,

    input  logic start,
    output logic done,
    output logic busy,

    output logic [$clog2(N)-1:0] stage,
    output logic [$clog2(N/2)-1:0] butterfly,
    output logic [$clog2(N/2)-1:0] cycle,
    output logic [PARALLEL-1:0] lane_valid
);

  localparam int LOGN = $clog2(N);
  localparam int LAST_STAGE = LOGN - 1;
  localparam int TOTAL_BUTTERFLIES = N / 2;
  localparam int CYCLES_PER_STAGE = (TOTAL_BUTTERFLIES + PARALLEL - 1) / PARALLEL;
  localparam int CYCLE_WIDTH = $clog2(CYCLES_PER_STAGE == 0 ? 1 : CYCLES_PER_STAGE);

  typedef enum logic [1:0] {
    IDLE = 2'b00,
    COMPUTE = 2'b01,
    DONE_STATE = 2'b10
  } state_t;

  state_t state, next_state;

  logic [LOGN-1:0] stage_next;
  logic [CYCLE_WIDTH-1:0] cycle_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      stage <= '0;
      cycle <= '0;
    end else begin
      state <= next_state;
      stage <= stage_next;
      cycle <= cycle_next;
    end
  end

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start) begin
          next_state = COMPUTE;
        end
      end
      COMPUTE: begin
        if ((stage == LAST_STAGE) && (cycle == CYCLES_PER_STAGE - 1)) begin
          next_state = DONE_STATE;
        end
      end
      DONE_STATE: begin
        if (!start) begin
          next_state = IDLE;
        end
      end
      default: next_state = IDLE;
    endcase
  end

  always_comb begin
    stage_next = stage;
    cycle_next = cycle;

    case (state)
      IDLE: begin
        if (start) begin
          stage_next = '0;
          cycle_next = '0;
        end
      end
      COMPUTE: begin
        if (stage <= LAST_STAGE) begin
          if (cycle == CYCLES_PER_STAGE - 1) begin
            cycle_next = '0;
            if (stage < LAST_STAGE) begin
              stage_next = stage + 1'b1;
            end else begin
              stage_next = stage;
            end
          end else begin
            cycle_next = cycle + 1'b1;
          end
        end
      end
      DONE_STATE: begin
        if (!start) begin
          stage_next = '0;
          cycle_next = '0;
        end
      end
      default: begin
        stage_next = '0;
        cycle_next = '0;
      end
    endcase
  end

  always_comb begin
    busy = (state == COMPUTE);
    done = (state == DONE_STATE);

    butterfly = cycle * PARALLEL;

    for (int lane = 0; lane < PARALLEL; lane++) begin
      lane_valid[lane] = ((butterfly + lane) < TOTAL_BUTTERFLIES)
                         && (state == COMPUTE)
                         && (stage <= LAST_STAGE);
    end
  end

endmodule
