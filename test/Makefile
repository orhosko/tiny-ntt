# Makefile for cocotb-based NTT multiplication testbench

# Simulator selection
SIM ?= icarus

# Testbench module
COCOTB_TEST_MODULES = test_ntt_mult

# Top-level module
TOPLEVEL = ntt_pointwise_mult

# Verilog sources - relative paths from test directory
VERILOG_SOURCES = \
	$(PWD)/../rtl/barrett_reduction.sv \
	$(PWD)/../rtl/montgomery_reduction.sv \
	$(PWD)/../rtl/mod_mult.sv \
	$(PWD)/../rtl/ntt_pointwise_mult.sv

# Language
TOPLEVEL_LANG = verilog

# Enable waveform dumping for all simulators
WAVES ?= 1
export WAVES

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

# Clean target
clean::
	rm -rf __pycache__
	rm -rf sim_build
	rm -f results.xml
	rm -f *.vcd