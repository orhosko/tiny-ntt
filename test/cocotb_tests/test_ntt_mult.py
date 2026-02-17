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


def pack_polynomial(values):
    """Pack coefficient list into a flat integer."""
    packed = 0
    for i, coeff in enumerate(values):
        packed |= int(coeff) << (i * WIDTH)
    return packed


def unpack_polynomial(packed, n):
    """Unpack flat integer into coefficient list."""
    mask = (1 << WIDTH) - 1
    return [(packed >> (i * WIDTH)) & mask for i in range(n)]


def set_polynomial(dut_signal, values):
    """Helper to set packed polynomial values."""
    dut_signal.value = pack_polynomial(values)


def get_polynomial(dut_signal, n):
    """Helper to get polynomial array values from packed signal."""
    return unpack_polynomial(int(dut_signal.value), n)


@cocotb.test()
async def test_basic_multiplication(dut):
    """Test basic multiplication with known values"""

    reduction_type = os.environ.get("REDUCTION_TYPE", "0")
    reduction_names = {"0": "SIMPLE", "1": "BARRETT", "2": "MONTGOMERY"}
    reduction_name = reduction_names.get(reduction_type, f"UNKNOWN({reduction_type})")
    dut._log.info(f"Testing with REDUCTION_TYPE={reduction_type} ({reduction_name})")
    dut._log.info("Testing basic multiplication with known values")

    poly_a = [i for i in range(N)]
    poly_b = [1 for _ in range(N)]

    set_polynomial(dut.poly_a_flat, poly_a)
    set_polynomial(dut.poly_b_flat, poly_b)

    await Timer(10, unit="ns")

    result = get_polynomial(dut.poly_c_flat, N)
    expected = [python_mod_mult(poly_a[i], poly_b[i]) for i in range(N)]

    for i in range(N):
        assert result[i] == expected[i], (
            f"Index {i}: Expected {expected[i]}, got {result[i]}"
        )

    dut._log.info("✓ Identity multiplication test passed")


@cocotb.test()
async def test_random_values(dut):
    """Test with random coefficient values"""
    dut._log.info("Testing with random values (100 iterations)")

    random.seed(42)  # For reproducibility
    num_tests = 100

    for test_num in range(num_tests):
        poly_a = [random.randint(0, Q - 1) for _ in range(N)]
        poly_b = [random.randint(0, Q - 1) for _ in range(N)]

        set_polynomial(dut.poly_a_flat, poly_a)
        set_polynomial(dut.poly_b_flat, poly_b)

        await Timer(10, unit="ns")

        result = get_polynomial(dut.poly_c_flat, N)
        expected = [python_mod_mult(poly_a[i], poly_b[i]) for i in range(N)]

        for i in range(N):
            assert result[i] == expected[i], (
                f"Random test {test_num}, Index {i}: Expected {expected[i]}, got {result[i]}"
            )

        if (test_num + 1) % 20 == 0:
            dut._log.info(f"  Completed {test_num + 1}/{num_tests} random tests")

    dut._log.info(f"✓ All {num_tests} random tests passed")


@cocotb.test()
async def test_all_positions(dut):
    """Test that all 256 multiplier positions work correctly"""
    dut._log.info("Testing all multiplier positions independently")

    errors = []

    for pos in range(N):
        poly_a = [0] * N
        poly_b = [0] * N
        poly_a[pos] = random.randint(1, Q - 1)
        poly_b[pos] = random.randint(1, Q - 1)

        set_polynomial(dut.poly_a_flat, poly_a)
        set_polynomial(dut.poly_b_flat, poly_b)

        await Timer(10, unit="ns")

        result = get_polynomial(dut.poly_c_flat, N)
        expected = python_mod_mult(poly_a[pos], poly_b[pos])

        for i in range(N):
            if i == pos:
                if result[i] != expected:
                    errors.append(f"Position {pos}: Expected {expected}, got {result[i]}")
            else:
                if result[i] != 0:
                    errors.append(
                        f"Position {i}: Expected 0, got {result[i]} (testing pos {pos})"
                    )

    assert len(errors) == 0, "Position-specific errors:\n" + "\n".join(errors)
    dut._log.info(f"✓ All {N} multiplier positions tested successfully")
