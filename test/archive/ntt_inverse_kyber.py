"""
CORRECTED Inverse NTT implementation based on official Kyber reference
https://github.com/pq-crystals/kyber/blob/master/ref/ntt.c
"""

def mod_exp(base, exp, mod):
    result = 1
    base = base % mod
    while exp > 0:
        if exp % 2 == 1:
            result = (result * base) % mod
        exp = exp >> 1
        base = (base * base) % mod
    return result

def mod_inv(a, m):
    def egcd(a, b):
        if a == 0:
            return b, 0, 1
        gcd, x1, y1 = egcd(b % a, a)
        x = y1 - (b // a) * x1
        y = x1
        return gcd, x, y
    gcd, x, _ = egcd(a % m, m)
    return (x % m + m) % m

def bit_reverse(x, log_n):
    """Reverse the bits of x using log_n bits"""
    result = 0
    for i in range(log_n):
        if x & (1 << i):
            result |= 1 << (log_n - 1 - i)
    return result

def ntt_inverse_kyber_style(coeffs, N=256, q=3329, omega=17):
    """
    Corrected INTT based on Kyber reference implementation
    
    Adapted for our forward NTT which outputs normal order (not bit-reversed).
    This version bit-reverses the input first to match Kyber's expectations.
    """
    import math
    
    if len(coeffs) != N:
        raise ValueError(f"Input must have {N} coefficients")
    
    num_stages = int(math.log2(N))
    
    # Our forward NTT outputs normal order, but Kyber INTT expects bit-reversed
    # So we bit-reverse the input first
    result = [0] * N
    for i in range(N):
        j = bit_reverse(i, num_stages)
        result[i] = coeffs[j] % q
    
    # Pre-compute forward twiddles (same as forward NTT)
    twiddles = []
    for stage in range(num_stages):
        half_block = 1 << stage
        twiddle_mult = 1 << (num_stages - stage - 1)
        for position in range(half_block):
            twiddle_index = position * twiddle_mult
            twiddle = mod_exp(omega, twiddle_index, q)
            twiddles.append(twiddle)
    
    # INTT with REVERSED stage order
    k = len(twiddles) - 1  # Start from end of twiddles array
    
    # len goes from 2 -> 4 -> 8 -> ... -> 128 (REVERSED from forward!)
    len_val = 2
    while len_val <= N // 2:
        start = 0
        while start < N:
            zeta = twiddles[k]
            k -= 1
            
            j = start
            while j < start + len_val:
                # Kyber butterfly for inverse:
                t = result[j]
                result[j] = (t + result[j + len_val]) % q          # a' = a + b
                result[j + len_val] = (result[j + len_val] - t) % q  # b' = b - a
                result[j + len_val] = (result[j + len_val] * zeta) % q  # b' *= zeta
                j += 1
            
            start = start + 2 * len_val
        
        len_val <<= 1
    
    # Final scaling by N^(-1)
    N_inv = mod_inv(N, q)
    result = [(r * N_inv) % q for r in result]
    
    return result

# Test it!
if __name__ == "__main__":
    import os
    import sys

    sys.path.insert(0, os.path.dirname(__file__))
    from refs.ntt_forward_reference import ntt_forward_reference

    N, Q, OMEGA = 256, 3329, 17
    
    print("Testing CORRECTED INTT (Kyber-style)")
    print("="*60)
    
    # Test 1: Impulse
    print("\nTest 1: Impulse")
    impulse = [1] + [0] * (N - 1)
    ntt_impulse = ntt_forward_reference(impulse, N, Q, OMEGA)
    intt_result = ntt_inverse_kyber_style(ntt_impulse, N, Q, OMEGA)
    print(f"  Input: [1, 0, 0, ...]")
    print(f"  After NTT: {ntt_impulse[:10]}")
    print(f"  After INTT: {intt_result[:10]}")
    print(f"  Match: {intt_result == impulse}")
    
    # Test 2: Simple polynomial
    print("\nTest 2: Simple polynomial [1,2,3,0,...]")
    poly = [1, 2, 3] + [0] * (N - 3)
    ntt_poly = ntt_forward_reference(poly, N, Q, OMEGA)
    intt_poly = ntt_inverse_kyber_style(ntt_poly, N, Q, OMEGA)
    print(f"  Input: {poly[:10]}")
    print(f"  After NTT: {ntt_poly[:10]}")
    print(f"  After INTT: {intt_poly[:10]}")
    print(f"  Match: {intt_poly == poly}")
    
    # Test 3: All ones
    print("\nTest 3: All ones")
    ones = [1] * N
    ntt_ones = ntt_forward_reference(ones, N, Q, OMEGA)
    intt_ones = ntt_inverse_kyber_style(ntt_ones, N, Q, OMEGA)
    print(f"  Input: [1, 1, 1, ...]")
    print(f"  After NTT: {ntt_ones[:10]}")
    print(f"  After INTT: {intt_ones[:10]}")
    print(f"  Match: {intt_ones == ones}")
    
    # Test 4: Polynomial multiplication
    print("\nTest 4: Polynomial multiplication")
    p1 = [1, 5, 1] + [0] * (N - 3)  # x^2 + 5x + 1
    p2 = [5, 1] + [0] * (N - 2)      # 5 + x
    expected = [5, 10, 6, 1] + [0] * (N - 4)
    
    ntt_p1 = ntt_forward_reference(p1, N, Q, OMEGA)
    ntt_p2 = ntt_forward_reference(p2, N, Q, OMEGA)
    ntt_product = [(ntt_p1[i] * ntt_p2[i]) % Q for i in range(N)]
    result = ntt_inverse_kyber_style(ntt_product, N, Q, OMEGA)
    
    print(f"  p1: {p1[:5]}")
    print(f"  p2: {p2[:5]}")
    print(f"  Expected product: {expected[:10]}")
    print(f"  Actual product: {result[:10]}")
    print(f"  Match: {result[:4] == expected[:4]}")
    
    print("\n" + "="*60)
    if all([intt_result == impulse, intt_poly == poly, intt_ones == ones, result[:4] == expected[:4]]):
        print("✓✓✓ ALL TESTS PASSED! ✓✓✓")
    else:
        print("✗ SOME TESTS FAILED")
