import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

WIDTH = 32
DEPTH = 256

@cocotb.test()
async def test_write_then_read_same_address(dut):
    """Test writing then immediately reading same address"""
    dut._log.info("Testing write-then-read same address")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 1
    dut.we_a.value = 0
    dut.we_b.value = 0
    await RisingEdge(dut.clk)
    
    # Write 0xDEADBEEF to address 5
    dut.addr_a.value = 5
    dut.din_a.value = 0xDEADBEEF
    dut.we_a.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")  # Wait for NBA to complete
    dut._log.info(f"After write cycle: dout_a = {hex(int(dut.dout_a.value))}")
    
    # Stop writing, keep same address
    dut.we_a.value = 0
    dut.addr_a.value = 5
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")  # Wait for NBA to complete
    result = int(dut.dout_a.value)
    dut._log.info(f"After read cycle: dout_a = {hex(result)}")
    
    assert result == 0xDEADBEEF, f"Failed: got {hex(result)}"
    dut._log.info("✓ Write-then-read same address works")

@cocotb.test()
async def test_two_sequential_writes(dut):
    """Test two writes to different addresses"""
    dut._log.info("Testing two sequential writes")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 1
    dut.we_a.value = 0
    dut.we_b.value = 0
    await RisingEdge(dut.clk)
    
    # Write to address 10
    dut._log.info("Writing 0xAAAAAAAA to address 10")
    dut.addr_a.value = 10
    dut.din_a.value = 0xAAAAAAAA
    dut.we_a.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut._log.info(f"  After write: dout_a = {hex(int(dut.dout_a.value))}")
    
    # Write to address 20
    dut._log.info("Writing 0xBBBBBBBB to address 20")
    dut.addr_a.value = 20
    dut.din_a.value = 0xBBBBBBBB
    dut.we_a.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut._log.info(f"  After write: dout_a = {hex(int(dut.dout_a.value))}")
    
    # Stop writing
    dut.we_a.value = 0
    await RisingEdge(dut.clk)
    
    # Read address 10
    dut._log.info("Reading from address 10")
    dut.addr_a.value = 10
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    result1 = int(dut.dout_a.value)
    dut._log.info(f"  Got: {hex(result1)}")
    
    # Read address 20
    dut._log.info("Reading from address 20")
    dut.addr_a.value = 20
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    result2 = int(dut.dout_a.value)
    dut._log.info(f"  Got: {hex(result2)}")
    
    assert result1 == 0xAAAAAAAA, f"Addr 10: got {hex(result1)}"
    assert result2 == 0xBBBBBBBB, f"Addr 20: got {hex(result2)}"
    dut._log.info("✓ Two sequential writes/reads work")

@cocotb.test()
async def test_write_loop_diagnostic(dut):
    """Diagnostic test for write loop behavior"""
    dut._log.info("Testing write loop with detailed logging")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.rst_n.value = 1
    dut.we_a.value = 0
    dut.we_b.value = 0
    await RisingEdge(dut.clk)
    
    # Write 3 values
    test_data = {0: 0x11111111, 1: 0x22222222, 2: 0x33333333}
    
    for addr, data in test_data.items():
        dut._log.info(f"Writing {hex(data)} to address {addr}")
        dut.addr_a.value = addr
        dut.din_a.value = data
        dut.we_a.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        dut._log.info(f"  dout_a after write = {hex(int(dut.dout_a.value))}")
    
    # Stop writing
    dut._log.info("Stopping writes")
    dut.we_a.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut._log.info(f"  dout_a = {hex(int(dut.dout_a.value))}")
    
    # Try various read approaches
    dut._log.info("\n=== Approach 1: Direct read ===")
    for addr, expected in test_data.items():
        dut.addr_a.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        result = int(dut.dout_a.value)
        dut._log.info(f"Addr {addr}: expected {hex(expected)}, got {hex(result)}")
    
    dut._log.info("✓ Diagnostic complete")
