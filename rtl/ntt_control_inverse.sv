`timescale 1ns / 1ps

//==============================================================================
// NTT Control FSM (Inverse, Gentlemen-Sande order)
//==============================================================================
// Runs stages from LOGN-1 down to 0.
//==============================================================================

module ntt_control_inverse #(
    parameter int N          = 256,
    parameter int ADDR_WIDTH = 8
) (
    input logic clk,
    input logic rst_n,

    // Control interface
    input  logic start,
    output logic done,
    output logic busy,

    // RAM control
    output logic [ADDR_WIDTH-1:0] ram_addr_a,
    output logic [ADDR_WIDTH-1:0] ram_addr_b,
    output logic                  ram_we_a,
    output logic                  ram_we_b,
    output logic                  ram_re,

    // Twiddle ROM control
    output logic [ADDR_WIDTH-1:0] twiddle_addr,

    // Butterfly control
    output logic butterfly_valid
);

  localparam int LOGN = $clog2(N);

  typedef enum logic [1:0] {
    IDLE    = 2'b00,
    COMPUTE = 2'b01,
    DONE    = 2'b10
  } state_t;

  state_t state, next_state;

  logic [3:0] stage;
  logic [6:0] butterfly;
  logic [1:0] cycle;

  logic [3:0] stage_next;
  logic [6:0] butterfly_next;
  logic [1:0] cycle_next;

  logic [ADDR_WIDTH-1:0] block_size;
  logic [ADDR_WIDTH-1:0] half_block;
  logic [ADDR_WIDTH-1:0] group;
  logic [ADDR_WIDTH-1:0] position;
  logic [ADDR_WIDTH-1:0] addr0, addr1;

  logic [ADDR_WIDTH-1:0] twiddle_base;
  logic [ADDR_WIDTH-1:0] t_blocks;

  always_comb begin
    half_block = ADDR_WIDTH'(1 << stage);
    block_size = ADDR_WIDTH'(1 << (stage + 1));

    group    = {1'b0, butterfly} >> stage;
    position = butterfly & (half_block - 1);

    addr0 = (group * block_size) + position;
    addr1 = addr0 + half_block;
  end

  always_comb begin
    t_blocks = ADDR_WIDTH'(1 << (LOGN - 1 - stage));
    twiddle_base = t_blocks - 1;
    twiddle_addr = twiddle_base + group;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start) next_state = COMPUTE;
      end
      COMPUTE: begin
        if (stage == LOGN - 1 && butterfly == 127 && cycle == 3) begin
          next_state = DONE;
        end
      end
      DONE: begin
        if (!start) next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stage     <= 4'b0;
      butterfly <= 7'b0;
      cycle     <= 2'b0;
    end else begin
      stage     <= stage_next;
      butterfly <= butterfly_next;
      cycle     <= cycle_next;
    end
  end

  always_comb begin
    stage_next     = stage;
    butterfly_next = butterfly;
    cycle_next     = cycle;

    case (state)
      IDLE: begin
        if (start) begin
          stage_next     = 4'b0;
          butterfly_next = 7'b0;
          cycle_next     = 2'b0;
        end
      end
      COMPUTE: begin
        if (cycle == 3) begin
          cycle_next = 2'b0;
          if (butterfly == 127) begin
            butterfly_next = 7'b0;
            if (stage != LOGN - 1) begin
              stage_next = stage + 1'b1;
            end
          end else begin
            butterfly_next = butterfly + 1'b1;
          end
        end else begin
          cycle_next = cycle + 1'b1;
        end
      end
      DONE: begin
        if (!start) begin
          stage_next     = 4'b0;
          butterfly_next = 7'b0;
          cycle_next     = 2'b0;
        end
      end
      default: begin
        stage_next     = 4'b0;
        butterfly_next = 7'b0;
        cycle_next     = 2'b0;
      end
    endcase
  end

  always_comb begin
    busy = (state == COMPUTE);
    done = (state == DONE);

    ram_addr_a = addr0;
    ram_addr_b = addr1;
    ram_we_a   = (state == COMPUTE) && (cycle == 3);
    ram_we_b   = (state == COMPUTE) && (cycle == 3);
    ram_re     = (state == COMPUTE);
    butterfly_valid = (state == COMPUTE) && (cycle == 2);
  end

endmodule
