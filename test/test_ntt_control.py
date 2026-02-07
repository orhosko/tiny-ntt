"""
Cocotb testbench for NTT Control FSM
Tests state machine, address generation, and twiddle addressing
"""

import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock

# NTT parameters
N = 256
LOGN = 8

def cooley_tukey_addresses(stage, butterfly):
    """
    Python reference for Cooley-Tukey address generation
    Returns (addr0, addr1) for given stage and butterfly index
    """
    half_block = 1 << stage
    block_size = 1 << (stage + 1)
    
    group = butterfly // half_block
    position = butterfly % half_block
    
    addr0 = group * block_size + position
    addr1 = addr0 + half_block
    
    return (addr0, addr1)

def twiddle_address(stage, butterfly):
    """
    Python reference for twiddle factor addressing
    """
    half_block = 1 << stage
    multiplier = 1 << (LOGN - stage - 1)
    index = butterfly % half_block
    return (index * multiplier) % N

@cocotb.test()
async def test_idle_to_done(dut):
    """Test basic state transitions: IDLE → COMPUTE → DONE"""
    dut._log.info("Testing FSM state transitions")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    # Check IDLE state
    assert int(dut.done.value) == 0, "Should not be done in IDLE"
    assert int(dut.busy.value) == 0, "Should not be busy in IDLE"
    dut._log.info("✓ IDLE state correct")
    
    # Start computation
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    # Check COMPUTE state
    assert int(dut.busy.value) == 1, "Should be busy in COMPUTE"
    assert int(dut.done.value) == 0, "Should not be done yet"
    dut._log.info("✓ COMPUTE state entered")
    
    # Run a few cycles
    for _ in range(20):
        await RisingEdge(dut.clk)
    
    # Still computing
    assert int(dut.busy.value) == 1, "Should still be busy"
    dut._log.info("✓ State transitions work")

@cocotb.test()
async def test_address_generation_stage0(dut):
    """Test address generation for stage 0"""
    dut._log.info("Testing address generation for stage 0")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset and start
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    # Test first few butterflies of stage 0
    test_cases = [0, 1, 2, 5, 10, 50, 100, 127]
    
    for expected_butterfly in test_cases:
        # Wait for the right butterfly
        while True:
            await Timer(1, unit="ns")
            stage_val = int(dut.stage.value)
            butterfly_val = int(dut.butterfly.value)
            
            if stage_val == 0 and butterfly_val == expected_butterfly:
                break
            
            await RisingEdge(dut.clk)
        
        # Read addresses
        addr_a = int(dut.ram_addr_a.value)
        addr_b = int(dut.ram_addr_b.value)
        
        # Calculate expected
        expected_a, expected_b = cooley_tukey_addresses(0, expected_butterfly)
        
        dut._log.info(f"  Butterfly {expected_butterfly}: addr_a={addr_a}, addr_b={addr_b} "
                     f"(expected {expected_a}, {expected_b})")
        
        assert addr_a == expected_a, f"Stage 0, butterfly {expected_butterfly}: addr_a mismatch"
        assert addr_b == expected_b, f"Stage 0, butterfly {expected_butterfly}: addr_b mismatch"
    
    dut._log.info(f"✓ Stage 0 addresses correct for {len(test_cases)} butterflies")

@cocotb.test()
async def test_address_generation_multiple_stages(dut):
    """Test address generation across multiple stages"""
    dut._log.info("Testing address generation across stages")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset and start
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    
    # Test select butterflies from different stages
    test_points = [
        (0, 0), (0, 64), (0, 127),  # Stage 0
        (1, 0), (1, 32), (1, 127),  # Stage 1
        (2, 0), (2, 100),           # Stage 2
        (3, 0), (3, 50),            # Stage 3
    ]
    
    for expected_stage, expected_butterfly in test_points:
        # Wait for the right stage/butterfly
        while True:
            await Timer(1, unit="ns")
            stage_val = int(dut.stage.value)
            butterfly_val = int(dut.butterfly.value)
            
            if stage_val == expected_stage and butterfly_val == expected_butterfly:
                break
            
            await RisingEdge(dut.clk)
            
            # Safety: don't wait forever
            if stage_val > expected_stage:
                dut._log.error(f"Missed stage {expected_stage}, butterfly {expected_butterfly}")
                break
        
        if stage_val != expected_stage:
            continue
        
        # Read addresses
        addr_a = int(dut.ram_addr_a.value)
        addr_b = int(dut.ram_addr_b.value)
        
        # Calculate expected
        expected_a, expected_b = cooley_tukey_addresses(expected_stage, expected_butterfly)
        
        dut._log.info(f"  Stage {expected_stage}, butterfly {expected_butterfly}: "
                     f"addr_a={addr_a}, addr_b={addr_b}")
        
        assert addr_a == expected_a, \
            f"Stage {expected_stage}, butterfly {expected_butterfly}: addr_a={addr_a}, expected={expected_a}"
        assert addr_b == expected_b, \
            f"Stage {expected_stage}, butterfly {expected_butterfly}: addr_b={addr_b}, expected={expected_b}"
    
    dut._log.info(f"✓ Multi-stage addresses correct for {len(test_points)} test points")

@cocotb.test()
async def test_twiddle_addressing(dut):
    """Test twiddle factor address calculation"""
    dut._log.info("Testing twiddle factor addressing")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset and start
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    
    # Test twiddle addresses for select stage/butterfly pairs
    test_points = [
        (0, 0), (0, 1), (0, 10),
        (1, 0), (1, 1), (1, 50),
        (2, 0), (2, 10),
        (3, 0), (3, 20),
    ]
    
    for expected_stage, expected_butterfly in test_points:
        # Wait for the right stage/butterfly
        while True:
            await Timer(1, unit="ns")
            stage_val = int(dut.stage.value)
            butterfly_val = int(dut.butterfly.value)
            
            if stage_val == expected_stage and butterfly_val == expected_butterfly:
                break
            
            await RisingEdge(dut.clk)
            
            if stage_val > expected_stage:
                break
        
        if stage_val != expected_stage:
            continue
        
        # Read twiddle address
        tw_addr = int(dut.twiddle_addr.value)
        
        # Calculate expected
        expected_tw = twiddle_address(expected_stage, expected_butterfly)
        
        dut._log.info(f"  Stage {expected_stage}, butterfly {expected_butterfly}: "
                     f"twiddle_addr={tw_addr} (expected {expected_tw})")
        
        assert tw_addr == expected_tw, \
            f"Stage {expected_stage}, butterfly {expected_butterfly}: twiddle mismatch"
    
    dut._log.info(f"✓ Twiddle addresses correct for {len(test_points)} test points")

@cocotb.test()
async def test_timing_cycles(dut):
    """Test multi-cycle timing for butterfly operation"""
    dut._log.info("Testing timing cycles")
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Reset and start
    dut.rst_n.value = 0
    dut.start.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    dut.start.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    
    # Monitor cycles for first butterfly
    cycle_signals = []
    for i in range(4):
        cycle_val = int(dut.cycle.value)
        ram_re = int(dut.ram_re.value)
        butterfly_valid = int(dut.butterfly_valid.value)
        ram_we_a = int(dut.ram_we_a.value)
        
        cycle_signals.append({
            'cycle': cycle_val,
            're': ram_re,
            'valid': butterfly_valid,
            'we': ram_we_a
        })
        
        dut._log.info(f"  Cycle {i}: cycle={cycle_val}, re={ram_re}, "
                     f"valid={butterfly_valid}, we={ram_we_a}")
        
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
    
    # Check expected timing
    assert cycle_signals[0]['re'] == 1, "Cycle 0: should read"
    assert cycle_signals[2]['valid'] == 1, "Cycle 2: butterfly should be valid"
    assert cycle_signals[3]['we'] == 1, "Cycle 3: should write"
    
    dut._log.info("✓ Timing cycles correct")
