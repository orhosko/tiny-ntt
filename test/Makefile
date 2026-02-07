# Makefile for cocotb simulation of NTT Pointwise Multiplication Unit

# Simulation settings
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# RTL source files
VERILOG_SOURCES += $(PWD)/../rtl/mod_mult.sv
VERILOG_SOURCES += $(PWD)/../rtl/ntt_pointwise_mult.sv

# Top-level module
TOPLEVEL = ntt_pointwise_mult

# Python test module
MODULE = test_ntt_mult

# Simulator-specific settings
ifeq ($(SIM),icarus)
    COMPILE_ARGS += -g2012  # Enable SystemVerilog support
endif

ifeq ($(SIM),verilator)
    COMPILE_ARGS += --timing  # For SystemVerilog timing constructs
    EXTRA_ARGS += --trace --trace-structs
endif

# Include cocotb's make rules
include $(shell cocotb-config --makefiles)/Makefile.sim

# Clean target
clean::
	rm -rf __pycache__
	rm -rf sim_build
	rm -f results.xml
	rm -f *.vcd
