# Makefile for cocotb simulation of NTT Pointwise Multiplication Unit

# Simulation settings
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# RTL source files
VERILOG_SOURCES += $(PWD)/../rtl/barrett_reduction.sv
VERILOG_SOURCES += $(PWD)/../rtl/montgomery_reduction.sv
VERILOG_SOURCES += $(PWD)/../rtl/mod_mult.sv
VERILOG_SOURCES += $(PWD)/../rtl/ntt_pointwise_mult.sv

# Top-level module
TOPLEVEL = ntt_pointwise_mult

# Python test module
MODULE = test_ntt_mult

# Reduction method selection
# 0 = SIMPLE (direct modulo)
# 1 = BARRETT (Barrett reduction)
# 2 = MONTGOMERY (Montgomery reduction)
REDUCTION_TYPE ?= 0

# Simulator-specific settings
ifeq ($(SIM),icarus)
    COMPILE_ARGS += -g2012  # Enable SystemVerilog support
    COMPILE_ARGS += -PREDUCTION_TYPE=$(REDUCTION_TYPE)  # Parameter override for Icarus
endif

ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing  # For SystemVerilog timing constructs
    COMPILE_ARGS += -GREDUCTION_TYPE=$(REDUCTION_TYPE)  # Parameter override for Verilator
    EXTRA_ARGS += --trace --trace-structs
endif

# Include cocotb's make rules
include $(shell cocotb-config --makefiles)/Makefile.sim

# Test all reduction methods
.PHONY: test-all test-simple test-barrett test-montgomery

test-all: test-simple test-barrett test-montgomery
	@echo ""
	@echo "======================================================================"
	@echo " All reduction methods tested successfully!"
	@echo "======================================================================"

test-simple:
	@echo ""
	@echo "======================================================================"
	@echo " Testing with SIMPLE reduction (REDUCTION_TYPE=0)"
	@echo "======================================================================"
	$(MAKE) clean
	$(MAKE) REDUCTION_TYPE=0

test-barrett:
	@echo ""
	@echo "======================================================================"
	@echo " Testing with BARRETT reduction (REDUCTION_TYPE=1)"
	@echo "======================================================================"
	$(MAKE) clean
	$(MAKE) REDUCTION_TYPE=1

test-montgomery:
	@echo ""
	@echo "======================================================================"
	@echo " Testing with MONTGOMERY reduction (REDUCTION_TYPE=2)"
	@echo "======================================================================"
	$(MAKE) clean
	$(MAKE) REDUCTION_TYPE=2

# Clean target
clean::
	rm -rf __pycache__
	rm -rf sim_build
	rm -f results.xml
	rm -f *.vcd
