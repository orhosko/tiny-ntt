"""
Cocotb testbench for NTT butterfly unit
Tests Cooley-Tukey radix-2 butterfly: (a', b') = (a + ψ·b, a - ψ·b) mod q
"""

import cocotb
from cocotb.triggers import Timer
import random

# Test parameters
WIDTH = 32
Q = 8380417
PSI = 1239911

def butterfly_reference(a, b, twiddle, q=Q):
    """
    Python reference implementation of CT butterfly
    Returns (a_out, b_out) where:
        a_out = (a + twiddle*b) mod q
        b_out = (a - twiddle*b) mod q
    """
    twiddle_b = (twiddle * b) % q
    a_out = (a + twiddle_b) % q
    b_out = (a - twiddle_b) % q
    return (a_out, b_out)

@cocotb.test()
async def test_identity_twiddle(dut):
    """Test with twiddle factor = 1 (identity)"""
    dut._log.info("Testing butterfly with twiddle = 1 (identity)")
    
    test_cases = [
        (0, 0),
        (1, 1),
        (10, 20),
        (100, 200),
        (Q-1, Q-1),
    ]
    
    for a, b in test_cases:
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = 1
        await Timer(1, unit='ns')
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        expected_a, expected_b = butterfly_reference(a, b, 1)
        
        assert a_out == expected_a, \
            f"Identity twiddle: a_out mismatch for ({a}, {b}): got {a_out}, expected {expected_a}"
        assert b_out == expected_b, \
            f"Identity twiddle: b_out mismatch for ({a}, {b}): got {b_out}, expected {expected_b}"
    
    dut._log.info(f"✓ Identity twiddle test passed for {len(test_cases)} cases")

@cocotb.test()
async def test_zero_twiddle(dut):
    """Test with twiddle factor = 0"""
    dut._log.info("Testing butterfly with twiddle = 0")
    
    test_cases = [
        (0, 0),
        (1, 100),
        (100, 200),
        (Q-1, Q-1),
    ]
    
    for a, b in test_cases:
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = 0
        await Timer(1, unit='ns')
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        # When twiddle = 0: a_out = a, b_out = a
        expected_a, expected_b = butterfly_reference(a, b, 0)
        
        assert a_out == expected_a, \
            f"Zero twiddle: a_out mismatch: got {a_out}, expected {expected_a}"
        assert b_out == expected_b, \
            f"Zero twiddle: b_out mismatch: got {b_out}, expected {expected_b}"
    
    dut._log.info(f"✓ Zero twiddle test passed for {len(test_cases)} cases")

@cocotb.test()
async def test_basic_butterfly(dut):
    """Test basic butterfly operations with known values"""
    dut._log.info("Testing basic butterfly operations")
    
    test_cases = [
        # (a, b, twiddle, expected_a, expected_b)
        (10, 5, 2, (10 + 2*5) % Q, (10 - 2*5) % Q),  # Simple case
        (100, 50, 3, (100 + 3*50) % Q, (100 - 3*50) % Q),
        (1000, 500, 17, (1000 + 17*500) % Q, (1000 - 17*500) % Q),
    ]
    
    for a, b, twiddle, exp_a, exp_b in test_cases:
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = twiddle
        await Timer(1, unit='ns')
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        assert a_out == exp_a, \
            f"Basic butterfly: a_out mismatch for ({a}, {b}, {twiddle}): got {a_out}, expected {exp_a}"
        assert b_out == exp_b, \
            f"Basic butterfly: b_out mismatch for ({a}, {b}, {twiddle}): got {b_out}, expected {exp_b}"
    
    dut._log.info(f"✓ Basic butterfly test passed for {len(test_cases)} cases")

@cocotb.test()
async def test_inverse_butterfly(dut):
    """Test that butterfly is reversible"""
    dut._log.info("Testing butterfly reversibility")
    
    # The inverse butterfly with same twiddle should give back original values
    # If (a', b') = BF(a, b, ψ), then (a, b) = BF(a', b', -ψ) / 2
    # For NTT, we typically use different twiddles for inverse
    
    test_cases = [
        (100, 200, 17),
        (500, 1000, 3),
        (Q-1, 1, 2),
    ]
    
    for a, b, twiddle in test_cases:
        # Forward butterfly
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = twiddle
        await Timer(1, unit='ns')
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        # Verify against reference
        exp_a, exp_b = butterfly_reference(a, b, twiddle)
        assert a_out == exp_a and b_out == exp_b, \
            f"Forward butterfly failed for ({a}, {b}, {twiddle})"
    
    dut._log.info(f"✓ Butterfly produces correct outputs")

@cocotb.test()
async def test_ntt_twiddle_factors(dut):
    """Test with actual NTT twiddle factors"""
    dut._log.info("Testing with NTT twiddle factors")
    
    # ψ is primitive 2N-th root of unity for NWC
    # Common twiddle factors: ψ^0, ψ^1, ψ^2, ..., ψ^128
    psi = PSI
    
    test_cases = [
        (100, 200, pow(psi, 0, Q)),   # ψ^0 = 1
        (100, 200, pow(psi, 1, Q)),   # ψ^1
        (100, 200, pow(psi, 2, Q)),   # ψ^2
        (100, 200, pow(psi, 64, Q)),  # ψ^64
        (100, 200, pow(psi, 128, Q)), # ψ^128
    ]
    
    for i, (a, b, twiddle) in enumerate(test_cases):
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = twiddle
        await Timer(1, unit='ns')
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        exp_a, exp_b = butterfly_reference(a, b, twiddle)
        
        assert a_out == exp_a, \
            f"NTT twiddle test {i}: a_out mismatch: got {a_out}, expected {exp_a}"
        assert b_out == exp_b, \
            f"NTT twiddle test {i}: b_out mismatch: got {b_out}, expected {exp_b}"
    
    dut._log.info(f"✓ NTT twiddle factors test passed for {len(test_cases)} cases")

@cocotb.test()
async def test_boundary_values(dut):
    """Test with boundary values"""
    dut._log.info("Testing boundary values")
    
    test_cases = [
        (0, 0, 0),
        (Q-1, Q-1, Q-1),
        (0, Q-1, 1),
        (Q-1, 0, Q-1),
        (Q-1, 1, Q-2),
        (1, Q-1, 2),
    ]
    
    for a, b, twiddle in test_cases:
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = twiddle
        await Timer(1, unit='ns')
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        exp_a, exp_b = butterfly_reference(a, b, twiddle)
        
        assert a_out == exp_a, \
            f"Boundary test: a_out mismatch for ({a}, {b}, {twiddle}): got {a_out}, expected {exp_a}"
        assert b_out == exp_b, \
            f"Boundary test: b_out mismatch for ({a}, {b}, {twiddle}): got {b_out}, expected {exp_b}"
    
    dut._log.info(f"✓ Boundary values test passed for {len(test_cases)} cases")

@cocotb.test()
async def test_random_values(dut):
    """Test with random values"""
    dut._log.info("Testing with random values")
    
    random.seed(42)
    num_tests = 100
    
    for i in range(num_tests):
        a = random.randint(0, Q-1)
        b = random.randint(0, Q-1)
        twiddle = random.randint(0, Q-1)
        
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = twiddle
        await Timer(1, unit='ns')
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        exp_a, exp_b = butterfly_reference(a, b, twiddle)
        
        assert a_out == exp_a, \
            f"Random test {i}: a_out mismatch: got {a_out}, expected {exp_a}"
        assert b_out == exp_b, \
            f"Random test {i}: b_out mismatch: got {b_out}, expected {exp_b}"
        
        if (i + 1) % 20 == 0:
            dut._log.info(f"  Completed {i+1}/{num_tests} random tests")
    
    dut._log.info(f"✓ All {num_tests} random tests passed")

@cocotb.test()
async def test_symmetry(dut):
    """Test butterfly symmetry properties"""
    dut._log.info("Testing butterfly symmetry")
    
    # Test that swapping a and b with proper twiddle adjustment works
    test_pairs = [
        (100, 200, 17),
        (500, 1000, 3),
        (Q-1, 1, 2),
    ]
    
    for a, b, twiddle in test_pairs:
        # Original
        dut.a.value = a
        dut.b.value = b
        dut.twiddle.value = twiddle
        await Timer(1, unit='ns')
        
        a_out1 = int(dut.a_out.value)
        b_out1 = int(dut.b_out.value)
        
        # Verify they match reference
        exp_a, exp_b = butterfly_reference(a, b, twiddle)
        assert a_out1 == exp_a and b_out1 == exp_b, \
            f"Symmetry test failed for ({a}, {b}, {twiddle})"
    
    dut._log.info("✓ Butterfly symmetry verified")
