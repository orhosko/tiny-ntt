`timescale 1ns / 1ps

//==============================================================================
// Bank Selection and Pipeline Alignment
//==============================================================================

module ntt_bank_switch #(
    parameter int LOGN = 8,
    parameter int PARALLEL = 8,
    parameter int MULT_PIPELINE = 3,
    parameter int TOTAL_PIPE_DEPTH = MULT_PIPELINE  // Total pipeline depth (mult + BRAM latency)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [LOGN-1:0] stage,
    input  logic lane_valid_any,
    input  logic [PARALLEL-1:0] lane_valid_pipe [0:TOTAL_PIPE_DEPTH],
    output logic read_bank_sel,
    output logic write_bank_sel,
    output logic [TOTAL_PIPE_DEPTH:0] write_bank_sel_pipe,  // Packed array for pipeline
    output logic pipe_active
);

  assign read_bank_sel = stage[0];
  assign write_bank_sel = ~stage[0];
  assign pipe_active = |lane_valid_pipe[TOTAL_PIPE_DEPTH];

  // Pipeline write_bank_sel to match lane_valid_pipe latency
  // Using packed array for better simulator compatibility
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      write_bank_sel_pipe <= '0;
    end else begin
      // Capture current write_bank_sel when issuing new butterflies
      if (lane_valid_any) begin
        write_bank_sel_pipe[0] <= write_bank_sel;
      end
      // Always shift the pipeline to match lane_valid_pipe behavior
      write_bank_sel_pipe[TOTAL_PIPE_DEPTH:1] <= write_bank_sel_pipe[TOTAL_PIPE_DEPTH-1:0];
    end
  end

endmodule
