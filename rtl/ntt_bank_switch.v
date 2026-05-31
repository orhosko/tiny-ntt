`timescale 1ns / 1ps

// Note: lane_valid_pipe port changed from unpacked array to just the tail
// element (index TOTAL_PIPE_DEPTH), since that is the only element used.

module ntt_bank_switch #(
    parameter LOGN            = 12,
    parameter PARALLEL        = 8,
    parameter MULT_PIPELINE   = 4,
    parameter TOTAL_PIPE_DEPTH = MULT_PIPELINE
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [LOGN-1:0]           stage,
    input  wire                      lane_valid_any,
    input  wire [PARALLEL-1:0]       lane_valid_last,   // = lane_valid_pipe[TOTAL_PIPE_DEPTH]
    output wire                      read_bank_sel,
    output wire                      write_bank_sel,
    output reg  [TOTAL_PIPE_DEPTH:0] write_bank_sel_pipe,
    output wire                      pipe_active
);

  assign read_bank_sel  = stage[0];
  assign write_bank_sel = ~stage[0];
  assign pipe_active    = |lane_valid_last;

  always @(posedge clk) begin
    if (!rst_n) begin
      write_bank_sel_pipe <= 0;
    end else begin
      if (lane_valid_any)
        write_bank_sel_pipe[0] <= write_bank_sel;
      write_bank_sel_pipe[TOTAL_PIPE_DEPTH:1] <= write_bank_sel_pipe[TOTAL_PIPE_DEPTH-1:0];
    end
  end

endmodule
