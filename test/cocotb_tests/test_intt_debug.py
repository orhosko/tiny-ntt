"""
Detailed INTT debugging tests
Break down INTT into components and test each part
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from refs.ntt_forward_reference import ntt_forward_reference
from refs.ntt_inverse_reference import ntt_inverse_reference, mod_exp, mod_inv

N = 256
Q = 8380417
PSI = 1239911
PSI_INV = mod_inv(PSI, Q)
N_INV = mod_inv(N, Q)

async def load_coefficients(dut, coeffs):
    """Load coefficients into RAM"""
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = coeffs[addr] if addr < len(coeffs) else 0
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)

async def read_coefficients(dut, count=N):
    """Read coefficients from RAM"""
    results = []
    
    for addr in range(count):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        value = int(dut.read_data.value)
        results.append(value)
    
    return results

async def wait_for_done(dut, timeout=15000):
    """Wait for INTT to complete"""
    cycles = 0
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > timeout:
            raise RuntimeError(f"Timeout after {timeout} cycles")
    return cycles

@cocotb.test()
async def test_intt_no_scaling(dut):
    """Test INTT computation WITHOUT final scaling"""
    dut._log.info("="*60)
    dut._log.info("TEST: INTT without N^(-1) scaling")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Test case: NTT([1,1,1,...]) should give scaled impulse before division
    # After INTT (before scaling): should be [256, 0, 0, ...]
    # After scaling by N^(-1): should be [1, 0, 0, ...]
    
    input_data = [1] * N  # This is NTT(impulse)
    dut._log.info(f"Input: [1,1,1,...] (NTT of impulse)")
    
    # Load data
    await load_coefficients(dut, input_data)
    
    # Start INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    #  Wait for INTT_COMPUTE to complete (not full DONE, stop after INTT before scaling)
    # We need to read right after INTT_COMPUTE completes
    cycles = 0
    while True:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        cycles += 1
        
        if hasattr(dut, 'state'):
            state = int(dut.state.value)
            # state=2 is SCALE, so read just BEFORE that
            if state == 2:  # Entered SCALE state
                dut._log.info(f"  Detected SCALE state at cycle {cycles}")
                break
        
        if cycles > 10000:
            raise RuntimeError("Timeout waiting for SCALE state")
    
    # Read results right after INTT, before scaling
    results = await read_coefficients(dut)
    
    # Calculate expected: INTT without scaling should give N times the result
    # INTT([1,1,1,...]) without scaling = [256, 0, 0, ...]
    expected_unscaled = [N] + [0] * (N-1)
    
    dut._log.info(f"  Hardware result (first 5): {results[:5]}")
    dut._log.info(f"  Expected unscaled (first 5): {expected_unscaled[:5]}")
    
    mismatches = sum(1 for i in range(N) if results[i] != expected_unscaled[i])
    
    if mismatches > 0:
        dut._log.error(f"  FAIL: {mismatches} mismatches")
        for i in range(min(10, N)):
            if results[i] != expected_unscaled[i]:
                dut._log.error(f"    [{i}]: got {results[i]}, expected {expected_unscaled[i]}")
    else:
        dut._log.info(f"  ✓ PASS: INTT (without scaling) works correctly!")
    
    # Don't assert here, just collect info
    dut._log.info(f"Mismatch count: {mismatches}/{N}")

@cocotb.test()
async def test_scaling_only(dut):
    """Test JUST the scaling logic"""
    dut._log.info("="*60)
    dut._log.info(f"TEST: Scaling by N^(-1) = {N_INV}")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0  
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load test data: [256, 0, 0, ...] (what INTT should produce without scaling)
    test_data = [N] + [0] * (N-1)
    dut._log.info(f"Input for scaling test: [256, 0, 0, ...]")
    
    await load_coefficients(dut, test_data)
    
    # Run full INTT (it will do INTT + scaling)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    cycles = await wait_for_done(dut)
    dut._log.info(f"  Completed in {cycles} cycles")
    
    # Read results
    results = await read_coefficients(dut)
    
    # Expected after scaling: [N * N_INV mod Q, 0, 0, ...]
    expected = [1] + [0] * (N-1)
    
    dut._log.info(f"  Hardware result (first 5): {results[:5]}")
    dut._log.info(f"  Expected after scaling (first 5): {expected[:5]}")
    
    mismatches = sum(1 for i in range(N) if results[i] != expected[i])
    
    if mismatches > 0:
        dut._log.error(f"  FAIL: {mismatches} mismatches")  
        for i in range(min(10, N)):
            if results[i] != expected[i]:
                dut._log.error(f"    [{i}]: got {results[i]}, expected {expected[i]}")
    else:
        dut._log.info(f"  ✓ PASS: Scaling works correctly!")
    
    dut._log.info(f"Mismatch count: {mismatches}/{N}")

@cocotb.test()
async def test_python_reference_verification(dut):
    """Verify Python reference works correctly"""
    dut._log.info("="*60)
    dut._log.info("TEST: Python INTT Reference Verification")
    dut._log.info("="*60)
    
    # This test doesn't use hardware, just verifies Python
    
    # Test 1: Impulse round-trip
    dut._log.info("Test 1: Impulse round-trip")
    impulse = [1] + [0] * (N-1)
    ntt_impulse = ntt_forward_reference(impulse, N, Q, PSI)
    intt_result = ntt_inverse_reference(ntt_impulse, N, Q, PSI)
    
    if intt_result == impulse:
        dut._log.info("  ✓ Python impulse round-trip PASS")
    else:
        dut._log.error("  ✗ Python impulse round-trip FAIL")
        for i in range(min(10, N)):
            if intt_result[i] != impulse[i]:
                dut._log.error(f"    [{i}]: got {intt_result[i]}, expected {impulse[i]}")
    
    # Test  2: Known value
    dut._log.info("Test 2: Known simple vector")
    simple = [1, 2, 3] + [0] * (N-3)
    ntt_simple = ntt_forward_reference(simple, N, Q, PSI)
    intt_simple = ntt_inverse_reference(ntt_simple, N, Q, PSI)
    
    if intt_simple == simple:
        dut._log.info("  ✓ Python simple vector round-trip PASS")
    else:
        dut._log.error("  ✗ Python simple vector round-trip FAIL")
    
    dut._log.info("Python reference verification complete")

@cocotb.test()
async def test_step_by_step_comparison(dut):
    """Compare hardware vs Python step by step"""
    dut._log.info("="*60)
    dut._log.info("TEST: Step-by-step hardware vs Python")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Start with impulse
    impulse = [1] + [0] * (N-1)
    
    # Step 1: Forward NTT (Python)
    ntt_python = ntt_forward_reference(impulse, N, Q, PSI)
    dut._log.info(f"Step 1 - Python NTT([1,0,0,...]): {ntt_python[:5]}...")
    dut._log.info(f"         Expected: [1,1,1,1,1]...")
    
    # Step 2: Inverse NTT (Python)
    intt_python = ntt_inverse_reference(ntt_python, N, Q, PSI)
    dut._log.info(f"Step 2 - Python INTT(NTT): {intt_python[:5]}...")
    dut._log.info(f"         Expected: [1,0,0,0,0]...")
    
    # Step 3: Hardware INTT
    await load_coefficients(dut, ntt_python)
    
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    cycles = await wait_for_done(dut)
    dut._log.info(f"Step 3 - Hardware INTT completed in {cycles} cycles")
    
    hw_result = await read_coefficients(dut)
    dut._log.info(f"         Hardware result: {hw_result[:5]}...")
    dut._log.info(f"         Python result:   {intt_python[:5]}...")
    
    # Compare
    mismatches = sum(1 for i in range(N) if hw_result[i] != intt_python[i])
    
    if mismatches == 0:
        dut._log.info(f"  ✓ PERFECT MATCH!")
    else:
        dut._log.error(f"  ✗ {mismatches} mismatches")
        for i in range(min(10, N)):
            if hw_result[i] != intt_python[i]:
                dut._log.error(f"    [{i}]: HW={hw_result[i]}, PY={intt_python[i]}, diff={hw_result[i]-intt_python[i]}")
    
    assert mismatches == 0, f"Hardware doesn't match Python: {mismatches} errors"
