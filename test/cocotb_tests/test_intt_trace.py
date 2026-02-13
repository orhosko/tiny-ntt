"""
Deep diagnostic tests with extensive logging
Track RAM signals during read operations
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

N = 256
Q = 8380417

@cocotb.test()
async def test_trace_ram_signals(dut):
    """Trace RAM control signals during read"""
    dut._log.info("="*60)
    dut._log.info("TRACE: RAM Signals During Read")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load simple pattern
    dut._log.info("Loading: RAM[0]=100, RAM[1]=200, RAM[2]=300")
    test_data = {0: 100, 1: 200, 2: 300}
    
    for addr, value in test_data.items():
        dut.load_addr.value = addr  
        dut.load_data.value = value
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Now trace a read operation in detail
    dut._log.info("\nTracing read of RAM[0]...")
    dut.read_addr.value = 0
    
    # Log signals BEFORE the clock edge
    dut._log.info(f"  BEFORE clock:")
    dut._log.info(f"    read_addr = {int(dut.read_addr.value)}")
    if hasattr(dut, 'state'):
        dut._log.info(f"    state = {int(dut.state.value)}")
    if hasattr(dut.u_coeff_ram, 'addr_a'):
        dut._log.info(f"    RAM addr_a = {int(dut.u_coeff_ram.addr_a.value)}")  
    if hasattr(dut.u_coeff_ram, 'dout_a'):
        dut._log.info(f"    RAM dout_a = {int(dut.u_coeff_ram.dout_a.value)}")
    dut._log.info(f"    read_data = {int(dut.read_data.value)}")
    
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    # Log signals AFTER the clock edge
    dut._log.info(f"  AFTER clock:")
    if hasattr(dut.u_coeff_ram, 'addr_a'):
        dut._log.info(f"    RAM addr_a = {int(dut.u_coeff_ram.addr_a.value)}")
    if hasattr(dut.u_coeff_ram, 'dout_a'):
        dut._log.info(f"    RAM dout_a = {int(dut.u_coeff_ram.dout_a.value)}")
    dut._log.info(f"    read_data = {int(dut.read_data.value)}")
    
    result = int(dut.read_data.value)
    dut._log.info(f"\n  Result: {result}")
    dut._log.info(f"  Expected: 100")
    
    if result == 100:
        dut._log.info("  ✓ Read worked!")
    else:
        dut._log.error(f"  ✗ Read failed: got {result}, expected 100")
    
    assert result == 100

@cocotb.test()
async def test_trace_after_intt(dut):
    """Trace RAM signals after INTT completes"""
    dut._log.info("="*60)
    dut._log.info("TRACE: RAM After INTT")
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
    dut._log.info("Loading [1,1,1,...]")
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = 1
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Run INTT
    dut._log.info("Running INTT...")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
    
    dut._log.info("INTT done=1")
    
    # Log state immediately after done
    if hasattr(dut, 'state'):
        state = int(dut.state.value)
        state_names = {0: "IDLE", 1: "INTT_COMPUTE", 2: "SCALE", 3: "DONE_STATE"}
        dut._log.info(f"  State: {state_names.get(state, state)}")
    
    # Wait various amounts and check what we read
    for wait_cycles in [0, 1, 2, 5, 10]:
        dut._log.info(f"\nReading after {wait_cycles} extra cycles:")
        
        for _ in range(wait_cycles):
            await RisingEdge(dut.clk)
        
        # Try reading RAM[0]
        dut.read_addr.value = 0
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        
        # Log all signals
        if hasattr(dut, 'state'):
            state = int(dut.state.value)
            dut._log.info(f"  state = {state}")
        if hasattr(dut, 'ram_addr_a'):
            dut._log.info(f"  ram_addr_a = {int(dut.ram_addr_a.value)}")
        if hasattr(dut.u_coeff_ram, 'addr_a'):
            dut._log.info(f"  u_coeff_ram.addr_a = {int(dut.u_coeff_ram.addr_a.value)}")
        if hasattr(dut.u_coeff_ram, 'dout_a'):
            dut._log.info(f"  u_coeff_ram.dout_a = {int(dut.u_coeff_ram.dout_a.value)}")
        if hasattr(dut, 'ram_dout_a'):
            dut._log.info(f"  ram_dout_a = {int(dut.ram_dout_a.value)}")
        
        result = int(dut.read_data.value)
        dut._log.info(f"  read_data = {result}")
        dut._log.info(f"  Expected: 1")

@cocotb.test()
async def test_check_ram_contents(dut):
    """Directly check RAM array contents if accessible"""
    dut._log.info("="*60)
    dut._log.info("CHECK: Direct RAM Contents")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load testpattern
    dut._log.info("Loading [1,1,1,...]")
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = 1
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Try to access RAM array directly if possible
    if hasattr(dut.u_coeff_ram, 'mem'):
        dut._log.info("  RAM array accessible!")
        for i in range(5):
            try:
                value = int(dut.u_coeff_ram.mem[i].value)
                dut._log.info(f"    RAM.mem[{i}] = {value}")
            except:
                dut._log.info(f"    RAM.mem[{i}] = (not accessible)")
    else:
        dut._log.info("  RAM array not directly accessible")
    
    # Run INTT
    dut._log.info("\nRunning INTT...")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
    
    # Check RAM contents after INTT
    dut._log.info("\nAfter INTT:")
    if hasattr(dut.u_coeff_ram, 'mem'):
        for i in range(5):
            try:
                value = int(dut.u_coeff_ram.mem[i].value)
                dut._log.info(f"    RAM.mem[{i}] = {value}")
            except:
                dut._log.info(f"    RAM.mem[{i}] = (not accessible)")

@cocotb.test()
async def test_read_all_addresses(dut):
    """Read all 256 addresses and show pattern"""
    dut._log.info("="*60)
    dut._log.info("READ ALL: Check for patterns")
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
    
    # Run INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
    
    # Wait
    for _ in range(10):
        await RisingEdge(dut.clk)
    
    # Read ALL addresses
    all_values = []
    for addr in range(N):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        all_values.append(int(dut.read_data.value))
    
    # Analyze pattern
    dut._log.info(f"First 20 values: {all_values[:20]}")
    dut._log.info(f"Last 20 values: {all_values[-20:]}")
    
    # Check if all same
    unique_values = set(all_values)
    dut._log.info(f"Unique values found: {len(unique_values)}")
    
    if len(unique_values) == 1:
        dut._log.error(f"  ALL addresses return same value: {all_values[0]}")
    elif len(unique_values) < 10:
        dut._log.error(f"  Only {len(unique_values)} unique values!")
        dut._log.error(f"  Values: {sorted(unique_values)[:10]}")
    else:
        dut._log.info(f"  Many unique values (good sign)")
    
    # Check if it's a repeating pattern
    if all_values[:10] == all_values[10:20]:
        dut._log.error("  Pattern repeats every 10 values!")
    
    # The stale pattern we keep seeing
    stale_pattern = [1352, 1467, 1806, 2979, 2442, 3088, 2937, 205, 1328, 2091]
    if all_values[:10] == stale_pattern:
        dut._log.error(f"  ✗ Got the STALE PATTERN again!")
        dut._log.error(f"  This means we're reading cached/wrong data")
