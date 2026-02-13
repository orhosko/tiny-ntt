#!/usr/bin/env python3
"""
Compare our NWC NTT against a naive reference
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from refs.ntt_forward_reference import bit_reverse_order, ntt_forward_reference

N = 256
Q = 8380417
PSI = 1239911      # Primitive 2N-th root (ψ^512 ≡ 1, ψ^256 ≡ -1)
OMEGA = 169688     # ω = ψ² (primitive N-th root)

def mod_exp(base, exp, mod):
    result = 1
    base = base % mod
    while exp > 0:
        if exp % 2 == 1:
            result = (result * base) % mod
        exp = exp >> 1
        base = (base * base) % mod
    return result

def naive_dft(coeffs, N=256, q=3329, omega=17):
    """Naive DFT - mathematically correct but slow"""
    result = [0] * N
    for k in range(N):
        for j in range(N):
            result[k] = (result[k] + coeffs[j] * mod_exp(omega, (j * k) % N, q)) % q
    return result


def naive_nwc_ntt(coeffs, N=256, q=3329, psi=1):
    """Naive NWC NTT using psi twiddles (natural order output)."""
    result = [0] * N
    for k in range(N):
        exponent_scale = 2 * k + 1
        for j in range(N):
            result[k] = (result[k] + coeffs[j] * mod_exp(psi, exponent_scale * j, q)) % q
    return result

print("Comparing our NWC NTT against naive NWC reference")
print("="*60)

# Test 1: Impulse at position 1
test_input = [0, 1] + [0] * (N - 2)
print(f"\nInput: [0, 1, 0, 0, ...]")

our_ntt_bo = ntt_forward_reference(test_input, N, Q, PSI)
bit_reversed = bit_reverse_order(N)
our_ntt = [our_ntt_bo[bit_reversed[i]] for i in range(N)]
correct_dft = naive_nwc_ntt(test_input, N, Q, PSI)

print(f"\nFirst 10 values:")
print(f"Our NTT (NO):     {our_ntt[:10]}")
print(f"Correct NWC NTT:  {correct_dft[:10]}")

matches = our_ntt == correct_dft
print(f"\n✓ MATCH: {matches}")

if not matches:
    print(f"\nERROR FOUND! Our forward NTT is WRONG!")
    errors = sum(1 for i in range(N) if our_ntt[i] != correct_dft[i])
    print(f"Total mismatches: {errors}/{N}")
    print(f"\nFirst 5 mismatches:")
    count = 0
    for i in range(N):
        if our_ntt[i] != correct_dft[i]:
            print(f"  [{i}]: Our={our_ntt[i]}, Correct={correct_dft[i]}")
            count += 1
            if count >= 5:
                break
