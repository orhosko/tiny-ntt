# Makefile for Yosys synthesis of NTT Pointwise Multiplication Unit

# Yosys command
YOSYS ?= yosys

# Synthesis script
SYNTH_SCRIPT = synth.ys

.PHONY: all synth clean

all: synth

# Synthesize the design
# Note: Edit rtl/ntt_pointwise_mult.sv to change REDUCTION_TYPE parameter
synth:
	@echo ""
	@echo "======================================================================"
	@echo " Synthesizing NTT Multiplication Unit"
	@echo " (Edit rtl/ntt_pointwise_mult.sv to change REDUCTION_TYPE)"
	@echo "======================================================================"
	@$(YOSYS) -s $(SYNTH_SCRIPT) | tee synth.log

# Clean synthesis outputs
clean:
	rm -f *.log
	rm -f synth_output.v
	rm -f synth_output.json
	rm -f *.dot
