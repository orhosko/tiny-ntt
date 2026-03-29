`timescale 1ns / 1ps

//==============================================================================
// NTT Control FSM (Parallel Butterflies)
//==============================================================================
// Generates stage/butterfly scheduling for configurable parallelism.
//==============================================================================

module ntt_control_parallel #(
    parameter int N = 256,
    parameter int PARALLEL = 8,
    parameter int PIPELINE_DEPTH = 3  // Butterfly pipeline depth
) (
    input  logic clk,
    input  logic rst_n,

    input  logic start,
    input  logic stall,           // Stalls both issuance and advancement
    output logic done,
    output logic busy,
    output logic draining,        // Indicates pipeline drain at stage boundary

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

  typedef enum logic [2:0] {
    IDLE = 3'b000,
    COMPUTE = 3'b001,
    STAGE_DRAIN = 3'b010,   // Waiting for pipeline to drain at stage boundary
    DONE_STATE = 3'b100
  } state_t;

  state_t state, next_state;

  logic [LOGN-1:0] stage_next;
  logic [CYCLE_WIDTH-1:0] cycle_next;
  
  // Counter for pipeline drain
  localparam int DRAIN_COUNT_WIDTH = $clog2(PIPELINE_DEPTH + 1);
  logic [DRAIN_COUNT_WIDTH-1:0] drain_count, drain_count_next;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      stage <= '0;
      cycle <= '0;
      drain_count <= '0;
    end else begin
      state <= next_state;
      stage <= stage_next;
      cycle <= cycle_next;
      drain_count <= drain_count_next;
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
        if (!stall && (cycle == CYCLES_PER_STAGE - 1)) begin
          if (stage == LAST_STAGE) begin
            // Last stage, last cycle - go to done (will drain via pipe_active)
            next_state = DONE_STATE;
          end else begin
            // Not last stage - need to drain pipeline before advancing
            next_state = STAGE_DRAIN;
          end
        end
      end
      STAGE_DRAIN: begin
        // Wait for pipeline to drain
        if (drain_count == 0) begin
          next_state = COMPUTE;
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
    drain_count_next = drain_count;

    case (state)
      IDLE: begin
        if (start) begin
          stage_next = '0;
          cycle_next = '0;
          drain_count_next = '0;
        end
      end
      COMPUTE: begin
        if (!stall && stage <= LAST_STAGE) begin
          if (cycle == CYCLES_PER_STAGE - 1) begin
            cycle_next = '0;
            if (stage < LAST_STAGE) begin
              // Will enter STAGE_DRAIN, set counter
              drain_count_next = DRAIN_COUNT_WIDTH'(PIPELINE_DEPTH);
            end
            // Don't advance stage yet - will happen after drain
          end else begin
            cycle_next = cycle + 1'b1;
          end
        end
      end
      STAGE_DRAIN: begin
        // Count down the drain
        if (drain_count != 0) begin
          drain_count_next = drain_count - 1'b1;
        end else begin
          // Drain complete, now advance to next stage
          stage_next = stage + 1'b1;
        end
      end
      DONE_STATE: begin
        if (!start) begin
          stage_next = '0;
          cycle_next = '0;
          drain_count_next = '0;
        end
      end
      default: begin
        stage_next = '0;
        cycle_next = '0;
        drain_count_next = '0;
      end
    endcase
  end

  always_comb begin
    busy = (state == COMPUTE) || (state == STAGE_DRAIN);
    done = (state == DONE_STATE);
    draining = (state == STAGE_DRAIN);

    butterfly = cycle * PARALLEL;

    for (int lane = 0; lane < PARALLEL; lane++) begin
      // Only issue butterflies in COMPUTE state (not during STAGE_DRAIN)
      lane_valid[lane] = ((butterfly + lane) < TOTAL_BUTTERFLIES)
                         && (state == COMPUTE)
                         && (stage <= LAST_STAGE)
                         && !stall;
    end
  end

endmodule
