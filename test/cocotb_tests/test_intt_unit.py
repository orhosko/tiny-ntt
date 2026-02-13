"""
Simple INTT unit tests with known data
Compare hardware results against Python reference for simple cases
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from refs.ntt_inverse_reference import ntt_inverse_reference, mod_inv

N = 256
Q = 8380417
PSI = 1239911
N_INV = mod_inv(N, Q)

@cocotb.test()
async def test_unit_01_all_ones(dut):
    """Unit test: INTT([1,1,1,...]) should give [256, 0, 0, ...] before scaling"""
    dut._log.info("="*60)
    dut._log.info("UNIT TEST 1: INTT([1,1,1,...]) - Known Values")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Python reference calculation
    input_data = [1] * N
    python_result = ntt_inverse_reference(input_data, N, Q, PSI)
    
    dut._log.info(f"  Input: [1, 1, 1, ...]")
    dut._log.info(f"  Python reference result: {python_result[:5]}")
    
    # Load [1,1,1,...]
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = 1
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Run INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for done
    cycles = 0
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 10000:
            raise RuntimeError("Timeout")
    
    dut._log.info(f"  INTT completed in {cycles} cycles")
    
    # Wait for data to settle
    for _ in range(10):
        await RisingEdge(dut.clk)
    
    # Read results
    results = []
    for addr in range(10):  # Just first 10
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        results.append(int(dut.read_data.value))
    
    dut._log.info(f"  Hardware result: {results}")
    dut._log.info(f"  Python result:   {python_result[:10]}")
    
    # Check first few values
    errors = 0
    for i in range(10):
        if results[i] != python_result[i]:
            dut._log.error(f"    [{i}]: HW={results[i]}, PY={python_result[i]}, diff={results[i]-python_result[i]}")
            errors += 1
    
    if errors == 0:
        dut._log.info("  ✓ PASS: Hardware matches Python reference!")
    else:
        dut._log.error(f"  ✗ FAIL: {errors} mismatches")
    
    assert errors == 0, f"{errors} mismatches with Python reference"

@cocotb.test()
async def test_unit_02_simple_vector(dut):
    """Unit test: INTT of simple vector [1,2,3,0,0,...]"""
    dut._log.info("="*60)
    dut._log.info("UNIT TEST 2: INTT([1,2,3,0,0,...]) - Simple Vector")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Input: [1,2,3,0,0,...]
    input_data = [1, 2, 3] + [0] * (N - 3)
    
    # Python reference
    python_result = ntt_inverse_reference(input_data, N, Q, PSI)
    
    dut._log.info(f"  Input: [1, 2, 3, 0, 0, ...]")
    dut._log.info(f"  Python result (first 5): {python_result[:5]}")
    
    # Load data
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = input_data[addr]
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Run INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for done
    cycles = 0
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 10000:
            raise RuntimeError("Timeout")
    
    # Wait
    for _ in range(10):
        await RisingEdge(dut.clk)
    
    # Read
    results = []
    for addr in range(10):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        results.append(int(dut.read_data.value))
    
    dut._log.info(f"  Hardware result: {results}")
    
    # Compare
    errors = 0
    for i in range(10):
        if results[i] != python_result[i]:
            dut._log.error(f"    [{i}]: HW={results[i]}, PY={python_result[i]}")
            errors += 1
    
    if errors == 0:
        dut._log.info("  ✓ PASS")
    
    assert errors == 0

@cocotb.test()
async def test_unit_03_check_ram_after_load(dut):
    """Unit test: Verify data is correctly loaded before INTT"""
    dut._log.info("="*60)
    dut._log.info("UNIT TEST 3: Verify RAM After Load")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load pattern [100, 101, 102, ...]
    pattern = [100 + i for i in range(20)]
    dut._log.info(f"  Loading: {pattern[:5]}...")
    
    for addr in range(20):
        dut.load_addr.value = addr
        dut.load_data.value = pattern[addr]
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Read back BEFORE running INTT
    dut._log.info("  Reading back before INTT...")
    readback = []
    for addr in range(20):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        readback.append(int(dut.read_data.value))
    
    dut._log.info(f"  Readback: {readback[:5]}...")
    
    # Verify
    errors = 0
    for i in range(20):
        if readback[i] != pattern[i]:
            dut._log.error(f"   [{i}]: wrote {pattern[i]}, read {readback[i]}")
            errors += 1
    
    if errors == 0:
        dut._log.info("  ✓ PASS: Load/read works correctly")
    else:
        dut._log.error(f"  ✗ FAIL: Can't even read what we wrote!")
    
    assert errors == 0, "Data not preserved in RAM!"

@cocotb.test()
async def test_unit_04_compare_single_address(dut):
    """Unit test: Track single RAM address through INTT"""
    dut._log.info("="*60)
    dut._log.info("UNIT TEST 4: Track RAM[0] Through INTT")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load all 1s
    input_data = [1] * N
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = 1
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Read RAM[0] before INTT
    dut.read_addr.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    before = int(dut.read_data.value)
    dut._log.info(f"  RAM[0] before INTT: {before}")
    
    # Run INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
    
    # Wait
    for _ in range(10):
        await RisingEdge(dut.clk)
    
    # Read RAM[0] after INTT
    dut.read_addr.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    after = int(dut.read_data.value)
    dut._log.info(f"  RAM[0] after INTT: {after}")
    
    # Python reference
    python_result = ntt_inverse_reference(input_data, N, Q, PSI)
    expected = python_result[0]
    dut._log.info(f"  Python says RAM[0] should be: {expected}")
    
    if after == expected:
        dut._log.info(f"  ✓ PASS: RAM[0] matches!")
    else:
        dut._log.error(f"  ✗ FAIL: RAM[0]={after}, expected={expected}")
    
    assert after == expected, f"RAM[0] mismatch: got {after}, expected {expected}"
