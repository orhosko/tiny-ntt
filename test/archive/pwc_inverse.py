#!/usr/bin/env python3
"""
Corrected INTT implementation - testing different approaches
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

def ntt_inverse_corrected_v1(coeffs, N=256, q=3329, omega=17):
    """
    INTT with bit-reversal permutation at input
    (Standard Cooley-Tukey requires either input or output bit-reversed)
    """
    import math
    result = [c % q for c in coeffs]
    omega_inv = mod_inv(omega, q)
    num_stages = int(math.log2(N))
    
    # Bit-reverse input
    temp = result[:]
    for i in range(N):
        j = bit_reverse(i, num_stages)
        result[i] = temp[j]
    
    # Same algorithm as forward
    for stage in range(num_stages):
        half_block = 1 << stage
        block_size = 1 << (stage + 1)
        twiddle_mult = 1 << (num_stages - stage - 1)
        
        for butterfly in range(N // 2):
            group = butterfly // half_block
            position = butterfly % half_block
            addr0 = group * block_size + position
            addr1 = addr0 + half_block
            
            twiddle_index = position * twiddle_mult
            twiddle = mod_exp(omega_inv, twiddle_index, q)
            
            a = result[addr0]
            b = result[addr1]
            temp = (b * twiddle) % q
            result[addr0] = (a + temp) % q
            result[addr1] = (a - temp) % q
    
    # Final scaling
    N_inv = mod_inv(N, q)
    result = [(r * N_inv) % q for r in result]
    return result

def ntt_inverse_corrected_v2(coeffs, N=256, q=3329, omega=17):
    """
    INTT with bit-reversal permutation at output
    """
    import math
    result = [c % q for c in coeffs]
    omega_inv = mod_inv(omega, q)
    num_stages = int(math.log2(N))
    
    # Same algorithm as forward
    for stage in range(num_stages):
        half_block = 1 << stage
        block_size = 1 << (stage + 1)
        twiddle_mult = 1 << (num_stages - stage - 1)
        
        for butterfly in range(N // 2):
            group = butterfly // half_block
            position = butterfly % half_block
            addr0 = group * block_size + position
            addr1 = addr0 + half_block
            
            twiddle_index = position * twiddle_mult
            twiddle = mod_exp(omega_inv, twiddle_index, q)
            
            a = result[addr0]
            b = result[addr1]
            temp = (b * twiddle) % q
            result[addr0] = (a + temp) % q
            result[addr1] = (a - temp) % q
    
    # Bit-reverse output
    temp = result[:]
    for i in range(N):
        j = bit_reverse(i, num_stages)
        result[i] = temp[j]
    
    # Final scaling
    N_inv = mod_inv(N, q)
    result = [(r * N_inv) % q for r in result]
    return result

# Test
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from refs.ntt_forward_reference import ntt_forward_reference

N, Q, OMEGA = 256, 3329, 17

print("Testing Corrected INTT Implementations")
print("="*60)

# Test data
test_poly = [1, 2, 3] + [0] * (N - 3)
ntt_poly = ntt_forward_reference(test_poly, N, Q, OMEGA)

print(f"\nOriginal: {test_poly[:10]}")
print(f"After Forward NTT: {ntt_poly[:10]}")

print("\nVersion 1: Bit-reverse INPUT")
result_v1 = ntt_inverse_corrected_v1(ntt_poly, N, Q, OMEGA)
print(f"After INTT: {result_v1[:10]}")
match_v1 = result_v1 == test_poly
print(f"Match: {match_v1}")

print("\nVersion 2: Bit-reverse OUTPUT")
result_v2 = ntt_inverse_corrected_v2(ntt_poly, N, Q, OMEGA)
print(f"After INTT: {result_v2[:10]}")
match_v2 = result_v2 == test_poly
print(f"Match: {match_v2}")

# Also test impulse
impulse = [1] + [0] * (N - 1)
ntt_impulse = [1] * N
print("\n" + "="*60)
print("Impulse test:")
print(f"INTT([1,1,1...]) V1: {ntt_inverse_corrected_v1(ntt_impulse, N, Q, OMEGA)[:10]}")
print(f"INTT([1,1,1...]) V2: {ntt_inverse_corrected_v2(ntt_impulse, N, Q, OMEGA)[:10]}")
print(f"Expected: [1, 0, 0, ...]")
