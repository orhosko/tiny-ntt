# Synthesis Guide

This directory contains scripts for synthesizing the NTT multiplication unit with Yosys.

## Quick Start

```bash
cd synth
make       # Synthesize design
make clean # Clean outputs
```

## Output Files

- `synth.log` - Full synthesis log with statistics
- `synth_output.v` - Synthesized Verilog netlist
- `synth_output.json` - JSON representation

## Understanding the Report

The synthesis report shows:
- **Number of cells**: Total logic cells used
- **Cell breakdown**: Types of cells (AND, OR, MUX, ADD, MUL, etc.)
- **Wires**: Number of internal connections

### Key Metrics

- **Multipliers** - Number of multiplication units
- **Adders** - Addition/subtraction logic
- **Total cells** - Overall resource usage

### Expected Differences

- **SIMPLE**: May synthesize less efficiently (depends on tool)
- **BARRETT**: More adders/shifts, explicit algorithm
- **MONTGOMERY**: Similar to Barrett, optimized for repeated ops
