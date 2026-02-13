"""
Python reference implementation of NTT for testing
N=256, q=8380417, psi=1239911 (primitive 512-th root of unity)

Based on hardware twiddle addressing (DIT with ψ twiddles)
"""

import numpy as np

# NTT Parameters
N = 256
Q = 8380417
PSI = 1239911      # Primitive 2N-th root (ψ^512 ≡ 1, ψ^256 ≡ -1)
OMEGA = 169688     # ω = ψ² (primitive N-th root)

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

def bit_reverse_order(n):
    """Generate bit-reversed indices for size n"""
    width = n.bit_length() - 1
    indices = np.arange(n)
    reversed_indices = np.zeros(n, dtype=int)
    for i in range(n):
        binary = bin(i)[2:].zfill(width)
        reversed_indices[i] = int(binary[::-1], 2)
    return reversed_indices

def ntt_forward_reference(coeffs, N=N, q=Q, psi=PSI):
    """
    Fast NTT using Cooley-Tukey (DIT) with ψ-based twiddles.

    Input: Normal Order (NO)
    Output: Hardware-order output (matches control twiddle addressing).
    """
    n = len(coeffs)
    if n != N:
        raise ValueError(f"Input must have {N} coefficients, got {n}")

    result = np.array(coeffs, dtype=object)

    m = 2
    while m <= N:
        step = N // m
        half = m // 2
        for base in range(0, N, m):
            for j in range(half):
                w = pow(int(psi), int(j * step), q)
                idx1 = base + j
                idx2 = idx1 + half

                u = result[idx1]
                v = (result[idx2] * w) % q

                result[idx1] = (u + v) % q
                result[idx2] = (u - v) % q
        m *= 2

    return result.astype(np.int64).tolist()

