`timescale 1ns / 1ps

module ntt_control_parallel #(
    parameter N              = 4096,
    parameter PARALLEL       = 8,
    parameter PIPELINE_DEPTH = 3
) (
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire stall,
    output reg  done,
    output reg  busy,
    output reg  draining,

    output reg  [$clog2(N)-1:0]   stage,
    output reg  [$clog2(N/2)-1:0] butterfly,
    output reg  [$clog2(N/2)-1:0] cycle,
    output reg  [PARALLEL-1:0]    lane_valid
);

  localparam LOGN             = $clog2(N);
  localparam LAST_STAGE       = LOGN - 1;
  localparam TOTAL_BUTTERFLIES = N / 2;
  localparam CYCLES_PER_STAGE = (TOTAL_BUTTERFLIES + PARALLEL - 1) / PARALLEL;
  localparam CYCLE_WIDTH      = $clog2(CYCLES_PER_STAGE == 0 ? 1 : CYCLES_PER_STAGE);
  localparam DRAIN_COUNT_WIDTH = $clog2(PIPELINE_DEPTH + 1);

  // State encoding (replaces typedef enum)
  localparam [2:0] IDLE        = 3'b000;
  localparam [2:0] COMPUTE     = 3'b001;
  localparam [2:0] STAGE_DRAIN = 3'b010;
  localparam [2:0] DONE_STATE  = 3'b100;

  reg [2:0] state, next_state;

  reg [LOGN-1:0]           stage_next;
  reg [CYCLE_WIDTH-1:0]    cycle_next;
  reg [DRAIN_COUNT_WIDTH-1:0] drain_count, drain_count_next;

  integer lane;

  always @(posedge clk) begin
    if (!rst_n) begin
      state       <= IDLE;
      stage       <= 0;
      cycle       <= 0;
      drain_count <= 0;
    end else begin
      state       <= next_state;
      stage       <= stage_next;
      cycle       <= cycle_next;
      drain_count <= drain_count_next;
    end
  end

  always @(*) begin
    next_state = state;
    case (state)
      IDLE: begin
        if (start) next_state = COMPUTE;
      end
      COMPUTE: begin
        if (!stall && (cycle == CYCLES_PER_STAGE - 1)) begin
          if (stage == LAST_STAGE) next_state = DONE_STATE;
          else                     next_state = STAGE_DRAIN;
        end
      end
      STAGE_DRAIN: begin
        if (drain_count == 0) next_state = COMPUTE;
      end
      DONE_STATE: begin
        if (!start) next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  always @(*) begin
    stage_next       = stage;
    cycle_next       = cycle;
    drain_count_next = drain_count;

    case (state)
      IDLE: begin
        if (start) begin
          stage_next       = 0;
          cycle_next       = 0;
          drain_count_next = 0;
        end
      end
      COMPUTE: begin
        if (!stall && stage <= LAST_STAGE) begin
          if (cycle == CYCLES_PER_STAGE - 1) begin
            cycle_next = 0;
            if (stage < LAST_STAGE)
              drain_count_next = PIPELINE_DEPTH[DRAIN_COUNT_WIDTH-1:0];
          end else begin
            cycle_next = cycle + 1'b1;
          end
        end
      end
      STAGE_DRAIN: begin
        if (drain_count != 0)
          drain_count_next = drain_count - 1'b1;
        else
          stage_next = stage + 1'b1;
      end
      DONE_STATE: begin
        if (!start) begin
          stage_next       = 0;
          cycle_next       = 0;
          drain_count_next = 0;
        end
      end
      default: begin
        stage_next       = 0;
        cycle_next       = 0;
        drain_count_next = 0;
      end
    endcase
  end

  always @(*) begin
    busy     = (state == COMPUTE) || (state == STAGE_DRAIN);
    done     = (state == DONE_STATE);
    draining = (state == STAGE_DRAIN);

    butterfly = cycle * PARALLEL;

    for (lane = 0; lane < PARALLEL; lane = lane + 1) begin
      lane_valid[lane] = ((butterfly + lane) < TOTAL_BUTTERFLIES)
                         && (state == COMPUTE)
                         && (stage <= LAST_STAGE)
                         && !stall;
    end
  end

endmodule
