#!/usr/bin/env python3
"""
Test Forward NTT hardware with new parameters (Q=8380417, WIDTH=24)
Compares hardware output against Python reference
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from refs.ntt_forward_reference import ntt_forward_reference, N, Q, PSI

@cocotb.test()
async def test_forward_ntt_new_params(dut):
    """Test forward NTT with Q=8380417"""
    
    # Start clock
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    
    dut._log.info(f"Testing Forward NTT with N={N}, Q={Q}")
    
    # Test 1: Simple polynomial
    test_poly = [1, 2, 3] + [0] * (N - 3)
    dut._log.info(f"Input: {test_poly[:10]}")
    
    # Load coefficients
    dut.load_coeff.value = 1
    for i, coeff in enumerate(test_poly):
        dut.load_addr.value = i
        dut.load_data.value = int(coeff)
        await RisingEdge(dut.clk)
    dut.load_coeff.value = 0
    
    # Start NTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for completion
    timeout = 10000
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            break
    else:
        assert False, f"NTT didn't complete in {timeout} cycles"
    
    dut._log.info(f"NTT completed")
    
    # Read results (need delay for RAM read)
    hw_result = []
    for i in range(N):
        dut.read_addr.value = i
        await RisingEdge(dut.clk)  # Wait for RAM output
        await RisingEdge(dut.clk)  # Extra cycle for stability
        val = dut.read_data.value
        # Handle X/Z values
        try:
            hw_result.append(int(val))
        except ValueError:
            dut._log.warning(f"Invalid value at [{i}]: {val}")
            hw_result.append(0)  # Use 0 for invalid
    
    dut._log.info(f"Hardware output: {hw_result[:10]}")
    
    # Compare with Python reference
    py_result = ntt_forward_reference(test_poly)
    dut._log.info(f"Python reference: {py_result[:10]}")
    
    # Check match
    mismatches = 0
    for i in range(N):
        if hw_result[i] != py_result[i]:
            if mismatches < 10:  # Show first 10 mismatches
                dut._log.error(f"Mismatch at [{i}]: HW={hw_result[i]}, PY={py_result[i]}")
            mismatches += 1
    
    if mismatches == 0:
        dut._log.info("✓✓✓ Hardware matches Python reference!")
    else:
        dut._log.error(f"✗ {mismatches}/{N} mismatches")
        assert False, f"Hardware output doesn't match Python reference"
