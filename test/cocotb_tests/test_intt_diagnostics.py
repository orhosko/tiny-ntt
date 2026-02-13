"""
Comprehensive diagnostic tests for INTT
Tests each component individually to find the exact failure point
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

N = 256
Q = 8380417
PSI = 1239911
PSI_INV = pow(PSI, Q - 2, Q)

@cocotb.test()
async def test_01_ram_write_read_idle(dut):
    """TEST 1: Can we write/read RAM in IDLE state?"""
    dut._log.info("="*60)
    dut._log.info("TEST 1: RAM Write/Read in IDLE State")
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
    
    # Write test pattern
    test_data = {0: 100, 5: 500, 10: 1000, 255: 2550}
    
    for addr, value in test_data.items():
        dut.load_addr.value =  addr
        dut.load_data.value = value
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Read back
    errors = 0
    for addr, expected in test_data.items():
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        got = int(dut.read_data.value)
        if got != expected:
            dut._log.error(f"  RAM[{addr}]: wrote {expected}, read {got}")
            errors += 1
    
    if errors == 0:
        dut._log.info("  ✓ PASS: RAM read/write works in IDLE")
    else:
        dut._log.error(f"  ✗ FAIL: {errors} errors")
    
    assert errors == 0

@cocotb.test()
async def test_02_control_signals_during_intt(dut):
    """TEST 2: Are control signals active during INTT?"""
    dut._log.info("="*60)
    dut._log.info("TEST 2: Control Signals During INTT")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load data
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
    
    # Monitor control signals during INTT_COMPUTE
    we_a_count = 0
    we_b_count = 0
    max_check = 1000
    
    for i in range(max_check):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        
        if hasattr(dut, 'state') and int(dut.state.value) == 1:  # INTT_COMPUTE
            # Check if write enables are active
            if hasattr(dut.u_coeff_ram, 'we_a'):
                if int(dut.u_coeff_ram.we_a.value) == 1:
                    we_a_count += 1
            if hasattr(dut.u_coeff_ram, 'we_b'):
                if int(dut.u_coeff_ram.we_b.value) == 1:
                    we_b_count += 1
        
        # Stop after leaving INTT_COMPUTE
        if hasattr(dut, 'state') and int(dut.state.value) == 2:  # SCALE
            break
    
    dut._log.info(f"  Write enables during INTT_COMPUTE:")
    dut._log.info(f"    we_a asserted: {we_a_count} times")
    dut._log.info(f"    we_b asserted: {we_b_count} times")
    
    if we_a_count > 0 or we_b_count > 0:
        dut._log.info("  ✓ PASS: Writes are happening during INTT")
    else:
        dut._log.error("  ✗ FAIL: NO writes during INTT!")
        dut._log.error("  This means INTT results are never written to RAM")
    
    assert (we_a_count + we_b_count) > 0, "No writes during INTT!"

@cocotb.test()
async def test_03_inverse_twiddle_rom(dut):
    """TEST 3: Is inverse twiddle ROM working?"""
    dut._log.info("="*60)
    dut._log.info("TEST 3: Inverse Twiddle ROM")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Check some known twiddle values
    expected_twiddles = {
        0: 1,                     # ψ^(-0) = 1
        1: PSI_INV,               # ψ^(-1)
        2: pow(PSI_INV, 2, Q),    # ψ^(-2)
    }
    
    if hasattr(dut, 'u_inverse_twiddle_rom'):
        dut._log.info(f"  ✓ Inverse twiddle ROM exists")
    else:
        dut._log.error("  ✗ Inverse twiddle ROM not found!")
        assert False, "ROM missing"

@cocotb.test()
async def test_04_scaling_signals(dut):
    """TEST 4: Are scaling signals active?"""
    dut._log.info("="*60)
    dut._log.info("TEST 4: Scaling Control Signals")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Load data
    for addr in range(N):
        dut.load_addr.value = addr
        dut.load_data.value = 100 + addr
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    
    # Start INTT
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for SCALE state
    scale_we_count = 0
    max_wait = 15000
    in_scale = False
    
    for i in range(max_wait):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        
        if hasattr(dut, 'state') and int(dut.state.value) == 2:  # SCALE
            in_scale = True
            # Check if scaling is writing
            if hasattr(dut, 'scale_we') and int(dut.scale_we.value) == 1:
                scale_we_count += 1
        
        if hasattr(dut, 'state') and int(dut.state.value) == 3:  # DONE
            break
    
    dut._log.info(f"  Entered SCALE state: {in_scale}")
    dut._log.info(f"  scale_we asserted: {scale_we_count} times")
    
    if scale_we_count > 0:
        dut._log.info("  ✓ PASS: Scaling writes are happening")
    else:
        dut._log.error("  ✗ FAIL: NO scaling writes!")
    
    assert scale_we_count > 0, "No writes during scaling!"

@cocotb.test()
async def test_05_ram_port_routing(dut):
    """TEST 5: Are RAM ports routed correctly in each state?"""
    dut._log.info("="*60)
    dut._log.info("TEST 5: RAM Port Routing")
    dut._log.info("="*60)
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    
    # Check IDLE state routing
    if hasattr(dut, 'state'):
        state = int(dut.state.value)
        dut._log.info(f"  IDLE state: {state == 0}")
        
        # In IDLE, read_addr should control port routing
        dut.read_addr.value = 42
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        
        if hasattr(dut.u_coeff_ram, 'addr_a'):
            addr_a = int(dut.u_coeff_ram.addr_a.value)
            dut._log.info(f"  read_addr=42 → RAM addr_a={addr_a}")
            if addr_a == 42:
                dut._log.info("  ✓ Port A used for reading (correct)")
            else:
                dut._log.error(f"  ✗ Port A not following read_addr")

@cocotb.test()
async def test_06_full_data_path(dut):
    """TEST 6: Full data path - load, process, read"""
    dut._log.info("="*60)
    dut._log.info("TEST 6: Full Data Path")
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
    
    # Load simple known pattern
    dut._log.info("  Step 1: Loading [100, 101, 102, ...]")
    for addr in range(10):  # Just first 10
        dut.load_addr.value = addr
        dut.load_data.value = 100 + addr
        dut.load_coeff.value = 1
        await RisingEdge(dut.clk)
    
    dut.load_coeff.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    
    # Read back immediately (before INTT)
    dut._log.info("  Step 2: Reading back before INTT")
    pre_intt = []
    for addr in range(10):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        pre_intt.append(int(dut.read_data.value))
    
    dut._log.info(f"  Before INTT: {pre_intt[:5]}")
    
    # Run INTT
    dut._log.info("  Step 3: Running INTT")
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    
    # Wait for done
    cycles = 0
    while int(dut.done.value) == 0:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles > 15000:
            break
    
    dut._log.info(f"  INTT took {cycles} cycles")
    
    # Wait extra cycles after done
    for _ in range(10):
        await RisingEdge(dut.clk)
    
    # Read after INTT
    dut._log.info("  Step 4: Reading after INTT")
    post_intt = []
    for addr in range(10):
        dut.read_addr.value = addr
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        post_intt.append(int(dut.read_data.value))
    
    dut._log.info(f"  After INTT: {post_intt[:5]}")
    
    # Check if data changed
    changed = sum(1 for i in range(10) if pre_intt[i] != post_intt[i])
    
    if changed > 0:
        dut._log.info(f"  ✓ Data changed: {changed}/10 values different")
        dut._log.info("  This means INTT is processing data")
    else:
        dut._log.error("  ✗ Data unchanged!")
        dut._log.error("  INTT did not modify RAM at all")
    
    assert changed > 0, "Data not modified by INTT!"
