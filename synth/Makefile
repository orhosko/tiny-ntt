# Makefile for Yosys synthesis of NTT Pointwise Multiplication Unit

# Yosys command
YOSYS ?= yosys

# Synthesis script
SYNTH_SCRIPT = synth.ys

# Reduction types
REDUCTION_TYPES = 0 1 2
REDUCTION_NAMES = simple barrett montgomery

.PHONY: all synth-all synth-simple synth-barrett synth-montgomery clean report

all: synth-all

# Synthesize all reduction methods
synth-all: synth-simple synth-barrett synth-montgomery
	@echo ""
	@echo "======================================================================"
	@echo " Synthesis complete for all reduction methods!"
	@echo " Reports available in synth/ directory"
	@echo "======================================================================"
	@echo ""
	@$(MAKE) report

# Synthesize with SIMPLE reduction
synth-simple:
	@echo ""
	@echo "======================================================================"
	@echo " Synthesizing with SIMPLE reduction (REDUCTION_TYPE=0)"
	@echo "======================================================================"
	@$(YOSYS) -p "read_verilog -sv ../rtl/mod_mult.sv; \
	              read_verilog -sv ../rtl/ntt_pointwise_mult_synth.sv; \
	              chparam -set REDUCTION_TYPE 0 ntt_pointwise_mult_synth; \
	              script $(SYNTH_SCRIPT)" | tee synth_simple.log

# Synthesize with BARRETT reduction
synth-barrett:
	@echo ""
	@echo "======================================================================"
	@echo " Synthesizing with BARRETT reduction (REDUCTION_TYPE=1)"
	@echo "======================================================================"
	@$(YOSYS) -p "read_verilog -sv ../rtl/barrett_reduction.sv; \
	              read_verilog -sv ../rtl/mod_mult.sv; \
	              read_verilog -sv ../rtl/ntt_pointwise_mult_synth.sv; \
	              chparam -set REDUCTION_TYPE 1 ntt_pointwise_mult_synth; \
	              script $(SYNTH_SCRIPT)" | tee synth_barrett.log

# Synthesize with MONTGOMERY reduction
synth-montgomery:
	@echo ""
	@echo "======================================================================"
	@echo " Synthesizing with MONTGOMERY reduction (REDUCTION_TYPE=2)"
	@echo "======================================================================"
	@$(YOSYS) -p "read_verilog -sv ../rtl/montgomery_reduction.sv; \
	              read_verilog -sv ../rtl/mod_mult.sv; \
	              read_verilog -sv ../rtl/ntt_pointwise_mult_synth.sv; \
	              chparam -set REDUCTION_TYPE 2 ntt_pointwise_mult_synth; \
	              script $(SYNTH_SCRIPT)" | tee synth_montgomery.log

# Generate comparison report
report:
	@echo "======================================================================"
	@echo " Synthesis Statistics Comparison"
	@echo "======================================================================"
	@echo ""
	@for name in $(REDUCTION_NAMES); do \
		echo "--- $$name reduction ---"; \
		grep -A 20 "Printing statistics" synth_$$name.log | head -25 || true; \
		echo ""; \
	done

# Clean synthesis outputs
clean:
	rm -f *.log
	rm -f synth_output.v
	rm -f synth_output.json
	rm -f *.dot
