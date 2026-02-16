`timescale 1ns / 1ps

//==============================================================================
// NTT Control FSM
//==============================================================================
// Controls the NTT computation pipeline for N=256 radix-2 Cooley-Tukey
//
// Features:
//   - 3-state FSM: IDLE → COMPUTE → DONE
//   - Address generation for in-place Cooley-Tukey algorithm
//   - Twiddle factor address calculation
//   - RAM and butterfly control signals
//
// Algorithm:
//   - 8 stages (log₂ 256)
//   - 128 butterflies per stage (N/2)
//   - Total: 1024 butterfly operations
//==============================================================================

module ntt_control #(
    parameter int N          = 256,  // NTT size
    parameter int ADDR_WIDTH = 8,     // log₂(N)
    parameter bit INVERSE    = 1'b0,  // 0=forward, 1=inverse (GS)
    parameter bit DIF        = 1'b0   // 0=DIT, 1=DIF forward
) (
    input logic clk,
    input logic rst_n,

    // Control interface
    input  logic start,  // Start NTT computation
    output logic done,   // Computation complete
    output logic busy,   // Currently computing

    // RAM control
    output logic [ADDR_WIDTH-1:0] ram_addr_a,  // Coefficient pair address A
    output logic [ADDR_WIDTH-1:0] ram_addr_b,  // Coefficient pair address B
    output logic                  ram_we_a,    // Write enable A
    output logic                  ram_we_b,    // Write enable B
    output logic                  ram_re,      // Read enable (for both ports)

    // Twiddle ROM control
    output logic [ADDR_WIDTH-1:0] twiddle_addr,  // Twiddle factor address

    // Butterfly control
    output logic butterfly_valid  // Butterfly computation valid
);

  //============================================================================
  // FSM States
  //============================================================================
  typedef enum logic [1:0] {
    IDLE    = 2'b00,
    COMPUTE = 2'b01,
    DONE    = 2'b10
  } state_t;

  state_t state, next_state;

  //============================================================================
  // Counters and Registers
  //============================================================================
  logic [           3:0] stage;  // Current stage (0-8, needs 4 bits for value 8)
  logic [           6:0] butterfly;  // Current butterfly in stage (0-127)
  logic [           1:0] cycle;  // Timing cycle within butterfly (0-3)

  logic [           3:0] stage_next;
  logic [           6:0] butterfly_next;
  logic [           1:0] cycle_next;

  //============================================================================
  // Address Generation Logic
  //============================================================================
  // For Cooley-Tukey radix-2 in-place NTT:
  // Stage s, Butterfly b:
  //   block_size = 2^(s+1)
  //   group = b / 2^s
  //   position = b % 2^s
  //   addr0 = group * 2^(s+1) + position
  //   addr1 = addr0 + 2^s

  logic [ADDR_WIDTH-1:0] block_size;  // 2^(s+1)
  logic [ADDR_WIDTH-1:0] half_block;  // 2^s
  logic [ADDR_WIDTH-1:0] group;
  logic [ADDR_WIDTH-1:0] position;
  logic [ADDR_WIDTH-1:0] addr0, addr1;

  always_comb begin
    if (DIF) begin
      half_block = ADDR_WIDTH'(N >> (stage + 1));
      block_size = ADDR_WIDTH'(N >> stage);

      group    = {1'b0, butterfly} >> (ADDR_WIDTH - stage - 1);
      position = butterfly & (half_block - 1);
    end else begin
      half_block = ADDR_WIDTH'(1 << stage);
      block_size = ADDR_WIDTH'(1 << (stage + 1));

      group    = {1'b0, butterfly} >> stage;  // butterfly / 2^stage
      position = butterfly & (half_block - 1);  // butterfly % 2^stage
    end

    addr0 = (group * block_size) + position;
    addr1 = addr0 + half_block;
  end

  //============================================================================
  // Twiddle Address Calculation
  //============================================================================
  // Forward (CT): twiddle_addr = (b % 2^s) * 2^(log₂N - s - 1)
  // Inverse (GS): twiddle_addr = bit_reverse(2^(log₂N - s - 1) + (b / 2^s))

  logic [ADDR_WIDTH-1:0] twiddle_multiplier;
  logic [ADDR_WIDTH-1:0] twiddle_index;
  logic [ADDR_WIDTH-1:0] twiddle_input;

  function automatic [ADDR_WIDTH-1:0] bit_reverse(input logic [ADDR_WIDTH-1:0] value);
    automatic logic [ADDR_WIDTH-1:0] reversed;
    for (int i = 0; i < ADDR_WIDTH; i++) begin
      reversed[i] = value[ADDR_WIDTH - 1 - i];
    end
    return reversed;
  endfunction

  always_comb begin
    twiddle_multiplier = ADDR_WIDTH'(1 << (ADDR_WIDTH - stage - 1));
    if (INVERSE) begin
      twiddle_index = group;  // k = butterfly / 2^stage
      twiddle_input = twiddle_multiplier + twiddle_index;
      twiddle_addr = bit_reverse(twiddle_input);
    end else if (DIF) begin
      twiddle_index = group;  // k = butterfly / (N / 2^(stage+1))
      twiddle_input = ADDR_WIDTH'(1 << stage) + twiddle_index;
      twiddle_addr = bit_reverse(twiddle_input);
    end else begin
      twiddle_index = butterfly & (half_block - 1);  // butterfly % 2^stage
      twiddle_addr = twiddle_index * twiddle_multiplier;
    end
  end

  //============================================================================
  // FSM State Register
  //============================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  //============================================================================
  // FSM Next State Logic
  //============================================================================
  always_comb begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start) next_state = COMPUTE;
      end

      COMPUTE: begin
        // Check if all stages complete (stages 0-7 done, now at stage 8)
        if (stage >= 8) begin
          next_state = DONE;
        end
      end

      DONE: begin
        if (!start) next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  //============================================================================
  // Counter Logic
  //============================================================================
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
    // Default: keep current values
    stage_next     = stage;
    butterfly_next = butterfly;
    cycle_next     = cycle;

    case (state)
      IDLE: begin
        if (start) begin
          // Initialize counters
          stage_next     = 4'b0;
          butterfly_next = 7'b0;
          cycle_next     = 2'b0;
        end
      end

      COMPUTE: begin
        // Stop advancing if we've completed all stages
        if (stage >= 8) begin
          // Freeze counters, wait for state transition to DONE
          stage_next = stage;
          butterfly_next = butterfly;
          cycle_next = cycle;
        end else begin
          // Advance cycle
          if (cycle == 3) begin
            cycle_next = 2'b0;

            // Advance butterfly
            if (butterfly == 127) begin
              butterfly_next = 7'b0;

              // Advance stage
              stage_next = stage + 1;
            end else begin
              butterfly_next = butterfly + 1;
            end
          end else begin
            cycle_next = cycle + 1;
          end
        end
      end

      DONE: begin
        // Reset counters
        stage_next     = 4'b0;
        butterfly_next = 7'b0;
        cycle_next     = 2'b0;
      end
    endcase
  end

  //============================================================================
  // Output Control Signals
  //============================================================================
  always_comb begin
    // Defaults
    ram_addr_a      = addr0;
    ram_addr_b      = addr1;
    ram_we_a        = 1'b0;
    ram_we_b        = 1'b0;
    ram_re          = 1'b0;
    butterfly_valid = 1'b0;
    done            = 1'b0;
    busy            = 1'b0;

    case (state)
      IDLE: begin
        done = 1'b0;
        busy = 1'b0;
      end

      COMPUTE: begin
        busy = 1'b1;

        case (cycle)
          2'b00: begin  // Cycle 0: Set addresses
            ram_re = 1'b1;
          end

          2'b01: begin  // Cycle 1: RAM outputs valid
            ram_re = 1'b1;
          end

          2'b10: begin  // Cycle 2: Butterfly compute
            butterfly_valid = 1'b1;
          end

          2'b11: begin  // Cycle 3: Write back
            ram_we_a = 1'b1;
            ram_we_b = 1'b1;
          end
        endcase
      end

      DONE: begin
        done = 1'b1;
        busy = 1'b0;
      end
    endcase
  end

endmodule
