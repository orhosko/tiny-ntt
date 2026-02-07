"""
Cocotb testbench for twiddle factor ROM
Tests precomputed NTT twiddle factors
"""

import cocotb
from cocotb.triggers import Timer

# Test parameters
N = 256
Q = 3329
OMEGA = 17

def compute_twiddle(k, omega=OMEGA, q=Q):
    """Compute ω^k mod q"""
    return pow(omega, k, q)

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
async def test_identity_twiddle(dut):
    """Test that twiddle[0] = 1 (ω^0 = 1)"""
    dut._log.info("Testing identity twiddle (ω^0)")
    
    dut.addr.value = 0
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    assert result == 1, f"Twiddle[0] should be 1, got {result}"
    
    dut._log.info("✓ Identity twiddle correct")

@cocotb.test()
async def test_omega_value(dut):
    """Test that twiddle[1] = ω"""
    dut._log.info("Testing ω value (twiddle[1])")
    
    dut.addr.value = 1
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    assert result == OMEGA, f"Twiddle[1] should be {OMEGA}, got {result}"
    
    dut._log.info(f"✓ ω = {result}")

@cocotb.test()
async def test_all_twiddles(dut):
    """Test all 256 twiddle factors"""
    dut._log.info("Testing all 256 twiddle factors")
    
    errors = []
    for k in range(N):
        dut.addr.value = k
        await Timer(1, unit='ns')
        
        result = int(dut.twiddle.value)
        expected = compute_twiddle(k)
        
        if result != expected:
            errors.append(f"Twiddle[{k}]: got {result}, expected {expected}")
        
        if (k + 1) % 64 == 0:
            dut._log.info(f"  Verified {k+1}/256 twiddles")
    
    assert len(errors) == 0, f"Twiddle mismatches:\n" + "\n".join(errors[:10])
    dut._log.info(f"✓ All {N} twiddle factors correct")

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
        dut._log.info(f"  ω^{k} = {result}")
    
    dut._log.info("✓ Power-of-2 twiddles correct")

@cocotb.test()
async def test_half_point(dut):
    """Test twiddle at N/2 = 128"""
    dut._log.info("Testing twiddle at half-point (128)")
    
    dut.addr.value = 128
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    expected = compute_twiddle(128)
    
    dut._log.info(f"  ω^128 = {result}")
    assert result == expected, \
        f"Twiddle[128] mismatch: got {result}, expected {expected}"
    
    dut._log.info("✓ Half-point twiddle correct")

@cocotb.test()
async def test_last_twiddle(dut):
    """Test last twiddle factor (255)"""
    dut._log.info("Testing last twiddle (255)")
    
    dut.addr.value = 255
    await Timer(1, unit='ns')
    
    result = int(dut.twiddle.value)
    expected = compute_twiddle(255)
    
    dut._log.info(f"  ω^255 = {result}")
    assert result == expected, \
        f"Twiddle[255] mismatch: got {result}, expected {expected}"
    
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
    test_indices = random.sample(range(N), 50)
    
    for k in test_indices:
        dut.addr.value = k
        await Timer(1, unit='ns')
        
        result = int(dut.twiddle.value)
        expected = compute_twiddle(k)
        
        assert result == expected, \
            f"Random access [{k}]: got {result}, expected {expected}"
    
    dut._log.info(f"✓ Random access test passed for 50 addresses")

@cocotb.test()
async def test_modular_properties(dut):
    """Verify that twiddles satisfy modular arithmetic properties"""
    dut._log.info("Testing modular properties")
    
    # Test that ω^256 ≡ 1 (mod 3329) by checking wraparound
    # Read ω^0 and ω^256 (should wrap if we had more addresses, but ROM has 256 entries)
    
    # Test ω^a * ω^b ≡ ω^(a+b) mod 256 for small values
    test_pairs = [(1, 2), (5, 10), (7, 13)]
    
    for a, b in test_pairs:
        # Read ω^a
        dut.addr.value = a
        await Timer(1, unit='ns')
        omega_a = int(dut.twiddle.value)
        
        # Read ω^b
        dut.addr.value = b
        await Timer(1, unit='ns')
        omega_b = int(dut.twiddle.value)
        
        # Read ω^(a+b)
        dut.addr.value = (a + b) % N
        await Timer(1, unit='ns')
        omega_ab = int(dut.twiddle.value)
        
        # Check ω^a * ω^b ≡ ω^(a+b) (mod Q)
        product = (omega_a * omega_b) % Q
        assert product == omega_ab, \
            f"Property failed: ω^{a} * ω^{b} = {product}, but ω^{a+b} = {omega_ab}"
    
    dut._log.info("✓ Modular properties verified")
