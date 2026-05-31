# Tiny NTT

Tiny NTT is a configurable RTL implementation of an NTT-based negacyclic
polynomial multiplication accelerator. The design is intended for
lattice-cryptography-style workloads and includes forward NTT execution,
transform-domain pointwise multiplication, inverse NTT execution, coefficient
storage, twiddle-factor storage, butterfly units, and modular arithmetic blocks.

The project also includes software benchmarks, RocketChip/RoCC integration
experiments, FPGA implementation results, and an ASIC-oriented physical-design
flow for the accelerator block.

## Repository Layout

```text
tiny-ntt/
├── rtl/                  # Verilog/SystemVerilog accelerator RTL and twiddle files
├── test/                 # Simulation testbench files
├── new_reference/        # Python reference models for CG NTT behavior
├── software_benchmark/   # C++ scalar, AVX2, and AVX-512 software benchmarks
├── chipyard/             # RocketChip/RoCC wrapper and C test material
├── synth/                # Yosys synthesis scripts and outputs
├── librelane/            # ASIC-oriented accelerator flow configuration
├── scripts/              # Twiddle and modular-constant generation helpers
└── reports/              # Interim/final report source, figures, and bibliography
```

## Main RTL

The main accelerator source is in `rtl/`. Important blocks include:

- `ntt_poly_mult.sv`: top-level polynomial multiplication accelerator.
- `ntt_forward.sv` and `ntt_inverse.sv`: transform engines.
- `ntt_coeff_banks.v`: banked coefficient storage.
- `ntt_cg_address_gen.v`: constant-geometry address generation.
- `ntt_butterfly.v`: butterfly datapath.
- `mod_mult.v`, `barrett_mult.v`, `barrett_reduction.v`: modular multiplication path.
- `twiddle_bram_multiport.v`: multiport twiddle access.

The current hardware-oriented path uses Barrett reduction, banked
constant-geometry coefficient storage, and precomputed forward/inverse twiddle
files. Montgomery reduction was explored earlier, but Barrett is the main path
used for the reported hardware versions.

## Software Benchmarks

The C++ benchmark suite compares direct polynomial multiplication and NTT-based
software multiplication for scalar, AVX2, and AVX-512 builds.

```sh
cd software_benchmark
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

See `software_benchmark/README.md` for the exact benchmark commands, including
the 24-bit and 60-bit configurations.

## Simulation and Integration

The accelerator was tested against Python reference models and simulation
testbenches. The processor-facing path was also exercised through Chipyard and
Verilator using C tests that invoke the accelerator through RoCC custom
instructions.

Relevant directories:

- `test/`: standalone accelerator test material.
- `new_reference/`: Python reference models.
- `chipyard/`: RoCC wrapper and C-level invocation examples.

## Synthesis, FPGA, and ASIC Flow

The project includes both FPGA-oriented and ASIC-oriented implementation work.

- `synth/` contains Yosys synthesis scripts.
- FPGA implementation results are documented in `reports/final-report.tex`.
- `librelane/` contains the accelerator-only ASIC-oriented flow configuration.

The ASIC-oriented path uses SRAM-aware top-level handling. The SRAM22 Sky130
macros used in this direction are 1RW SRAMs, so the ASIC top level has different
state sequencing from the FPGA BRAM-oriented version.

## Reports

The main writeup is in:

```text
reports/final-report.tex
```

It describes the architecture, literature comparison, verification flow,
software benchmarks, FPGA resource/timing results, RocketChip integration, and
ASIC-oriented layout output.
