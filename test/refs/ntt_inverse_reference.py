"""
Python reference implementation of Inverse NWC NTT (INTT)
N=256, q=8380417, psi=1239911 (primitive 2N-th root)

Uses Gentleman-Sande butterfly with ψ^(-1) twiddles
Input: Bit-Reversed Order (from forward NTT)
Output: Normal Order
"""

import numpy as np

try:
    from .ntt_forward_reference import N, Q, PSI, bit_reverse_order
except ImportError:
    from ntt_forward_reference import N, Q, PSI, bit_reverse_order


def mod_inv(a, mod):
    """Modular inverse using extended Euclidean algorithm"""
    def extended_gcd(a, b):
        if a == 0:
            return b, 0, 1
        gcd, x1, y1 = extended_gcd(b % a, a)
        x = y1 - (b // a) * x1
        y = x1
        return gcd, x, y

    gcd, x, _ = extended_gcd(a % mod, mod)
    if gcd != 1:
        raise ValueError(f"{a} has no inverse mod {mod}")
    return (x % mod + mod) % mod


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

def ntt_inverse_reference(coeffs, N=N, q=Q, psi=PSI):
    """
    Fast Inverse NTT using Gentleman-Sande with ψ^(-1) twiddles
    
    Input: Bit-Reversed Order (BO) - output from forward NTT
    Output: Normal Order (NO)
    
    This matches the working reference implementation.
    """
    n = len(coeffs)
    if n != N:
        raise ValueError(f"Input must have {N} coefficients, got {n}")
    
    result = np.array(coeffs, dtype=object)
    
    psi_inv = mod_inv(psi, q)
    brv = bit_reverse_order(N)
    
    t = N // 2     # Number of blocks (starts high, decreases)
    m = 1          # Stride (starts low, increases)
    
    while m < N:
        for k in range(t):
            # Twiddle factor W = ψ^(-p) using bit-reversed index
            p = brv[t + k]
            W = pow(int(psi_inv), int(p), q)
            
            for j in range(m):
                idx1 = 2 * m * k + j
                idx2 = idx1 + m
                
                u = result[idx1]
                v = result[idx2]
                
                # Gentleman-Sande butterfly: (A+B, (A-B)×W)
                result[idx1] = (u + v) % q
                diff = (u - v) % q
                result[idx2] = (diff * W) % q
        
        t //= 2
        m *= 2
    
    # Final scaling by N^(-1)
    n_inv = mod_inv(N, q)
    result = (result * n_inv) % q
    
    return result.astype(np.int64).tolist()

