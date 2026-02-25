"""
Test inverse NTT butterfly unit
Compare hardware against Python reference
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import random

Q = 8380417
PSI = 1239911
PSI_INV = pow(PSI, Q - 2, Q)
MULT_PIPELINE = 3
CLOCK_PERIOD_NS = 1


async def init_dut(dut):
    cocotb.start_soon(Clock(dut.clk, CLOCK_PERIOD_NS, units="ns").start())
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def apply_and_capture(dut, a, b, twiddle):
    dut.a.value = a
    dut.b.value = b
    dut.twiddle.value = twiddle
    for _ in range(MULT_PIPELINE + 1):
        await RisingEdge(dut.clk)
    await Timer(1, unit="ps")
    return int(dut.a_out.value), int(dut.b_out.value)


def mod_add(a, b, q=Q):
    return (a + b) % q


def mod_sub(a, b, q=Q):
    return (a - b) % q


def mod_mult(a, b, q=Q):
    return (a * b) % q


def inverse_butterfly_ref(a, b, twiddle, q=Q):
    """
    Reference inverse NTT butterfly (Gentleman-Sande)
    a' = a + b
    b' = (a - b) * twiddle
    """
    a_out = mod_add(a, b, q)
    b_out = mod_mult(mod_sub(a, b, q), twiddle, q)
    return a_out, b_out


@cocotb.test()
async def test_inverse_butterfly_basic(dut):
    """Test basic inverse butterfly operation"""
    dut._log.info("=" * 60)
    dut._log.info("TEST: Inverse Butterfly Basic")
    dut._log.info("=" * 60)
    await init_dut(dut)

    # Test case 1: Simple values
    test_cases = [
        (100, 50, PSI, "Simple values"),
        (1, 1, 1, "All ones"),
        (256, 0, PSI_INV, "With zero"),
        (Q - 1, Q - 1, Q - 1, "Near modulus"),
        (0, 0, 0, "All zeros"),
    ]

    errors = 0
    for a, b, tw, desc in test_cases:
        hw_a, hw_b = await apply_and_capture(dut, a, b, tw)

        py_a, py_b = inverse_butterfly_ref(a, b, tw)

        dut._log.info(f"\n{desc}:")
        dut._log.info(f"  Input: a={a}, b={b}, twiddle={tw}")
        dut._log.info(f"  Python: a'={py_a}, b'={py_b}")
        dut._log.info(f"  Hardware: a'={hw_a}, b'={hw_b}")

        if hw_a != py_a or hw_b != py_b:
            dut._log.error(f"  ✗ MISMATCH!")
            dut._log.error(f"    a_out: HW={hw_a}, PY={py_a}, diff={hw_a - py_a}")
            dut._log.error(f"    b_out: HW={hw_b}, PY={py_b}, diff={hw_b - py_b}")
            errors += 1
        else:
            dut._log.info(f"  ✓ Match")

    assert errors == 0, f"{errors} test cases failed"
    dut._log.info(f"\n✓ All {len(test_cases)} test cases passed!")


@cocotb.test()
async def test_inverse_butterfly_random(dut):
    """Test with random values"""
    dut._log.info("=" * 60)
    dut._log.info("TEST: Inverse Butterfly Random")
    dut._log.info("=" * 60)
    await init_dut(dut)

    random.seed(12345)
    num_tests = 50
    errors = 0

    for i in range(num_tests):
        a = random.randint(0, Q - 1)
        b = random.randint(0, Q - 1)
        tw = random.randint(0, Q - 1)

        hw_a, hw_b = await apply_and_capture(dut, a, b, tw)

        py_a, py_b = inverse_butterfly_ref(a, b, tw)

        if hw_a != py_a or hw_b != py_b:
            dut._log.error(f"\nTest {i + 1}: FAIL")
            dut._log.error(f"  Input: a={a}, b={b}, twiddle={tw}")
            dut._log.error(f"  Python: a'={py_a}, b'={py_b}")
            dut._log.error(f"  Hardware: a'={hw_a}, b'={hw_b}")
            errors += 1
            if errors >= 5:  # Stop after 5 errors
                break

    if errors == 0:
        dut._log.info(f"✓ All {num_tests} random tests passed!")

    assert errors == 0, f"{errors} random tests failed"


@cocotb.test()
async def test_compare_forward_vs_inverse(dut):
    """Show the difference between forward and inverse butterfly"""
    dut._log.info("=" * 60)
    dut._log.info("TEST: Compare Forward vs Inverse Butterfly")
    dut._log.info("=" * 60)
    await init_dut(dut)

    # Test values
    a, b, tw = 100, 50, 17

    inv_a, inv_b = await apply_and_capture(dut, a, b, tw)

    # Inverse butterfly (what hardware does)

    # Forward butterfly (for comparison)
    fwd_a = mod_add(a, mod_mult(b, tw))
    fwd_b = mod_sub(a, mod_mult(b, tw))

    dut._log.info(f"Input: a={a}, b={b}, twiddle={tw}")
    dut._log.info(f"\nForward Butterfly (Cooley-Tukey):")
    dut._log.info(f"  a' = a + b*tw = {fwd_a}")
    dut._log.info(f"  b' = a - b*tw = {fwd_b}")
    dut._log.info(f"\nInverse Butterfly (Gentleman-Sande):")
    dut._log.info(f"  a' = a + b = {inv_a}")
    dut._log.info(f"  b' = (a - b)*tw = {inv_b}")
    dut._log.info(f"\nThey are DIFFERENT - as expected!")


@cocotb.test()
async def test_inverse_butterfly_properties(dut):
    """Test mathematical properties"""
    dut._log.info("=" * 60)
    dut._log.info("TEST: Inverse Butterfly Properties")
    dut._log.info("=" * 60)
    await init_dut(dut)

    # Property 1: When twiddle=1, b' = a - b
    a, b = 200, 50
    hw_a, hw_b = await apply_and_capture(dut, a, b, 1)

    expected_a = mod_add(a, b)
    expected_b = mod_sub(a, b)

    dut._log.info("Property 1: When twiddle=1")
    dut._log.info(f"  a' should be a+b = {expected_a}, got {hw_a}")
    dut._log.info(f"  b' should be a-b = {expected_b}, got {hw_b}")

    assert hw_a == expected_a and hw_b == expected_b
    dut._log.info("  ✓ Property holds!")

    # Property 2: When a=b, a'=2a mod q, b'=0
    a = 100
    hw_a, hw_b = await apply_and_capture(dut, a, a, 999)

    expected_a = (2 * a) % Q
    expected_b = 0

    dut._log.info("\nProperty 2: When a=b")
    dut._log.info(f"  a' should be 2*a mod q = {expected_a}, got {hw_a}")
    dut._log.info(f"  b' should be 0 (regardless of twiddle), got {hw_b}")

    assert hw_a == expected_a and hw_b == expected_b
    dut._log.info("  ✓ Property holds!")
