# Makefile for cocotb-based NTT multiplication testbench

# Simulator selection
SIM ?= icarus

# Testbench module (will be overridden by test targets)
COCOTB_TEST_MODULES ?= cocotb_tests.test_ntt_mult

# Top-level module (will be overridden by test targets)
TOPLEVEL ?= ntt_pointwise_mult

# Verilog sources (will be overridden by test targets)
# Note: Do not set default sources - use explicit test targets below

# Language
TOPLEVEL_LANG = verilog

# Disable waveform dumping by default (enable with WAVES=1 if needed)
WAVES ?= 0
export WAVES

export PYTHONPATH := $(PWD):$(PYTHONPATH)

ifeq ($(SIM),icarus)
    COMPILE_ARGS += -g2012  # Enable SystemVerilog support
endif

ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing
    COMPILE_ARGS += --trace
    COMPILE_ARGS += --trace-structs
endif

# Include cocotb makefiles
include $(shell cocotb-config --makefiles)/Makefile.sim

# Default target - show help
.DEFAULT_GOAL := help

# Test targets
.PHONY: help test-mod-add test-mod-sub test-ntt-mult test-all clean

help:
	@echo "Available test targets:"
	@echo "  make test-mod-add      - Test modular adder"
	@echo "  make test-mod-sub      - Test modular subtractor"
	@echo "  make test-butterfly    - Test NTT butterfly unit"
	@echo "  make test-twiddle-rom  - Test twiddle factor ROM"
	@echo "  make test-coeff-ram    - Test coefficient RAM"
	@echo "  make test-ntt-mult     - Test NTT pointwise multiplication"
	@echo "  make test-ntt-control  - Test NTT control FSM"
	@echo "  make test-ntt-poly     - Test NTT polynomial multiply"
	@echo "  make test-all          - Run all tests"
	@echo "  make clean             - Clean build artifacts"
	@echo ""
	@echo "Optional: SIM=verilator (default: icarus)"

# Test modular adder
test-mod-add: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing modular adder (mod_add)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_mod_add \
		TOPLEVEL=mod_add \
		VERILOG_SOURCES=$(PWD)/../rtl/mod_add.sv \
		sim

# Test modular subtractor  
test-mod-sub: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing modular subtractor (mod_sub)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_mod_sub \
		TOPLEVEL=mod_sub \
		VERILOG_SOURCES=$(PWD)/../rtl/mod_sub.sv \
		sim

# Test NTT butterfly
test-butterfly: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT butterfly unit"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_butterfly \
		TOPLEVEL=ntt_butterfly \
		VERILOG_SOURCES="$(PWD)/../rtl/mod_add.sv $(PWD)/../rtl/mod_sub.sv $(PWD)/../rtl/barrett_reduction.sv $(PWD)/../rtl/montgomery_reduction.sv $(PWD)/../rtl/mod_mult.sv $(PWD)/../rtl/ntt_butterfly.sv" \
		sim

# Test inverse butterfly unit
test-butterfly-inverse: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing Inverse NTT Butterfly Unit"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_butterfly_inverse \
		TOPLEVEL=ntt_butterfly_inverse \
		VERILOG_SOURCES="$(PWD)/../rtl/mod_add.sv $(PWD)/../rtl/mod_sub.sv $(PWD)/../rtl/barrett_reduction.sv $(PWD)/../rtl/montgomery_reduction.sv $(PWD)/../rtl/mod_mult.sv $(PWD)/../rtl/ntt_butterfly_inverse.sv" \
		sim

# Test twiddle ROM
test-twiddle-rom: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing twiddle factor ROM"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_twiddle_rom \
		TOPLEVEL=twiddle_rom \
		VERILOG_SOURCES="$(PWD)/../rtl/twiddle_rom.sv" \
		sim

# Test coefficient RAM
test-coeff-ram: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing coefficient RAM"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_coeff_ram \
		TOPLEVEL=coeff_ram \
		VERILOG_SOURCES="$(PWD)/../rtl/coeff_ram.sv" \
		sim

# Test NTT pointwise multiplication
test-ntt-mult: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT pointwise multiplication"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_mult \
		TOPLEVEL=ntt_pointwise_mult \
		VERILOG_SOURCES="$(PWD)/../rtl/barrett_reduction.sv $(PWD)/../rtl/montgomery_reduction.sv $(PWD)/../rtl/mod_mult.sv $(PWD)/../rtl/ntt_pointwise_mult.sv" \
		sim

# Test NTT control FSM
test-ntt-control: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT control FSM"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_control \
		TOPLEVEL=ntt_control \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_control.sv" \
		sim

# Test NTT polynomial multiply
test-ntt-poly: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT Polynomial Multiply (Top Level)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_poly_mult \
		TOPLEVEL=ntt_poly_mult \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_poly_mult.sv $(PWD)/../rtl/ntt_forward.sv $(PWD)/../rtl/ntt_control_parallel.sv $(PWD)/../rtl/ntt_control.sv $(PWD)/../rtl/ntt_inverse.sv $(PWD)/../rtl/ntt_control_inverse.sv $(PWD)/../rtl/twiddle_rom.sv $(PWD)/../rtl/inverse_twiddle_rom.sv $(PWD)/../rtl/coeff_ram.sv $(PWD)/../rtl/ntt_butterfly.sv $(PWD)/../rtl/ntt_butterfly_inverse.sv $(PWD)/../rtl/mod_mult.sv $(PWD)/../rtl/mod_add.sv $(PWD)/../rtl/mod_sub.sv $(PWD)/../rtl/barrett_reduction.sv $(PWD)/../rtl/montgomery_reduction.sv" \
		sim

# Test NTT forward (full integration)
test-ntt-forward: clean

	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT Forward Transform (Full Integration)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_forward \
		TOPLEVEL=ntt_forward \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_forward.sv $(PWD)/../rtl/ntt_control_parallel.sv $(PWD)/../rtl/ntt_control.sv $(PWD)/../rtl/twiddle_rom.sv $(PWD)/../rtl/ntt_butterfly.sv $(PWD)/../rtl/mod_mult.sv $(PWD)/../rtl/mod_add.sv $(PWD)/../rtl/mod_sub.sv $(PWD)/../rtl/barrett_reduction.sv $(PWD)/../rtl/montgomery_reduction.sv" \
		sim

# Run all tests
test-all: clean
	@echo ""
	@echo "======================================================================"
	@echo " Running all tests"
	@echo "======================================================================"
	@$(MAKE) test-mod-add
	@echo ""
	@$(MAKE) test-mod-sub
	@echo ""
	@$(MAKE) test-butterfly
	@echo ""
	@$(MAKE) test-butterfly-inverse
	@echo ""
	@$(MAKE) test-twiddle-rom
	@echo ""
	@$(MAKE) test-coeff-ram
	@echo ""
	@$(MAKE) test-ntt-mult
	@echo ""
	@$(MAKE) test-ntt-control
	@echo ""
	@$(MAKE) test-ntt-forward
	@echo ""
	@$(MAKE) test-ntt-poly
	@echo ""
	@$(MAKE) test-ntt-inverse
	@echo ""
	@$(MAKE) test-intt-unit
	@echo ""
	@echo "======================================================================"
	@echo " All tests completed!"
	@echo "======================================================================"

# Testing NTT Inverse Transform
test-ntt-inverse: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT Inverse Transform (INTT)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_inverse \
		TOPLEVEL=ntt_inverse \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_inverse.sv $(PWD)/../rtl/ntt_control_inverse.sv $(PWD)/../rtl/ntt_control.sv $(PWD)/../rtl/coeff_ram.sv $(PWD)/../rtl/inverse_twiddle_rom.sv $(PWD)/../rtl/ntt_butterfly_inverse.sv $(PWD)/../rtl/mod_mult.sv $(PWD)/../rtl/mod_add.sv $(PWD)/../rtl/mod_sub.sv $(PWD)/../rtl/barrett_reduction.sv $(PWD)/../rtl/montgomery_reduction.sv" \
		sim

# INTT unit tests with known data
test-intt-unit: clean
	@echo ""
	@echo "======================================================================"
	@echo " INTT Unit Tests - Known Data"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_intt_unit \
		TOPLEVEL=ntt_inverse \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_inverse.sv $(PWD)/../rtl/ntt_control_inverse.sv $(PWD)/../rtl/ntt_control.sv $(PWD)/../rtl/coeff_ram.sv $(PWD)/../rtl/inverse_twiddle_rom.sv $(PWD)/../rtl/ntt_butterfly_inverse.sv $(PWD)/../rtl/mod_mult.sv $(PWD)/../rtl/mod_add.sv $(PWD)/../rtl/mod_sub.sv $(PWD)/../rtl/barrett_reduction.sv $(PWD)/../rtl/montgomery_reduction.sv" \
		sim

# Clean target
clean::
	rm -rf __pycache__
	rm -rf sim_build
	rm -f results.xml
	rm -f *.vcd
