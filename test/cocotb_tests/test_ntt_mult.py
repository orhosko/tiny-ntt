"""
Cocotb testbench for NTT Pointwise Multiplication Unit

Tests the ntt_pointwise_mult module which performs parallel pointwise
multiplication of two NTT-domain polynomials.
"""

import cocotb
from cocotb.triggers import Timer
import random
import os

# Design parameters
N = 256       # Polynomial degree
WIDTH = 32    # Coefficient width
Q = 8380417


def python_mod_mult(a, b, q=Q):
    """Reference model for modular multiplication"""
    return (a * b) % q


def set_polynomial(dut_array, values):
    """Helper to set polynomial array values"""
    for i in range(len(values)):
        dut_array[i].value = values[i]


def get_polynomial(dut_array, n):
    """Helper to get polynomial array values"""
    return [int(dut_array[i].value) for i in range(n)]


@cocotb.test()
async def test_basic_multiplication(dut):
    """Test basic multiplication with known values"""
    
    # Log reduction type (from compilation)
    reduction_type = os.environ.get('REDUCTION_TYPE', '0')
    reduction_names = {' 0': 'SIMPLE', '1': 'BARRETT', '2': 'MONTGOMERY'}
    reduction_name = reduction_names.get(reduction_type, f'UNKNOWN({reduction_type})')
    dut._log.info(f"Testing with REDUCTION_TYPE={reduction_type} ({reduction_name})")
    dut._log.info("Testing basic multiplication with known values")
    
    # Test case 1: Multiply by 1 (identity)
    poly_a = [i for i in range(N)]
    poly_b = [1 for _ in range(N)]
    
    set_polynomial(dut.poly_a, poly_a)
    set_polynomial(dut.poly_b, poly_b)
    
    await Timer(10, unit='ns')  # Wait for combinational logic
    
    result = get_polynomial(dut.poly_c, N)
    expected = [python_mod_mult(poly_a[i], poly_b[i]) for i in range(N)]
    
    for i in range(N):
        assert result[i] == expected[i], \
            f"Index {i}: Expected {expected[i]}, got {result[i]}"
    
    dut._log.info("✓ Identity multiplication test passed")


@cocotb.test()
async def test_zero_multiplication(dut):
    """Test multiplication with zero"""
    dut._log.info("Testing multiplication with zero")
    
    # Test case: Multiply by 0
    poly_a = [i for i in range(N)]
    poly_b = [0 for _ in range(N)]
    
    set_polynomial(dut.poly_a, poly_a)
    set_polynomial(dut.poly_b, poly_b)
    
    await Timer(10, unit='ns')
    
    result = get_polynomial(dut.poly_c, N)
    
    for i in range(N):
        assert result[i] == 0, \
            f"Index {i}: Expected 0, got {result[i]}"
    
    dut._log.info("✓ Zero multiplication test passed")


@cocotb.test()
async def test_modular_reduction(dut):
    """Test that results are properly reduced modulo Q"""
    dut._log.info("Testing modular reduction")
    
    # Use large values that require modular reduction
    poly_a = [Q - 1 for _ in range(N)]
    poly_b = [Q - 1 for _ in range(N)]
    
    set_polynomial(dut.poly_a, poly_a)
    set_polynomial(dut.poly_b, poly_b)
    
    await Timer(10, unit='ns')
    
    result = get_polynomial(dut.poly_c, N)
    expected = [python_mod_mult(Q - 1, Q - 1) for _ in range(N)]
    
    for i in range(N):
        # Check result is in valid range
        assert 0 <= result[i] < Q, \
            f"Index {i}: Result {result[i]} not in range [0, {Q})"
        # Check correctness
        assert result[i] == expected[i], \
            f"Index {i}: Expected {expected[i]}, got {result[i]}"
    
    dut._log.info(f"✓ Modular reduction test passed (result = {expected[0]})")


@cocotb.test()
async def test_edge_cases(dut):
    """Test edge case values"""
    dut._log.info("Testing edge cases")
    
    # Test with various edge cases
    test_cases = [
        ([1] * N, [Q - 1] * N),           # 1 * (q-1)
        ([2] * N, [Q // 2] * N),          # 2 * (q/2)
        ([Q - 1] * N, [2] * N),           # (q-1) * 2
    ]
    
    for idx, (poly_a, poly_b) in enumerate(test_cases):
        set_polynomial(dut.poly_a, poly_a)
        set_polynomial(dut.poly_b, poly_b)
        
        await Timer(10, unit='ns')
        
        result = get_polynomial(dut.poly_c, N)
        expected = [python_mod_mult(poly_a[i], poly_b[i]) for i in range(N)]
        
        for i in range(N):
            assert result[i] == expected[i], \
                f"Test case {idx}, Index {i}: Expected {expected[i]}, got {result[i]}"
        
        dut._log.info(f"✓ Edge case {idx + 1} passed")


@cocotb.test()
async def test_random_values(dut):
    """Test with random coefficient values"""
    dut._log.info("Testing with random values (100 iterations)")
    
    random.seed(42)  # For reproducibility
    num_tests = 100
    
    for test_num in range(num_tests):
        # Generate random polynomials with values in [0, Q-1]
        poly_a = [random.randint(0, Q - 1) for _ in range(N)]
        poly_b = [random.randint(0, Q - 1) for _ in range(N)]
        
        set_polynomial(dut.poly_a, poly_a)
        set_polynomial(dut.poly_b, poly_b)
        
        await Timer(10, unit='ns')
        
        result = get_polynomial(dut.poly_c, N)
        expected = [python_mod_mult(poly_a[i], poly_b[i]) for i in range(N)]
        
        for i in range(N):
            assert result[i] == expected[i], \
                f"Random test {test_num}, Index {i}: Expected {expected[i]}, got {result[i]}"
        
        if (test_num + 1) % 20 == 0:
            dut._log.info(f"  Completed {test_num + 1}/{num_tests} random tests")
    
    dut._log.info(f"✓ All {num_tests} random tests passed")


@cocotb.test()
async def test_all_positions(dut):
    """Test that all 256 multiplier positions work correctly"""
    dut._log.info("Testing all multiplier positions independently")
    
    errors = []
    
    for pos in range(N):
        # Create polynomials with non-zero value only at position 'pos'
        poly_a = [0] * N
        poly_b = [0] * N
        poly_a[pos] = random.randint(1, Q - 1)
        poly_b[pos] = random.randint(1, Q - 1)
        
        set_polynomial(dut.poly_a, poly_a)
        set_polynomial(dut.poly_b, poly_b)
        
        await Timer(10, unit='ns')
        
        result = get_polynomial(dut.poly_c, N)
        expected = python_mod_mult(poly_a[pos], poly_b[pos])
        
        # Check that only position 'pos' is non-zero
        for i in range(N):
            if i == pos:
                if result[i] != expected:
                    errors.append(f"Position {pos}: Expected {expected}, got {result[i]}")
            else:
                if result[i] != 0:
                    errors.append(f"Position {i}: Expected 0, got {result[i]} (testing pos {pos})")
    
    assert len(errors) == 0, f"Position-specific errors:\n" + "\n".join(errors)
    dut._log.info(f"✓ All {N} multiplier positions tested successfully")
