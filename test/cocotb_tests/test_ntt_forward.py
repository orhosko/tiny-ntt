"""
Cocotb integration test for complete NTT forward transform
Tests the full pipeline with all components integrated
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os

# Add test directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from refs.ntt_forward_reference import ntt_forward_reference

# NTT parameters
N = 256
Q = 8380417
PSI = 1239911

async def load_coefficients(dut, coeffs):
    """Load coefficients into RAM via load interface"""
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
    dut._log.info(f"  Loaded {len(coeffs)} coefficients")

async def read_coefficients(dut, count=N):
    """Read coefficients from RAM via read interface"""
    results = []
    
    for addr in range(count):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")  # Wait for synchronous RAM
        value = int(dut.read_data.value)
        results.append(value)
    
    return results

async def run_ntt(dut):
    """Start NTT computation and wait for completion"""
    # Start NTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    # Check busy signal
    busy = int(dut.busy.value)
    done = int(dut.done.value)
    dut._log.info(f"  NTT started, busy={busy}, done={done}")
    
    # Wait for completion (with timeout)
    timeout = 10000  # cycles
    cycles = 0
    prev_stage = -1
    prev_butterfly = -1
    
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        cycles += 1
        
        if cycles > timeout:
            # Dump debug info on timeout
            state = int(dut.u_control.state.value) if hasattr(dut.u_control, 'state') else -1
            stage = int(dut.u_control.stage.value) if hasattr(dut.u_control, 'stage') else -1
            butterfly = int(dut.u_control.butterfly.value) if hasattr(dut.u_control, 'butterfly') else -1
            cycle = int(dut.u_control.cycle.value) if hasattr(dut.u_control, 'cycle') else -1
            busy = int(dut.busy.value)
            done = int(dut.done.value)
            
            dut._log.error(f"  TIMEOUT DEBUG:")
            dut._log.error(f"    FSM state={state}, stage={stage}, butterfly={butterfly}, cycle={cycle}")
            dut._log.error(f"    busy={busy}, done={done}")
            raise RuntimeError(f"NTT timeout after {timeout} cycles")
        
        # Log stage transitions
        if hasattr(dut.u_control, 'stage'):
            stage = int(dut.u_control.stage.value)
            butterfly = int(dut.u_control.butterfly.value)
            
            if stage != prev_stage:
                dut._log.info(f"  Stage {stage} started (butterfly {butterfly})")
                prev_stage = stage
        
        # Log progress occasionally
        if cycles % 1000 == 0:
            if hasattr(dut.u_control, 'stage'):
                state = int(dut.u_control.state.value)
                stage = int(dut.u_control.stage.value)
                butterfly = int(dut.u_control.butterfly.value)
                cycle = int(dut.u_control.cycle.value)
                dut._log.info(f"  Cycle {cycles}: state={state}, stage={stage}, butterfly={butterfly}, cycle={cycle}")
            else:
                dut._log.info(f"  Cycle {cycles}...")
    
    await Timer(1, unit="ns")
    dut._log.info(f"  NTT completed in {cycles} cycles")
    return cycles

@cocotb.test()
async def test_load_and_read(dut):
    """Test loading and reading coefficients without NTT"""
    dut._log.info("Testing load and read interface")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.load_coeff.value = 0
    dut.read_addr.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load test data
    test_data = [i * 10 for i in range(N)]
    await load_coefficients(dut, test_data)
    
    # Read back
    results = await read_coefficients(dut)
    
    # Verify
    mismatches = 0
    for i in range(N):
        if results[i] != test_data[i]:
            dut._log.error(f"  Mismatch at {i}: got {results[i]}, expected {test_data[i]}")
            mismatches += 1
            if mismatches > 10:  # Limit error output
                break
    
    assert mismatches == 0, f"Load/read test failed with {mismatches} mismatches"
    dut._log.info("✓ Load and read interface works")

@cocotb.test()
async def test_ntt_all_zeros(dut):
    """Test NTT with all zero input"""
    dut._log.info("Testing NTT with all zeros")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load all zeros
    zeros = [0] * N
    await load_coefficients(dut, zeros)
    
    # Run NTT
    cycles = await run_ntt(dut)
    
    # Read results
    results = await read_coefficients(dut)
    
    # All outputs should be zero
    non_zero = sum(1 for r in results if r != 0)
    assert non_zero == 0, f"All zeros test failed: {non_zero} non-zero outputs"
    
    dut._log.info(f"✓ All zeros test passed ({cycles} cycles)")

@cocotb.test()
async def test_ntt_impulse(dut):
    """Test NTT with impulse at position 0"""
    dut._log.info("Testing NTT with impulse")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load impulse
    impulse = [0] * N
    impulse[0] = 1
    await load_coefficients(dut, impulse)
    
    # Run NTT
    cycles = await run_ntt(dut)
    
    # Read results
    results = await read_coefficients(dut)
    
    # All outputs should be 1
    all_ones = all(r == 1 for r in results)
    if not all_ones:
        non_one_count = sum(1 for r in results if r != 1)
        dut._log.error(f"  Expected all 1s, got {non_one_count} non-1 values")
        dut._log.error(f"  First 20 results: {results[:20]}")
    
    assert all_ones, "Impulse test failed: not all outputs are 1"
    dut._log.info(f"✓ Impulse test passed ({cycles} cycles)")

@cocotb.test()
async def test_ntt_simple_vector(dut):
    """Test NTT with simple known vector"""
    dut._log.info("Testing NTT with simple vector [1, 2, 3, 0, 0, ...]")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load simple vector
    simple = [1, 2, 3] + [0] * (N - 3)
    await load_coefficients(dut, simple)
    
    # Compute reference
    expected = ntt_forward_reference(simple, N, Q, PSI)
    
    # Run NTT
    cycles = await run_ntt(dut)
    
    # Read results
    results = await read_coefficients(dut)
    
    # Compare with reference
    mismatches = 0
    for i in range(N):
        if results[i] != expected[i]:
            if mismatches < 10:  # Limit error output
                dut._log.error(f"  Mismatch at {i}: got {results[i]}, expected {expected[i]}")
            mismatches += 1
    
    if mismatches > 0:
        dut._log.error(f"  Total mismatches: {mismatches}/{N}")
        dut._log.error(f"  First 10 results:  {results[:10]}")
        dut._log.error(f"  First 10 expected: {expected[:10]}")
    
    assert mismatches == 0, f"Simple vector test failed with {mismatches} mismatches"
    dut._log.info(f"✓ Simple vector test passed ({cycles} cycles)")

@cocotb.test()
async def test_ntt_reference_comparison(dut):
    """Test NTT against Python reference with various inputs"""
    dut._log.info("Testing NTT against reference implementation")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Test cases
    test_cases = [
        ("All ones", [1] * N),
        ("Counting sequence", [(i % Q) for i in range(N)]),
        ("Powers of 2", [(1 << (i % 10)) for i in range(N)]),
    ]
    
    for name, input_vec in test_cases:
        dut._log.info(f"  Testing: {name}")
        
        # Load coefficients
        await load_coefficients(dut, input_vec)
        
        # Compute reference
        expected = ntt_forward_reference(input_vec, N, Q, PSI)
        
        # Run NTT
        cycles = await run_ntt(dut)
        
        # Read results
        results = await read_coefficients(dut)
        
        # Compare
        mismatches = 0
        for i in range(N):
            if results[i] != expected[i]:
                if mismatches < 5:
                    dut._log.error(f"    Mismatch at {i}: got {results[i]}, expected {expected[i]}")
                mismatches += 1
        
        if mismatches > 0:
            dut._log.error(f"    {name}: {mismatches} mismatches")
        else:
            dut._log.info(f"    {name}: ✓ Passed ({cycles} cycles)")
        
        assert mismatches == 0, f"{name} failed with {mismatches} mismatches"
    
    dut._log.info(f"✓ All reference comparison tests passed")

@cocotb.test()
async def test_ntt_random_polynomials(dut):
    """Test NTT with random polynomial inputs"""
    dut._log.info("Testing NTT with random polynomials")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Test multiple random polynomials
    import random
    random.seed(12345)  # Reproducible
    
    num_tests = 5
    for test_num in range(num_tests):
        dut._log.info(f"  Random test {test_num + 1}/{num_tests}")
        
        # Generate random polynomial coefficients (0 to Q-1)
        random_poly = [random.randint(0, Q-1) for _ in range(N)]
        
        # Load coefficients
        await load_coefficients(dut, random_poly)
        
        # Compute expected NTT using reference
        expected = ntt_forward_reference(random_poly, N, Q, PSI)
        
        # Run NTT
        cycles = await run_ntt(dut)
        
        # Read results
        results = await read_coefficients(dut)
        
        # Compare
        mismatches = 0
        for i in range(N):
            if results[i] != expected[i]:
                if mismatches < 5:  # Limit error output
                    dut._log.error(f"    Index {i}: got {results[i]}, expected {expected[i]}")
                mismatches += 1
        
        if mismatches > 0:
            dut._log.error(f"    Random test {test_num + 1}: {mismatches} mismatches")
        else:
            dut._log.info(f"    Random test {test_num + 1}: ✓ Passed ({cycles} cycles)")
        
        assert mismatches == 0, f"Random test {test_num + 1} failed with {mismatches} mismatches"
    
    dut._log.info(f"✓ All {num_tests} random polynomial tests passed")

@cocotb.test()
async def test_polynomial_multiplication(dut):
    """Test polynomial multiplication: (x^2 + 5x + 1) * (x + 5)"""
    dut._log.info("Testing polynomial multiplication via NTT")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Define polynomials:
    # p1(x) = x^2 + 5x + 1 = 1 + 5x + 1x^2
    # p2(x) = x + 5 = 5 + x
    # Result = (x^2 + 5x + 1)(x + 5) = x^3 + 6x^2 + 10x + 5
    #        = 5 + 10x + 6x^2 + x^3
    
    poly1 = [1, 5, 1] + [0] * (N - 3)  # [1, 5, 1, 0, 0, ...]
    poly2 = [5, 1] + [0] * (N - 2)     # [5, 1, 0, 0, ...]
    
    dut._log.info("  Polynomial 1: x^2 + 5x + 1")
    dut._log.info("  Polynomial 2: x + 5")
    dut._log.info("  Expected product: x^3 + 6x^2 + 10x + 5")
    
    # Test poly1
    dut._log.info("  Computing NTT of polynomial 1...")
    await load_coefficients(dut, poly1)
    expected1 = ntt_forward_reference(poly1, N, Q, PSI)
    cycles1 = await run_ntt(dut)
    result1 = await read_coefficients(dut)
    
    # Verify poly1 NTT
    mismatch1 = sum(1 for i in range(N) if result1[i] != expected1[i])
    assert mismatch1 == 0, f"Poly1 NTT failed with {mismatch1} mismatches"
    dut._log.info(f"    ✓ Polynomial 1 NTT correct ({cycles1} cycles)")
    
    # Test poly2
    dut._log.info("  Computing NTT of polynomial 2...")
    await load_coefficients(dut, poly2)
    expected2 = ntt_forward_reference(poly2, N, Q, PSI)
    cycles2 = await run_ntt(dut)
    result2 = await read_coefficients(dut)
    
    # Verify poly2 NTT
    mismatch2 = sum(1 for i in range(N) if result2[i] != expected2[i])
    assert mismatch2 == 0, f"Poly2 NTT failed with {mismatch2} mismatches"
    dut._log.info(f"    ✓ Polynomial 2 NTT correct ({cycles2} cycles)")
    
    # Show what the multiplication would look like (for reference)
    dut._log.info("  Note: Full multiplication requires INTT (inverse NTT)")
    dut._log.info("  Expected result coefficients: [5, 10, 6, 1, 0, 0, ...]")
    
    # For verification in Python:
    # Pointwise multiply NTT outputs
    ntt_product = [(expected1[i] * expected2[i]) % Q for i in range(N)]
    
    # Would need inverse NTT here to get actual polynomial product
    # (not implemented in hardware yet)
    
    dut._log.info("✓ Polynomial NTT verification passed")
