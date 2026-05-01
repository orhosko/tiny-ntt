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

export PYTHONPATH := $(CURDIR):$(PYTHONPATH)
TWIDDLE_FORWARD_SRC ?= $(CURDIR)/../rtl/twiddle_forward_4096.hex
TWIDDLE_INVERSE_SRC ?= $(CURDIR)/../rtl/twiddle_inverse_4096.hex
NTT_PARAM_ARGS ?=

ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing
    COMPILE_ARGS += --trace
    COMPILE_ARGS += --trace-structs
endif

# Include cocotb makefiles
include $(shell cocotb-config --makefiles)/Makefile.sim

# Default target - show help
.DEFAULT_GOAL := help

# Copy twiddle hex files from rtl directory (needed for BRAM simulation)
.PHONY: copy-hex-files
copy-hex-files:
	@rm -f $(CURDIR)/twiddle_forward.hex $(CURDIR)/twiddle_inverse.hex \
		$(CURDIR)/twiddle_forward_1024.hex $(CURDIR)/twiddle_inverse_1024.hex \
		$(CURDIR)/twiddle_forward_4096.hex $(CURDIR)/twiddle_inverse_4096.hex
	@cp -f $(TWIDDLE_FORWARD_SRC) $(CURDIR)/$(notdir $(TWIDDLE_FORWARD_SRC)) 2>/dev/null || true
	@cp -f $(TWIDDLE_INVERSE_SRC) $(CURDIR)/$(notdir $(TWIDDLE_INVERSE_SRC)) 2>/dev/null || true
	@cp -f $(TWIDDLE_FORWARD_SRC) $(CURDIR)/twiddle_forward.hex 2>/dev/null || true
	@cp -f $(TWIDDLE_INVERSE_SRC) $(CURDIR)/twiddle_inverse.hex 2>/dev/null || true
	@cp -f $(TWIDDLE_FORWARD_SRC) $(CURDIR)/twiddle_forward_1024.hex 2>/dev/null || true
	@cp -f $(TWIDDLE_INVERSE_SRC) $(CURDIR)/twiddle_inverse_1024.hex 2>/dev/null || true
	@cp -f $(TWIDDLE_FORWARD_SRC) $(CURDIR)/twiddle_forward_4096.hex 2>/dev/null || true
	@cp -f $(TWIDDLE_INVERSE_SRC) $(CURDIR)/twiddle_inverse_4096.hex 2>/dev/null || true

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
	@echo "  make test-all-1024     - Run the full test suite with 1024-point NTT integration tests"
	@echo "  make test-all-4096     - Run the full test suite with 4096-point NTT integration tests"
	@echo "  make test-ntt-control-1024 - Test NTT control FSM with N=1024"
	@echo "  make test-ntt-control-4096 - Test NTT control FSM with N=4096"
	@echo "  make test-ntt-forward-1024 - Test NTT forward transform with N=1024"
	@echo "  make test-ntt-inverse-1024 - Test NTT inverse transform with N=1024"
	@echo "  make test-ntt-poly-1024    - Test NTT polynomial multiply with N=1024"
	@echo "  make test-ntt-forward-4096 - Test NTT forward transform with N=4096"
	@echo "  make test-ntt-inverse-4096 - Test NTT inverse transform with N=4096"
	@echo "  make test-ntt-poly-4096    - Test NTT polynomial multiply with N=4096"
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
		VERILOG_SOURCES=$(PWD)/../rtl/mod_add.v \
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
		VERILOG_SOURCES=$(PWD)/../rtl/mod_sub.v \
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
		VERILOG_SOURCES="$(PWD)/../rtl/mod_add.v $(PWD)/../rtl/mod_sub.v $(PWD)/../rtl/barrett_reduction.v $(PWD)/../rtl/montgomery_reduction.v $(PWD)/../rtl/mod_mult.v $(PWD)/../rtl/ntt_butterfly.v" \
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
		VERILOG_SOURCES="$(PWD)/../rtl/mod_add.v $(PWD)/../rtl/mod_sub.v $(PWD)/../rtl/barrett_reduction.v $(PWD)/../rtl/montgomery_reduction.v $(PWD)/../rtl/mod_mult.v $(PWD)/../rtl/ntt_butterfly_inverse.v" \
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
		VERILOG_SOURCES="$(PWD)/../rtl/twiddle_rom.v" \
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
		VERILOG_SOURCES="$(PWD)/../rtl/coeff_ram.v" \
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
		VERILOG_SOURCES="$(PWD)/../rtl/barrett_reduction.v $(PWD)/../rtl/montgomery_reduction.v $(PWD)/../rtl/mod_mult.v $(PWD)/../rtl/ntt_pointwise_mult.v" \
		sim

# Test NTT control FSM
test-ntt-control: clean
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT control FSM"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_control \
		TOPLEVEL=ntt_control_parallel \
		COMPILE_ARGS='$(COMPILE_ARGS) $(NTT_PARAM_ARGS)' \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_control_parallel.v" \
		sim

# Test NTT polynomial multiply
test-ntt-poly: clean copy-hex-files
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT Polynomial Multiply (Top Level)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_poly_mult \
		TOPLEVEL=ntt_poly_mult \
		COMPILE_ARGS='$(COMPILE_ARGS) $(NTT_PARAM_ARGS)' \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_poly_mult.sv $(PWD)/../rtl/coeff_ram.v $(PWD)/../rtl/ntt_forward.sv $(PWD)/../rtl/ntt_coeff_banks.v $(PWD)/../rtl/ntt_coeff_bank_single.v $(PWD)/../rtl/ntt_cg_address_gen.v $(PWD)/../rtl/twiddle_bram.v $(PWD)/../rtl/twiddle_bram_multiport.v $(PWD)/../rtl/ntt_bank_switch.v $(PWD)/../rtl/ntt_control_parallel.v $(PWD)/../rtl/ntt_inverse.sv $(PWD)/../rtl/ntt_pointwise_mult.v $(PWD)/../rtl/twiddle_rom.v $(PWD)/../rtl/ntt_butterfly.v $(PWD)/../rtl/ntt_butterfly_inverse.v $(PWD)/../rtl/mod_mult.v $(PWD)/../rtl/mod_add.v $(PWD)/../rtl/mod_sub.v $(PWD)/../rtl/barrett_reduction.v $(PWD)/../rtl/montgomery_reduction.v" \
		sim

# Test NTT forward (full integration)
test-ntt-forward: clean copy-hex-files
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT Forward Transform (Full Integration)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_forward \
		TOPLEVEL=ntt_forward \
		COMPILE_ARGS='$(COMPILE_ARGS) $(NTT_PARAM_ARGS)' \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_forward.sv $(PWD)/../rtl/ntt_coeff_banks.v $(PWD)/../rtl/ntt_coeff_bank_single.v $(PWD)/../rtl/ntt_cg_address_gen.v $(PWD)/../rtl/twiddle_bram.v $(PWD)/../rtl/twiddle_bram_multiport.v $(PWD)/../rtl/ntt_bank_switch.v $(PWD)/../rtl/ntt_control_parallel.v $(PWD)/../rtl/twiddle_rom.v $(PWD)/../rtl/ntt_butterfly.v $(PWD)/../rtl/mod_mult.v $(PWD)/../rtl/mod_add.v $(PWD)/../rtl/mod_sub.v $(PWD)/../rtl/barrett_reduction.v $(PWD)/../rtl/montgomery_reduction.v" \
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
	@$(MAKE) test-twiddle-rom
	@echo ""
	@$(MAKE) test-coeff-ram
	@echo ""
	@$(MAKE) test-butterfly
	@echo ""
	@$(MAKE) test-butterfly-inverse
	@echo ""
	@$(MAKE) test-ntt-mult
	@echo ""
	@$(MAKE) test-ntt-control
	@echo ""
	@$(MAKE) test-ntt-inverse
	@echo ""
	@$(MAKE) test-ntt-forward
	@echo ""
	@$(MAKE) test-ntt-poly
	@echo ""
	@echo "======================================================================"
	@echo " All tests completed!"
	@echo "======================================================================"

# Testing NTT Inverse Transform
test-ntt-inverse: clean copy-hex-files
	@echo ""
	@echo "======================================================================"
	@echo " Testing NTT Inverse Transform (INTT)"
	@echo "======================================================================"
	@$(MAKE) -f $(firstword $(MAKEFILE_LIST)) \
		MODULE=cocotb_tests.test_ntt_inverse \
		TOPLEVEL=ntt_inverse \
		COMPILE_ARGS='$(COMPILE_ARGS) $(NTT_PARAM_ARGS)' \
		VERILOG_SOURCES="$(PWD)/../rtl/ntt_inverse.sv $(PWD)/../rtl/ntt_control_parallel.v $(PWD)/../rtl/ntt_coeff_banks.v $(PWD)/../rtl/ntt_coeff_bank_single.v $(PWD)/../rtl/ntt_cg_address_gen.v $(PWD)/../rtl/ntt_bank_switch.v $(PWD)/../rtl/twiddle_bram.v $(PWD)/../rtl/twiddle_bram_multiport.v $(PWD)/../rtl/ntt_butterfly.v $(PWD)/../rtl/mod_mult.v $(PWD)/../rtl/mod_add.v $(PWD)/../rtl/mod_sub.v $(PWD)/../rtl/barrett_reduction.v $(PWD)/../rtl/montgomery_reduction.v" \
		sim

test-ntt-control-1024:
	@$(MAKE) test-ntt-control \
		NTT_N=1024 \
		NTT_PARAM_ARGS="-Pntt_control_parallel.N=1024"

test-ntt-control-4096:
	@$(MAKE) test-ntt-control \
		NTT_N=4096 \
		NTT_PARAM_ARGS="-Pntt_control_parallel.N=4096"

test-ntt-forward-1024:
	@$(MAKE) test-ntt-forward \
		TWIDDLE_FORWARD_SRC=$(CURDIR)/../rtl/twiddle_forward_1024.hex \
		TWIDDLE_INVERSE_SRC=$(CURDIR)/../rtl/twiddle_inverse_1024.hex \
		NTT_N=1024 NTT_Q=8380417 NTT_PSI=5548360 \
		NTT_PARAM_ARGS="-Pntt_forward.N=1024 -Pntt_forward.ADDR_WIDTH=10 -Pntt_forward.PSI=5548360 -Ptwiddle_bram_multiport.DEPTH=1024 -Ptwiddle_bram_multiport.ADDR_WIDTH=10 -Ptwiddle_bram.DEPTH=1024 -Ptwiddle_bram.ADDR_WIDTH=10 -Pntt_coeff_banks.N=1024 -Pntt_cg_address_gen.N=1024 -Pntt_control_parallel.N=1024 -Pntt_bank_switch.LOGN=10"

test-ntt-inverse-1024:
	@$(MAKE) test-ntt-inverse \
		TWIDDLE_FORWARD_SRC=$(CURDIR)/../rtl/twiddle_forward_1024.hex \
		TWIDDLE_INVERSE_SRC=$(CURDIR)/../rtl/twiddle_inverse_1024.hex \
		NTT_N=1024 NTT_Q=8380417 NTT_PSI=5548360 \
		NTT_PARAM_ARGS="-Pntt_inverse.N=1024 -Pntt_inverse.ADDR_WIDTH=10 -Pntt_inverse.PSI_INV=2320879 -Pntt_inverse.N_INV=8372233 -Ptwiddle_bram_multiport.DEPTH=1024 -Ptwiddle_bram_multiport.ADDR_WIDTH=10 -Ptwiddle_bram.DEPTH=1024 -Ptwiddle_bram.ADDR_WIDTH=10 -Pntt_control_parallel.N=1024"

test-ntt-poly-1024:
	@$(MAKE) test-ntt-poly \
		TWIDDLE_FORWARD_SRC=$(CURDIR)/../rtl/twiddle_forward_1024.hex \
		TWIDDLE_INVERSE_SRC=$(CURDIR)/../rtl/twiddle_inverse_1024.hex \
		NTT_N=1024 NTT_Q=8380417 NTT_PSI=5548360 \
		NTT_PARAM_ARGS="-Pntt_poly_mult.N=1024 -Pntt_poly_mult.ADDR_WIDTH=10 -Pntt_poly_mult.PSI=5548360 -Pntt_poly_mult.PSI_INV=2320879 -Pntt_poly_mult.N_INV=8372233"

test-ntt-forward-4096:
	@$(MAKE) test-ntt-forward \
		TWIDDLE_FORWARD_SRC=$(CURDIR)/../rtl/twiddle_forward_4096.hex \
		TWIDDLE_INVERSE_SRC=$(CURDIR)/../rtl/twiddle_inverse_4096.hex \
		NTT_N=4096 NTT_Q=8380417 NTT_PSI=283817 \
		NTT_PARAM_ARGS="-Pntt_forward.N=4096 -Pntt_forward.ADDR_WIDTH=12 -Pntt_forward.PSI=283817 -Ptwiddle_bram_multiport.DEPTH=4096 -Ptwiddle_bram_multiport.ADDR_WIDTH=12 -Ptwiddle_bram.DEPTH=4096 -Ptwiddle_bram.ADDR_WIDTH=12 -Pntt_coeff_banks.N=4096 -Pntt_cg_address_gen.N=4096 -Pntt_control_parallel.N=4096 -Pntt_bank_switch.LOGN=12"

test-ntt-inverse-4096:
	@$(MAKE) test-ntt-inverse \
		TWIDDLE_FORWARD_SRC=$(CURDIR)/../rtl/twiddle_forward_4096.hex \
		TWIDDLE_INVERSE_SRC=$(CURDIR)/../rtl/twiddle_inverse_4096.hex \
		NTT_N=4096 NTT_Q=8380417 NTT_PSI=283817 \
		NTT_PARAM_ARGS="-Pntt_inverse.N=4096 -Pntt_inverse.ADDR_WIDTH=12 -Pntt_inverse.PSI_INV=7893065 -Pntt_inverse.N_INV=8378371 -Ptwiddle_bram_multiport.DEPTH=4096 -Ptwiddle_bram_multiport.ADDR_WIDTH=12 -Ptwiddle_bram.DEPTH=4096 -Ptwiddle_bram.ADDR_WIDTH=12 -Pntt_coeff_banks.N=4096 -Pntt_cg_address_gen.N=4096 -Pntt_control_parallel.N=4096 -Pntt_bank_switch.LOGN=12"

test-ntt-poly-4096:
	@$(MAKE) test-ntt-poly \
		TWIDDLE_FORWARD_SRC=$(CURDIR)/../rtl/twiddle_forward_4096.hex \
		TWIDDLE_INVERSE_SRC=$(CURDIR)/../rtl/twiddle_inverse_4096.hex \
		NTT_N=4096 NTT_Q=8380417 NTT_PSI=283817 \
		NTT_PARAM_ARGS="-Pntt_poly_mult.N=4096 -Pntt_poly_mult.ADDR_WIDTH=12 -Pntt_poly_mult.PSI=283817 -Pntt_poly_mult.PSI_INV=7893065 -Pntt_poly_mult.N_INV=8378371 -Ptwiddle_bram_multiport.DEPTH=4096 -Ptwiddle_bram_multiport.ADDR_WIDTH=12 -Ptwiddle_bram.DEPTH=4096 -Ptwiddle_bram.ADDR_WIDTH=12 -Pntt_coeff_banks.N=4096 -Pntt_cg_address_gen.N=4096 -Pntt_control_parallel.N=4096 -Pntt_bank_switch.LOGN=12"

test-all-1024: clean
	@echo ""
	@echo "======================================================================"
	@echo " Running full 1024-point test suite"
	@echo "======================================================================"
	@$(MAKE) test-mod-add
	@echo ""
	@$(MAKE) test-mod-sub
	@echo ""
	@$(MAKE) test-twiddle-rom
	@echo ""
	@$(MAKE) test-coeff-ram
	@echo ""
	@$(MAKE) test-butterfly
	@echo ""
	@$(MAKE) test-butterfly-inverse
	@echo ""
	@$(MAKE) test-ntt-mult
	@echo ""
	@$(MAKE) test-ntt-control-1024
	@echo ""
	@$(MAKE) test-ntt-inverse-1024
	@echo ""
	@$(MAKE) test-ntt-forward-1024
	@echo ""
	@$(MAKE) test-ntt-poly-1024
	@echo ""
	@echo "======================================================================"
	@echo " 1024-point test suite completed!"
	@echo "======================================================================"

test-all-4096: clean
	@echo ""
	@echo "======================================================================"
	@echo " Running full 4096-point test suite"
	@echo "======================================================================"
	@$(MAKE) test-mod-add
	@echo ""
	@$(MAKE) test-mod-sub
	@echo ""
	@$(MAKE) test-twiddle-rom
	@echo ""
	@$(MAKE) test-coeff-ram
	@echo ""
	@$(MAKE) test-butterfly
	@echo ""
	@$(MAKE) test-butterfly-inverse
	@echo ""
	@$(MAKE) test-ntt-mult
	@echo ""
	@$(MAKE) test-ntt-control-4096
	@echo ""
	@$(MAKE) test-ntt-inverse-4096
	@echo ""
	@$(MAKE) test-ntt-forward-4096
	@echo ""
	@$(MAKE) test-ntt-poly-4096
	@echo ""
	@echo "======================================================================"
	@echo " 4096-point test suite completed!"
	@echo "======================================================================"

# Clean target
clean::
	rm -rf __pycache__
	rm -rf sim_build
	rm -f results.xml
	rm -f *.vcd
