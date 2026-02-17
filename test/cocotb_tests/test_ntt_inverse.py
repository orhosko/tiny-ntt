"""
Cocotb test for inverse NTT module
Tests round-trip verification and polynomial multiplication
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os

# Add test directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from refs.ntt_forward_reference import ntt_forward_reference
from refs.ntt_inverse_reference import ntt_inverse_reference

# NTT parameters
N = 256
Q = 8380417
PSI = 1239911

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

async def run_intt(dut):
    """Start INTT computation and wait for completion"""
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    busy = int(dut.busy.value)
    done = int(dut.done.value)
    dut._log.info(f"  INTT started, busy={busy}, done={done}")
    
    timeout = 10000
    cycles = 0
    prev_state = -1
    
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        cycles += 1
        
        if cycles > timeout:
            # Dump debug info
            state = int(dut.state.value) if hasattr(dut, 'state') else -1
            busy = int(dut.busy.value)
            done = int(dut.done.value)
            intt_start = int(dut.intt_start.value) if hasattr(dut, 'intt_start') else -1
            intt_done = int(dut.intt_done.value) if hasattr(dut, 'intt_done') else -1
            intt_busy = int(dut.intt_busy.value) if hasattr(dut, 'intt_busy') else -1
            scale_addr = int(dut.scale_addr.value) if hasattr(dut, 'scale_addr') else -1
            
            dut._log.error(f"  TIMEOUT DEBUG:")
            dut._log.error(f"    Top state={state}, busy={busy}, done={done}")
            dut._log.error(f"    INTT control: start={intt_start}, done={intt_done}, busy={intt_busy}")
            dut._log.error(f"    Scale addr={scale_addr}")
            
            # Check control FSM if accessible
            if hasattr(dut, 'u_control'):
                ctrl_state = int(dut.u_control.state.value) if hasattr(dut.u_control, 'state') else -1
                stage = int(dut.u_control.stage.value) if hasattr(dut.u_control, 'stage') else -1
                butterfly = int(dut.u_control.butterfly.value) if hasattr(dut.u_control, 'butterfly') else -1
                cycle = int(dut.u_control.cycle.value) if hasattr(dut.u_control, 'cycle') else -1
                dut._log.error(f"    Control FSM: state={ctrl_state}, stage={stage}, butterfly={butterfly}, cycle={cycle}")
            
            raise RuntimeError(f"INTT timeout after {timeout} cycles")
        
        # Log state transitions
        if hasattr(dut, 'state'):
            state = int(dut.state.value)
            if state != prev_state:
                state_names = {0: "IDLE", 1: "INTT_COMPUTE", 2: "SCALE", 3: "DONE_STATE"}
                state_name = state_names.get(state, f"UNKNOWN({state})")
                dut._log.info(f"  State transition: {state_name}")
                prev_state = state
        
        if cycles % 1000 == 0:
            if hasattr(dut, 'state'):
                state = int(dut.state.value)
                state_names = {0: "IDLE", 1: "INTT_COMPUTE", 2: "SCALE", 3: "DONE_STATE"}
                state_name = state_names.get(state, f"{state}")
                dut._log.info(f"  Cycle {cycles}: state={state_name}")
            else:
                dut._log.info(f"  Cycle {cycles}...")
    
    dut._log.info(f"  INTT completed in {cycles} cycles")
    return cycles

@cocotb.test()
async def test_round_trip_impulse(dut):
    """Test round-trip: INTT(NTT(impulse)) = impulse"""
    dut._log.info("Testing round-trip with impulse")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Original: impulse = [1, 0, 0, ...]
    impulse = [1] + [0] * (N - 1)
    
    # NTT(impulse) = [1, 1, 1, ...]
    ntt_impulse = ntt_forward_reference(impulse)
    
    dut._log.info("  Loading NTT(impulse) = [1, 1, 1, ...]")
    await load_coefficients(dut, ntt_impulse)
    
    # Run INTT
    cycles = await run_intt(dut)
    
    # Wait a few extra cycles for data to stabilize
    for _ in range(5):
        await RisingEdge(dut.clk)
    
    # Read results
    results = await read_coefficients(dut)
    
    # Verify: should get back [1, 0, 0, ...]
    mismatches = sum(1 for i in range(N) if results[i] != impulse[i])
    
    if mismatches > 0:
        dut._log.error(f"  Round-trip failed!")
        dut._log.error(f"  Expected: {impulse[:10]}...")
        dut._log.error(f"  Got: {results[:10]}...")
    
    assert mismatches == 0, f"Round-trip failed with {mismatches} mismatches"
    dut._log.info(f"✓ Round-trip impulse test passed ({cycles} cycles)")

@cocotb.test()
async def test_intt_all_ones(dut):
    """Test INTT on all-ones input."""
    dut._log.info("Testing INTT on all-ones input")

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    input_data = [1] * N
    expected = ntt_inverse_reference(input_data, N, Q, PSI)

    await load_coefficients(dut, input_data)
    cycles = await run_intt(dut)

    for _ in range(5):
        await RisingEdge(dut.clk)

    results = await read_coefficients(dut)

    mismatches = sum(1 for i in range(N) if results[i] != expected[i])
    if mismatches:
        dut._log.error(f"  Expected: {expected[:10]}...")
        dut._log.error(f"  Got: {results[:10]}...")

    assert mismatches == 0, f"All-ones INTT failed with {mismatches} mismatches"
    dut._log.info(f"✓ All-ones INTT test passed ({cycles} cycles)")


@cocotb.test()
async def test_round_trip_random(dut):
    """Test round-trip with random polynomials"""
    dut._log.info("Testing round-trip with random polynomials")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    import random
    random.seed(54321)
    
    num_tests = 3
    for test_num in range(num_tests):
        dut._log.info(f"  Random test {test_num + 1}/{num_tests}")
        
        # Generate random polynomial
        poly = [random.randint(0, Q-1) for _ in range(N)]
        
        # Compute NTT
        ntt_poly = ntt_forward_reference(poly)
        
        # Load NTT result
        await load_coefficients(dut, ntt_poly)
        
        # Run INTT
        cycles = await run_intt(dut)
        
        # Wait for data to stabilize
        for _ in range(5):
            await RisingEdge(dut.clk)
        
        # Read results
        results = await read_coefficients(dut)
        
        # Verify round-trip
        mismatches = sum(1 for i in range(N) if results[i] != poly[i])
        
        if mismatches > 0:
            for i in range(N):
                if results[i] != poly[i]:
                    dut._log.error(f"    Mismatch at {i}: got {results[i]}, expected {poly[i]}")
                    break
        
        assert mismatches == 0, f"Random test {test_num + 1} failed"
        dut._log.info(f"    ✓ Passed ({cycles} cycles)")
    
    dut._log.info(f"✓ All {num_tests} round-trip tests passed")

@cocotb.test()
async def test_polynomial_multiplication_full(dut):
    """Test full polynomial multiplication: (x^2 + 5x + 1) * (x + 5)"""
    dut._log.info("Testing polynomial multiplication")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Polynomials:
    # p1(x) = 1 + 5x + x^2
    # p2(x) = 5 + x
    # Expected (negacyclic NTT result): 5 + 26x + 10x^2 + x^3
    
    poly1 = [1, 5, 1] + [0] * (N - 3)
    poly2 = [5, 1] + [0] * (N - 2)
    expected_product = [5, 26, 10, 1] + [0] * (N - 4)
    
    dut._log.info("  p1(x) = x^2 + 5x + 1")
    dut._log.info("  p2(x) = x + 5")
    dut._log.info("  Expected: x^3 + 6x^2 + 10x + 5")
    
    # Step 1: NTT(p1) and NTT(p2)
    ntt_p1 = ntt_forward_reference(poly1)
    ntt_p2 = ntt_forward_reference(poly2)
    
    # Step 2: Pointwise multiply
    ntt_product = [(ntt_p1[i] * ntt_p2[i]) % Q for i in range(N)]
    
    dut._log.info("  Computed NTT(p1) ⊙ NTT(p2)")
    
    # Step 3: INTT
    await load_coefficients(dut, ntt_product)
    cycles = await run_intt(dut)
    
    # Wait for data to stabilize
    for _ in range(5):
        await RisingEdge(dut.clk)
    
    result = await read_coefficients(dut)
    
    # Verify
    mismatches = sum(1 for i in range(N) if result[i] != expected_product[i])
    
    if mismatches > 0:
        dut._log.error(f"  Product verification failed!")
        dut._log.error(f"  Expected: {expected_product[:10]}")
        dut._log.error(f"  Got: {result[:10]}")
    else:
        dut._log.info(f"  Result: {result[:4]} (showing first 4 coefficients)")
    
    assert mismatches == 0, f"Multiplication failed with {mismatches} mismatches"
    dut._log.info(f"✓ Polynomial multiplication test passed ({cycles} cycles)")
