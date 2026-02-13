"""
Simple test: Can we write and read data correctly?
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

N = 256

async def simple_write_read_test(dut):
    """Test basic write/read without any NTT operation"""
    dut._log.info("="*60)
    dut._log.info("SIMPLE WRITE/READ TEST")
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
    
    # Write known pattern
    test_pattern = [i for i in range(N)]
    dut._log.info("Writing pattern: [0, 1, 2, 3, ...]")
    
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = test_pattern[addr]
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)  # Extra cycles
    await RisingEdge(dut.clk)
    
    # Read back
    dut._log.info("Reading back...")
    results = []
    for addr in range(N):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        value = int(dut.read_data.value)
        results.append(value)
    
    # Check
    mismatches = sum(1 for i in range(N) if results[i] != test_pattern[i])
    
    if mismatches == 0:
        dut._log.info("✓ PASS: Write/read works perfectly!")
    else:
        dut._log.error(f"✗ FAIL: {mismatches} mismatches")
        for i in range(min(10, N)):
            if results[i] != test_pattern[i]:
                dut._log.error(f"  [{i}]: wrote {test_pattern[i]}, read {results[i]}")
    
    return mismatches == 0

@cocotb.test()
async def test_write_read(dut):
    """Test if basic write/read works"""
    result = await simple_write_read_test(dut)
    assert result, "Basic write/read failed"

@cocotb.test()
async def test_read_after_done(dut):
    """Test reading AFTER intt done signal"""
    dut._log.info("="*60)
    dut._log.info("TEST: Read timing after DONE")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load [1, 1, 1, ...]
    input_data = [1] * N
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = input_data[addr]
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Start INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for DONE
    cycles = 0
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 15000:
            raise RuntimeError("Timeout")
    
    dut._log.info(f"  DONE asserted at cycle {cycles}")
    
    # Wait additional cycles AFTER done
    for i in range(10):
        await RisingEdge(dut.clk)
    
    dut._log.info("  Waiting 10 extra cycles after DONE")
    
    # Now read
    results = []
    for addr in range(N):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        value = int(dut.read_data.value)
        results.append(value)
    
    dut._log.info(f"  Results: {results[:10]}")
    dut._log.info(f"  Expected: [1, 0, 0, 0, ...]")
    
    # First element after full INTT+scaling should be 1
    if results[0] == 1:
        dut._log.info("  ✓ First element correct!")
    else:
        dut._log.error(f"  ✗ First element wrong: got {results[0]}, expected 1")

@cocotb.test()
async def test_state_during_read(dut):
    """Check what state we're in when reading"""
    dut._log.info("="*60)
    dut._log.info("TEST: State monitoring during read")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load [1,1,1,...]
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = 1
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Start INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for done
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
    
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    # Check state
    if hasattr(dut, 'state'):
        state = int(dut.state.value)
        state_names = {0: "IDLE", 1: "INTT_COMPUTE", 2: "SCALE", 3: "DONE_STATE"}
        dut._log.info(f"  State when reading: {state_names.get(state, state)}")
    
    # Read first few values and check RAM port status
    for addr in range(5):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        value = int(dut.read_data.value)
        dut._log.info(f"  RAM[{addr}] = {value}")
