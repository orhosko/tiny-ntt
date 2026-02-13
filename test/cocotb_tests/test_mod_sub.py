"""
Cocotb testbench for modular subtractor (mod_sub)
Tests (a - b) mod Q operation for NTT arithmetic
"""

import cocotb
from cocotb.triggers import Timer
import random

# Test parameters
WIDTH = 32
Q = 8380417

def mod_sub_reference(a, b, q=Q):
    """Python reference implementation of modular subtraction"""
    return (a - b) % q

@cocotb.test()
async def test_basic_subtraction(dut):
    """Test basic modular subtraction cases"""
    dut._log.info("Testing basic modular subtraction")
    
    test_cases = [
        (0, 0, 0),          # Zero - zero
        (1, 0, 1),          # Identity
        (1, 1, 0),          # Equal values
        (10, 5, 5),         # Simple subtraction
        (100, 50, 50),      # Normal case
        (Q-1, 0, Q-1),      # Max value
        (0, 1, Q-1),        # Negative wraparound
        (0, Q-1, 1),        # Large negative
        (1000, 500, 500),   # Larger values
        (500, 1000, Q-500), # a < b case
    ]
    
    for a, b, expected in test_cases:
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')  # Wait for combinational logic
        
        result = int(dut.result.value)
        assert result == expected, \
            f"Subtraction failed: {a} - {b} mod {Q} = {result}, expected {expected}"
    
    dut._log.info(f"✓ All {len(test_cases)} basic subtraction tests passed")

@cocotb.test()
async def test_identity(dut):
    """Test that subtracting 0 gives original value"""
    dut._log.info("Testing subtraction identity")
    
    test_values = [0, 1, 10, 100, 1000, Q-1, Q//2]
    
    for val in test_values:
        dut.a.value = val
        dut.b.value = 0
        await Timer(1, unit='ns')
        result = int(dut.result.value)
        assert result == val, f"Identity failed: {val} - 0 = {result}, expected {val}"
    
    dut._log.info(f"✓ Identity verified for {len(test_values)} values")

@cocotb.test()
async def test_self_subtraction(dut):
    """Test that a - a = 0"""
    dut._log.info("Testing self-subtraction")
    
    test_values = [0, 1, 10, 100, 1000, Q-1, Q//2]
    
    for val in test_values:
        dut.a.value = val
        dut.b.value = val
        await Timer(1, unit='ns')
        result = int(dut.result.value)
        assert result == 0, f"Self-subtraction failed: {val} - {val} = {result}, expected 0"
    
    dut._log.info(f"✓ Self-subtraction verified for {len(test_values)} values")

@cocotb.test()
async def test_negative_results(dut):
    """Test handling of negative results (a < b)"""
    dut._log.info("Testing negative result handling")
    
    test_cases = [
        (0, 1, Q-1),        # 0 - 1 = -1 = Q-1 mod Q
        (0, 2, Q-2),        # 0 - 2 = -2 = Q-2 mod Q
        (5, 10, Q-5),       # 5 - 10 = -5 = Q-5 mod Q
        (100, 200, Q-100),  # 100 - 200 = -100 = Q-100 mod Q
        (1, Q-1, 2),        # 1 - (Q-1) = 2 mod Q
    ]
    
    for a, b, expected in test_cases:
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')
        
        result = int(dut.result.value)
        assert result == expected, \
            f"Negative handling failed: {a} - {b} mod {Q} = {result}, expected {expected}"
    
    dut._log.info(f"✓ Negative result handling verified")

@cocotb.test()
async def test_inverse_of_addition(dut):
    """Test that subtraction is the inverse of addition"""
    dut._log.info("Testing subtraction as inverse of addition")
    
    # We need the mod_add module for this, so we'll just verify algebraically
    # (a + b) - b = a
    test_pairs = [
        (10, 5),
        (100, 50),
        (1000, 500),
        (Q-1, 1),
        (Q//2, Q//2),
    ]
    
    for a, b in test_pairs:
        # Compute a + b mod Q in Python
        sum_val = (a + b) % Q
        
        # Compute (a + b) - b mod Q
        dut.a.value = sum_val
        dut.b.value = b
        await Timer(1, unit='ns')
        result = int(dut.result.value)
        
        assert result == a, \
            f"Inverse property failed: ({a}+{b})-{b} = {result}, expected {a}"
    
    dut._log.info(f"✓ Inverse property verified for {len(test_pairs)} pairs")

@cocotb.test()
async def test_random_values(dut):
    """Test with random values"""
    dut._log.info("Testing with random values")
    
    random.seed(42)  # Reproducible tests
    num_tests = 100
    
    for i in range(num_tests):
        a = random.randint(0, Q-1)
        b = random.randint(0, Q-1)
        expected = mod_sub_reference(a, b)
        
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')
        
        result = int(dut.result.value)
        assert result == expected, \
            f"Random test {i} failed: {a} - {b} mod {Q} = {result}, expected {expected}"
        
        if (i + 1) % 20 == 0:
            dut._log.info(f"  Completed {i+1}/{num_tests} random tests")
    
    dut._log.info(f"✓ All {num_tests} random tests passed")

@cocotb.test()
async def test_boundary_values(dut):
    """Test boundary and edge cases"""
    dut._log.info("Testing boundary values")
    
    test_cases = [
        # Boundary cases
        (Q-1, Q-1, 0),      # Max - Max
        (Q-1, 0, Q-1),      # Max - 0
        (0, Q-1, 1),        # 0 - Max
        (Q-1, 1, Q-2),      # Max - 1
        (1, Q-1, 2),        # 1 - Max
        # Mid-range
        (Q//2, Q//2, 0),    # Half - Half
        (Q//2, 1, Q//2-1),  # Half - 1
        (1, Q//2, Q//2+2),  # 1 - half wraps under modulus
    ]
    
    for a, b, expected in test_cases:
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')
        
        result = int(dut.result.value)
        assert result == expected, \
            f"Boundary test failed: {a} - {b} mod {Q} = {result}, expected {expected}"
    
    dut._log.info("✓ Boundary value tests passed")

@cocotb.test()
async def test_result_always_in_range(dut):
    """Verify result is always in [0, Q-1]"""
    dut._log.info("Testing result range")
    
    random.seed(123)
    num_tests = 50
    
    for _ in range(num_tests):
        a = random.randint(0, Q-1)
        b = random.randint(0, Q-1)
        
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')
        
        result = int(dut.result.value)
        assert 0 <= result < Q, \
            f"Result out of range: {a} - {b} = {result}, should be in [0, {Q-1}]"
    
    dut._log.info(f"✓ All {num_tests} results in valid range [0, {Q-1}]")
