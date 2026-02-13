"""
Cocotb testbench for twiddle factor ROM
Tests precomputed NTT twiddle factors
"""

import cocotb
from cocotb.triggers import Timer

# Test parameters
N = 256
Q = 8380417
PSI = 1239911


def compute_twiddle(addr, psi=PSI, q=Q):
    """Compute ψ^addr mod q."""
    return pow(psi, addr, q)


TWIDDLE_COUNT = N


@cocotb.test()
async def test_basic_twiddles(dut):
    """Test basic twiddle factor reads"""
    dut._log.info("Testing basic twiddle factor reads")
    
    # Test first 10 twiddle factors
    for k in range(10):
        dut.addr.value = k
        await Timer(1, unit='ns')
        
        result = int(dut.twiddle.value)
        expected = compute_twiddle(k)
        
        assert result == expected, \
            f"Twiddle[{k}] mismatch: got {result}, expected {expected}"
    
    dut._log.info(f"✓ First 10 twiddle factors correct")

@cocotb.test()
async def test_first_twiddle(dut):
    """Test that twiddle[0] matches ROM layout"""
    dut._log.info("Testing twiddle[0] matches ROM layout")
    
    dut.addr.value = 0
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    expected = compute_twiddle(0)
    assert result == expected, f"Twiddle[0] should be {expected}, got {result}"
    
    dut._log.info("✓ Twiddle[0] correct")

@cocotb.test()
async def test_second_twiddle(dut):
    """Test that twiddle[1] matches ROM layout"""
    dut._log.info("Testing twiddle[1] matches ROM layout")
    
    dut.addr.value = 1
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    expected = compute_twiddle(1)
    assert result == expected, f"Twiddle[1] should be {expected}, got {result}"
    
    dut._log.info("✓ Twiddle[1] correct")

@cocotb.test()
async def test_all_twiddles(dut):
    """Test all twiddle factors in ROM"""
    dut._log.info("Testing all twiddle factors")
    
    errors = []
    for k in range(TWIDDLE_COUNT):
        dut.addr.value = k
        await Timer(1, unit='ns')
        
        result = int(dut.twiddle.value)
        expected = compute_twiddle(k)
        
        if result != expected:
            errors.append(f"Twiddle[{k}]: got {result}, expected {expected}")
        
        if (k + 1) % 64 == 0:
            dut._log.info(f"  Verified {k+1}/{TWIDDLE_COUNT} twiddles")
    
    assert len(errors) == 0, f"Twiddle mismatches:\n" + "\n".join(errors[:10])
    dut._log.info(f"✓ All {TWIDDLE_COUNT} twiddle factors correct")

@cocotb.test()
async def test_powers_of_two(dut):
    """Test twiddles at powers of 2 indices"""
    dut._log.info("Testing twiddles at power-of-2 indices")
    
    powers = [1, 2, 4, 8, 16, 32, 64, 128]
    
    for k in powers:
        dut.addr.value = k
        await Timer(1, unit='ns')
        
        result = int(dut.twiddle.value)
        expected = compute_twiddle(k)
        
        assert result == expected, \
            f"Twiddle[{k}] mismatch: got {result}, expected {expected}"
        dut._log.info(f"  Twiddle[{k}] = {result}")
    
    dut._log.info("✓ Power-of-2 twiddles correct")

@cocotb.test()
async def test_half_point(dut):
    """Test twiddle near the midpoint of the ROM"""
    dut._log.info("Testing twiddle near midpoint")
    
    midpoint = TWIDDLE_COUNT // 2
    dut.addr.value = midpoint
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    expected = compute_twiddle(midpoint)
    
    dut._log.info(f"  Twiddle[{midpoint}] = {result}")
    assert result == expected, \
        f"Twiddle[{midpoint}] mismatch: got {result}, expected {expected}"
    
    dut._log.info("✓ Midpoint twiddle correct")

@cocotb.test()
async def test_last_twiddle(dut):
    """Test last twiddle factor in ROM"""
    last_index = TWIDDLE_COUNT - 1
    dut._log.info(f"Testing last twiddle ({last_index})")
    
    dut.addr.value = last_index
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    expected = compute_twiddle(last_index)
    
    dut._log.info(f"  Twiddle[{last_index}] = {result}")
    assert result == expected, \
        f"Twiddle[{last_index}] mismatch: got {result}, expected {expected}"
    
    dut._log.info("✓ Last twiddle correct")

@cocotb.test()
async def test_sequential_read(dut):
    """Test sequential reads to ensure no timing issues"""
    dut._log.info("Testing sequential reads")
    
    for k in range(20):
        dut.addr.value = k
        await Timer(1, unit='ns')
        
        result = int(dut.twiddle.value)
        expected = compute_twiddle(k)
        
        assert result == expected, \
            f"Sequential read {k}: got {result}, expected {expected}"
    
    dut._log.info("✓ Sequential reads correct")

@cocotb.test()
async def test_random_access(dut):
    """Test random address access pattern"""
    dut._log.info("Testing random address access")
    
    import random
    random.seed(42)
    test_indices = random.sample(range(TWIDDLE_COUNT), min(50, TWIDDLE_COUNT))
    
    for k in test_indices:
        dut.addr.value = k
        await Timer(1, unit='ns')
        
        result = int(dut.twiddle.value)
        expected = compute_twiddle(k)
        
        assert result == expected, \
            f"Random access [{k}]: got {result}, expected {expected}"
    
    dut._log.info(f"✓ Random access test passed for {len(test_indices)} addresses")

@cocotb.test()
async def test_modular_properties(dut):
    """Verify that twiddles satisfy modular arithmetic properties"""
    dut._log.info("Testing modular properties")
    
    # Test ψ^a * ψ^b ≡ ψ^(a+b)
    test_indices = [(0, 1), (2, 3), (5, 10)]

    for idx_a, idx_b in test_indices:
        dut.addr.value = idx_a
        await Timer(1, unit='ns')
        psi_a = int(dut.twiddle.value)

        dut.addr.value = idx_b
        await Timer(1, unit='ns')
        psi_b = int(dut.twiddle.value)

        expected = pow(PSI, (idx_a + idx_b) % (2 * N), Q)

        product = (psi_a * psi_b) % Q
        assert product == expected, \
            f"Property failed: ψ^{idx_a} * ψ^{idx_b} = {product}, expected {expected}"
    
    dut._log.info("✓ Modular properties verified")
