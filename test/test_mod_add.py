"""
Cocotb testbench for modular adder (mod_add)
Tests (a + b) mod Q operation for NTT arithmetic
"""

import cocotb
from cocotb.triggers import Timer
import random

# Test parameters
WIDTH = 32
Q = 3329  # Kyber/Dilithium prime

def mod_add_reference(a, b, q=Q):
    """Python reference implementation of modular addition"""
    return (a + b) % q

@cocotb.test()
async def test_basic_addition(dut):
    """Test basic modular addition cases"""
    dut._log.info("Testing basic modular addition")
    
    test_cases = [
        (0, 0, 0),          # Zero + zero
        (1, 0, 1),          # Identity
        (0, 1, 1),          # Identity (commutative)
        (1, 1, 2),          # Simple addition
        (100, 200, 300),    # Normal case
        (Q-1, 0, Q-1),      # Max value
        (Q-1, 1, 0),        # Wraparound
        (Q-1, Q-1, Q-2),    # Double max
        (1000, 2000, 3000), # Larger values
        (2000, 2000, 671),  # Sum > Q
    ]
    
    for a, b, expected in test_cases:
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')  # Wait for combinational logic
        
        result = int(dut.result.value)
        assert result == expected, \
            f"Addition failed: {a} + {b} mod {Q} = {result}, expected {expected}"
    
    dut._log.info(f"✓ All {len(test_cases)} basic addition tests passed")

@cocotb.test()
async def test_commutative(dut):
    """Test that addition is commutative: a + b = b + a"""
    dut._log.info("Testing commutativity")
    
    test_pairs = [
        (10, 20),
        (100, 200),
        (1000, 2000),
        (Q-1, 1),
        (500, 1500),
    ]
    
    for a, b in test_pairs:
        # Test a + b
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')
        result_ab = int(dut.result.value)
        
        # Test b + a
        dut.a.value = b
        dut.b.value = a
        await Timer(1, unit='ns')
        result_ba = int(dut.result.value)
        
        assert result_ab == result_ba, \
            f"Commutativity failed: {a}+{b}={result_ab} but {b}+{a}={result_ba}"
    
    dut._log.info(f"✓ Commutativity verified for {len(test_pairs)} pairs")

@cocotb.test()
async def test_associative(dut):
    """Test that addition is associative: (a + b) + c = a + (b + c)"""
    dut._log.info("Testing associativity")
    
    test_triples = [
        (10, 20, 30),
        (100, 200, 300),
        (500, 1000, 1500),
        (Q-1, 1, 1),
    ]
    
    for a, b, c in test_triples:
        # Compute (a + b) + c
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')
        ab = int(dut.result.value)
        
        dut.a.value = ab
        dut.b.value = c
        await Timer(1, unit='ns')
        result_1 = int(dut.result.value)
        
        # Compute a + (b + c)
        dut.a.value = b
        dut.b.value = c
        await Timer(1, unit='ns')
        bc = int(dut.result.value)
        
        dut.a.value = a
        dut.b.value = bc
        await Timer(1, unit='ns')
        result_2 = int(dut.result.value)
        
        assert result_1 == result_2, \
            f"Associativity failed: ({a}+{b})+{c}={result_1} but {a}+({b}+{c})={result_2}"
    
    dut._log.info(f"✓ Associativity verified for {len(test_triples)} triples")

@cocotb.test()
async def test_identity(dut):
    """Test that 0 is the additive identity"""
    dut._log.info("Testing additive identity")
    
    test_values = [0, 1, 10, 100, 1000, Q-1, Q//2]
    
    for val in test_values:
        # Test val + 0
        dut.a.value = val
        dut.b.value = 0
        await Timer(1, unit='ns')
        result = int(dut.result.value)
        assert result == val, f"Identity failed: {val} + 0 = {result}, expected {val}"
        
        # Test 0 + val
        dut.a.value = 0
        dut.b.value = val
        await Timer(1, unit='ns')
        result = int(dut.result.value)
        assert result == val, f"Identity failed: 0 + {val} = {result}, expected {val}"
    
    dut._log.info(f"✓ Identity verified for {len(test_values)} values")

@cocotb.test()
async def test_modular_reduction(dut):
    """Test that modular reduction works correctly"""
    dut._log.info("Testing modular reduction")
    
    test_cases = [
        (Q, 0, 0),          # Exactly Q
        (Q-1, 1, 0),        # Wraparound to 0
        (Q-1, 2, 1),        # Wraparound to 1
        (Q//2, Q//2, Q-1),  # Two halves
        (Q, Q, 0),          # 2Q
        (Q+1, 0, 1),        # Q+1
        (Q+100, 0, 100),    # Q+100
    ]
    
    for a, b, expected in test_cases:
        # Ensure inputs are within valid range
        a_mod = a % Q
        b_mod = b % Q
        
        dut.a.value = a_mod
        dut.b.value = b_mod
        await Timer(1, unit='ns')
        
        result = int(dut.result.value)
        expected_calc = (a_mod + b_mod) % Q
        
        assert result == expected_calc, \
            f"Reduction failed: {a_mod} + {b_mod} mod {Q} = {result}, expected {expected_calc}"
    
    dut._log.info("✓ Modular reduction tests passed")

@cocotb.test()
async def test_random_values(dut):
    """Test with random values"""
    dut._log.info("Testing with random values")
    
    random.seed(42)  # Reproducible tests
    num_tests = 100
    
    for i in range(num_tests):
        a = random.randint(0, Q-1)
        b = random.randint(0, Q-1)
        expected = mod_add_reference(a, b)
        
        dut.a.value = a
        dut.b.value = b
        await Timer(1, unit='ns')
        
        result = int(dut.result.value)
        assert result == expected, \
            f"Random test {i} failed: {a} + {b} mod {Q} = {result}, expected {expected}"
        
        if (i + 1) % 20 == 0:
            dut._log.info(f"  Completed {i+1}/{num_tests} random tests")
    
    dut._log.info(f"✓ All {num_tests} random tests passed")

@cocotb.test()
async def test_edge_cases(dut):
    """Test edge cases"""
    dut._log.info("Testing edge cases")
    
    # Maximum values
    dut.a.value = Q-1
    dut.b.value = Q-1
    await Timer(1, unit='ns')
    result = int(dut.result.value)
    expected = (Q-1 + Q-1) % Q
    assert result == expected, f"Max+Max failed: got {result}, expected {expected}"
    
    # All zeros
    dut.a.value = 0
    dut.b.value = 0
    await Timer(1, unit='ns')
    result = int(dut.result.value)
    assert result == 0, f"Zero+Zero failed: got {result}, expected 0"
    
    dut._log.info("✓ Edge cases passed")
