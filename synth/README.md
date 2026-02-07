# Synthesis Guide

This directory contains scripts for synthesizing the NTT multiplication unit with Yosys.

## Quick Start

```bash
cd synth
make synth-all    # Synthesize all three reduction methods
```

## Individual Synthesis

```bash
make synth-simple      # REDUCTION_TYPE=0 (SIMPLE)
make synth-barrett     # REDUCTION_TYPE=1 (BARRETT)
make synth-montgomery  # REDUCTION_TYPE=2 (MONTGOMERY)
```

## View Results

```bash
make report  # Display synthesis statistics comparison
```

## Output Files

- `synth_simple.log` - Full synthesis log for SIMPLE reduction
- `synth_barrett.log` - Full synthesis log for BARRETT reduction
- `synth_montgomery.log` - Full synthesis log for MONTGOMERY reduction
- `synth_output.v` - Synthesized Verilog netlist (last run)
- `synth_output.json` - JSON representation (last run)

## Understanding the Report

The synthesis report shows:
- **Number of cells**: Total logic cells used
- **Cell breakdown**: Types of cells (AND, OR, MUX, ADD, MUL, etc.)
- **Wires**: Number of internal connections

### Key Metrics to Compare

1. **Multipliers** - Number of multiplication units
2. **Adders** - Addition/subtraction logic
3. **Total cells** - Overall resource usage

Expected differences:
- **SIMPLE**: Uses modulo operator (may synthesize inefficiently)
- **BARRETT**: More adders/shifts, fewer special operations
- **MONTGOMERY**: Similar to Barrett, optimized for repeated ops

## Synthesis for Specific FPGA

To target a specific FPGA family (e.g., Xilinx, Intel):

```bash
# Edit synth.ys and replace 'techmap' with FPGA-specific synth command
# For Xilinx:
yosys -p "synth_xilinx -top ntt_pointwise_mult" ...

# For Intel/Altera:
yosys -p "synth_intel -top ntt_pointwise_mult" ...
```

## Clean

```bash
make clean  # Remove all synthesis outputs and logs
```
