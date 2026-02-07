"""
Python reference implementation of NTT for testing
N=256, q=3329, omega=17 (primitive 256-th root of unity)
"""

def mod_exp(base, exp, mod):
    """Modular exponentiation"""
    result = 1
    base = base % mod
    while exp > 0:
        if exp % 2 == 1:
            result = (result * base) % mod
        exp = exp >> 1
        base = (base * base) % mod
    return result

def ntt_forward_reference(coeffs, N=256, q=3329, omega=17):
    """
    Reference NTT forward transform using Cooley-Tukey radix-2
    
    Args:
        coeffs: List of N coefficients
        N: NTT size (must be power of 2)
        q: Modulus
        omega: Primitive N-th root of unity mod q
    
    Returns:
        List of N transformed coefficients
    """
    import math
    
    if len(coeffs) != N:
        raise ValueError(f"Input must have {N} coefficients")
    
    # Copy input
    result = [c % q for c in coeffs]
    
    # Number of stages
    num_stages = int(math.log2(N))
    
    # Cooley-Tukey butterfly algorithm
    for stage in range(num_stages):
        half_block = 1 << stage
        block_size = 1 << (stage + 1)
        
        # Twiddle multiplier for this stage
        twiddle_mult = 1 << (num_stages - stage - 1)
        
        for butterfly in range(N // 2):
            # Calculate addresses
            group = butterfly // half_block
            position = butterfly % half_block
            addr0 = group * block_size + position
            addr1 = addr0 + half_block
            
            # Calculate twiddle index
            twiddle_index = position * twiddle_mult
            twiddle = mod_exp(omega, twiddle_index, q)
            
            # Butterfly operation
            a = result[addr0]
            b = result[addr1]
            
            temp = (b * twiddle) % q
            result[addr0] = (a + temp) % q
            result[addr1] = (a - temp) % q
    
    return result

def verify_ntt_properties(input_coeffs, output_coeffs, N=256, q=3329):
    """
    Verify basic NTT properties
    
    Returns:
        dict with verification results
    """
    results = {}
    
    # Property 1: Linearity - NTT(a*x + b*y) = a*NTT(x) + b*NTT(y)
    # This is complex to test, skip for now
    
    # Property 2: Identity - NTT of impulse at 0 should be all 1s (scaled)
    impulse = [0] * N
    impulse[0] = 1
    ntt_impulse = ntt_forward_reference(impulse, N, q)
    # All values should be 1
    all_ones = all(v == 1 for v in ntt_impulse)
    results['impulse_identity'] = all_ones
    
    # Property 3: All zeros → all zeros
    zeros = [0] * N
    ntt_zeros = ntt_forward_reference(zeros, N, q)
    all_zero = all(v == 0 for v in ntt_zeros)
    results['zeros_identity'] = all_zero
    
    # Property 4: Output values should be in range [0, q)
    in_range = all(0 <= v < q for v in output_coeffs)
    results['output_in_range'] = in_range
    
    return results

if __name__ == "__main__":
    # Test the reference implementation
    print("Testing NTT Reference Implementation")
    print("=" * 50)
    
    # Test 1: All zeros
    print("\nTest 1: All zeros")
    zeros = [0] * 256
    result = ntt_forward_reference(zeros)
    print(f"  Input: all zeros")
    print(f"  Output: {result[:10]}... (showing first 10)")
    print(f"  All zero: {all(v == 0 for v in result)}")
    
    # Test 2: Impulse at position 0
    print("\nTest 2: Impulse at position 0")
    impulse = [0] * 256
    impulse[0] = 1
    result = ntt_forward_reference(impulse)
    print(f"  Input: impulse at 0")
    print(f"  Output: {result[:10]}... (showing first 10)")
    print(f"  All ones: {all(v == 1 for v in result)}")
    
    # Test 3: All ones
    print("\nTest 3: All ones")
    ones = [1] * 256
    result = ntt_forward_reference(ones)
    print(f"  Input: all ones")
    print(f"  Output first value: {result[0]}")
    print(f"  Output rest: {result[1:10]}... (showing next 9)")
    print(f"  Expected: first=256, rest=0")
    
    # Test 4: Simple polynomial [1, 2, 3, 0, 0, ...]
    print("\nTest 4: Simple polynomial")
    poly = [1, 2, 3] + [0] * 253
    result = ntt_forward_reference(poly)
    print(f"  Input: [1, 2, 3, 0, 0, ...]")
    print(f"  Output: {result[:10]}... (showing first 10)")
    
    print("\n" + "=" * 50)
    print("Reference implementation tests complete!")
