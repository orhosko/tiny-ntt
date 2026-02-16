"""
Cocotb integration test for NTT-based polynomial multiplication.
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os
import random

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from refs.ntt_forward_reference import ntt_forward_reference, N, Q, PSI
from refs.ntt_inverse_reference import ntt_inverse_reference


async def load_poly(dut, poly, sel):
    """Load polynomial coefficients into A or B memory."""
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)

    dut.load_sel.value = sel
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = poly[addr] if addr < len(poly) else 0
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)


def python_poly_mult(poly_a, poly_b):
    """Reference polynomial multiplication using forward+inverse NTT."""
    a_ntt = ntt_forward_reference(poly_a, N, Q, PSI)
    b_ntt = ntt_forward_reference(poly_b, N, Q, PSI)
    c_ntt = [(a_ntt[i] * b_ntt[i]) % Q for i in range(N)]
    return ntt_inverse_reference(c_ntt, N, Q, PSI)


async def run_ntt_mult(dut):
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await RisingEdge(dut.clk)

    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")


async def read_result(dut):
    results = []
    for addr in range(N):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        results.append(int(dut.read_data.value))
    return results


@cocotb.test()
async def test_poly_mult_simple(dut):
    """Multiply small polynomials and compare to Python reference."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    poly_a = [1, 2, 3] + [0] * (N - 3)
    poly_b = [5, 1] + [0] * (N - 2)

    await load_poly(dut, poly_a, 0)
    await load_poly(dut, poly_b, 1)

    await run_ntt_mult(dut)

    hw = await read_result(dut)
    expected = python_poly_mult(poly_a, poly_b)

    mismatches = [i for i in range(N) if hw[i] != expected[i]]
    if mismatches:
        dut._log.error(f"Mismatches at indices: {mismatches[:10]}")
        dut._log.error(f"HW first 16: {hw[:16]}")
        dut._log.error(f"EXP first 16: {expected[:16]}")
    assert not mismatches, f"Mismatches at indices: {mismatches[:10]}"


@cocotb.test()
async def test_poly_mult_random(dut):
    """Random polynomial multiplication check."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.start.value = 0
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    random.seed(123)
    poly_a = [random.randint(0, Q - 1) for _ in range(N)]
    poly_b = [random.randint(0, Q - 1) for _ in range(N)]

    await load_poly(dut, poly_a, 0)
    await load_poly(dut, poly_b, 1)

    await run_ntt_mult(dut)

    hw = await read_result(dut)
    expected = python_poly_mult(poly_a, poly_b)

    mismatches = [i for i in range(N) if hw[i] != expected[i]]
    if mismatches:
        dut._log.error(f"Mismatches at indices: {mismatches[:10]}")
        dut._log.error(f"HW first 16: {hw[:16]}")
        dut._log.error(f"EXP first 16: {expected[:16]}")
    assert not mismatches, f"Mismatches at indices: {mismatches[:10]}"


