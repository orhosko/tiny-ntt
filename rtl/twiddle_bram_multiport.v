`timescale 1ns / 1ps

// 2D packed ports flattened:
//   addr : [PARALLEL-1:0][ADDR_WIDTH-1:0]  ->  [PARALLEL*ADDR_WIDTH-1:0]
//   data : [PARALLEL-1:0][WIDTH-1:0]        ->  [PARALLEL*WIDTH-1:0]
// Access: port[lane] -> port[lane*W +: W]

module twiddle_bram_multiport #(
    parameter DEPTH      = 1024,
    parameter WIDTH      = 32,
    parameter PARALLEL   = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter HEX_FILE   = ""
) (
    input  wire                          clk,
    input  wire [PARALLEL*ADDR_WIDTH-1:0] addr,
    output wire [PARALLEL*WIDTH-1:0]      data
);

  localparam NUM_BRAMS = (PARALLEL + 1) / 2;

  wire [ADDR_WIDTH-1:0] addr_a_arr [0:NUM_BRAMS-1];
  wire [ADDR_WIDTH-1:0] addr_b_arr [0:NUM_BRAMS-1];
  wire [WIDTH-1:0]      data_a_arr [0:NUM_BRAMS-1];
  wire [WIDTH-1:0]      data_b_arr [0:NUM_BRAMS-1];

  genvar i;
  generate
    for (i = 0; i < NUM_BRAMS; i = i + 1) begin : gen_arr_map
      localparam LANE_A = i * 2;
      localparam LANE_B = i * 2 + 1;

      assign addr_a_arr[i] = addr[LANE_A*ADDR_WIDTH +: ADDR_WIDTH];

      if (LANE_B < PARALLEL) begin : gen_lane_b_valid
        assign addr_b_arr[i] = addr[LANE_B*ADDR_WIDTH +: ADDR_WIDTH];
      end else begin : gen_lane_b_zero
        assign addr_b_arr[i] = {ADDR_WIDTH{1'b0}};
      end

      assign data[LANE_A*WIDTH +: WIDTH] = data_a_arr[i];

      if (LANE_B < PARALLEL) begin : gen_data_b_valid
        assign data[LANE_B*WIDTH +: WIDTH] = data_b_arr[i];
      end
    end
  endgenerate

  generate
    for (i = 0; i < NUM_BRAMS; i = i + 1) begin : gen_brams
      twiddle_bram #(
          .WIDTH             (WIDTH),
          .DEPTH             (DEPTH),
          .ADDR_WIDTH        (ADDR_WIDTH),
          .HEX_FILE          (HEX_FILE),
          .OUTPUT_PIPE_STAGES(OUTPUT_PIPE_STAGES)
      ) u_bram (
          .clk   (clk),
          .addr_a(addr_a_arr[i]),
          .data_a(data_a_arr[i]),
          .addr_b(addr_b_arr[i]),
          .data_b(data_b_arr[i])
      );
    end
  endgenerate

endmodule
