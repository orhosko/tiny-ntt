# Tiny NTT - NTT Multiplication Unit

A high-performance SystemVerilog implementation of a Number Theoretic Transform (NTT) pointwise multiplication unit, designed for post-quantum cryptography applications (Kyber/Dilithium).

## Directory Structure

```
tiny-ntt/
├── rtl/
│   ├── barrett_reduction.sv         # Barrett reduction algorithm
│   ├── montgomery_reduction.sv      # Montgomery reduction algorithm
│   ├── mod_mult.sv                  # Configurable modular multiplier
│   └── ntt_pointwise_mult.sv        # Top-level NTT multiplication unit
├── scripts/
│   └── precompute_constants.py      # Compute Barrett/Montgomery constants
├── synth/
│   ├── synth.ys                     # Yosys synthesis script
│   └── Makefile                     # Synthesis makefile
├── test/
│   ├── test_ntt_mult.py             # Cocotb testbench
│   └── Makefile                     # Simulation makefile
├── flake.nix                        # Nix development environment
└── README.md                        # This file
```

## Getting Started

### Prerequisites

- Python 3.7+
- cocotb (`pip install cocotb`)
- A Verilog/SystemVerilog simulator:
  - Icarus Verilog (`sudo apt install iverilog`) **recommended for quick start**
  - Verilator (`sudo apt install verilator`)

### Running Tests

1. Navigate to the test directory:
```bash
cd test
```

2. Run the cocotb testbench:
```bash
make
```

3. For Verilator (with waveform generation):
```bash
make SIM=verilator
```

4. View waveforms (if generated):
```bash
gtkwave ntt_pointwise_mult.vcd
```