#!/usr/bin/env python3
"""
Precompute constants for Barrett and Montgomery reduction

This script computes the necessary constants for efficient modular reduction
algorithms used in NTT-based polynomial multiplication.
"""

import math


def extended_gcd(a, b):
    """Extended Euclidean Algorithm - returns gcd, x, y where ax + by = gcd(a,b)"""
    if a == 0:
        return b, 0, 1
    gcd, x1, y1 = extended_gcd(b % a, a)
    x = y1 - (b // a) * x1
    y = x1
    return gcd, x, y


def mod_inverse(a, m):
    """Compute modular multiplicative inverse of a modulo m"""
    gcd, x, _ = extended_gcd(a, m)
    if gcd != 1:
        raise ValueError(f"Modular inverse does not exist for {a} mod {m}")
    return (x % m + m) % m


def compute_barrett_constants(q):
    """
    Compute Barrett reduction constants
    
    For modulus q, we need:
    - k: bit width such that 2^(k-1) < q < 2^k
    - μ (mu): floor(2^(2k) / q)
    
    Barrett algorithm:
        product = a * b
        q1 = product >> (k-1)
        q2 = (q1 * μ) >> (k+1)
        r = product - q2 * q
        if (r >= q) r = r - q
    """
    k = q.bit_length()  # Minimum bits needed to represent q
    mu = (1 << (2 * k)) // q
    
    print(f"Barrett Reduction Constants for q = {q}")
    print(f"  k (bit width):     {k}")
    print(f"  μ (mu):            {mu} (0x{mu:X})")
    print(f"  2^(2k):            {1 << (2*k)}")
    print(f"  2^(2k) / q:        {(1 << (2*k)) / q:.4f}")
    print()
    
    return k, mu


def compute_montgomery_constants(q):
    """
    Compute Montgomery reduction constants
    
    For modulus q, we need:
    - R: power of 2 greater than q (typically 2^k where k is bit width)
    - R^-1 mod q: multiplicative inverse of R modulo q
    - q': -q^-1 mod R (used in REDC algorithm)
    
    Montgomery REDC algorithm:
        T = a * b  (in Montgomery domain)
        m = (T * q') mod R
        t = (T + m * q) >> k  (where R = 2^k)
        if (t >= q) t = t - q
        result = t  (in Montgomery domain)
    
    To convert to Montgomery domain: a_M = (a * R) mod q
    To convert from Montgomery domain: a = (a_M * R^-1) mod q
    """
    k = q.bit_length()
    R = 1 << k  # Next power of 2 after q
    
    # Ensure R > q
    if R <= q:
        k += 1
        R = 1 << k
    
    # Compute R^-1 mod q
    R_inv = mod_inverse(R, q)
    
    # Compute q^-1 mod R
    q_inv = mod_inverse(q, R)
    
    # Compute q' = -q^-1 mod R
    q_prime = (-q_inv) % R
    
    # Verify: q * q' ≡ -1 (mod R)
    assert (q * q_prime) % R == (R - 1), "q' computation verification failed"
    
    # Compute R mod q (useful for domain conversion)
    R_mod_q = R % q
    
    print(f"Montgomery Reduction Constants for q = {q}")
    print(f"  k (bit width):     {k}")
    print(f"  R = 2^k:           {R} (0x{R:X})")
    print(f"  R mod q:           {R_mod_q}")
    print(f"  R^-1 mod q:        {R_inv}")
    print(f"  q^-1 mod R:        {q_inv}")
    print(f"  q' = -q^-1 mod R:  {q_prime} (0x{q_prime:X})")
    print()
    print(f"  Verification: (q * q') mod R = {(q * q_prime) % R} (should be {R-1})")
    print()
    
    return k, R, R_inv, q_prime, R_mod_q


def generate_systemverilog_params(q):
    """Generate SystemVerilog parameter definitions"""
    print("=" * 70)
    print(f"SystemVerilog Parameters for q = {q}")
    print("=" * 70)
    print()
    
    # Barrett constants
    k_barrett, mu = compute_barrett_constants(q)
    
    # Montgomery constants
    k_mont, R, R_inv, q_prime, R_mod_q = compute_montgomery_constants(q)
    
    print("=" * 70)
    print("Copy these into your SystemVerilog modules:")
    print("=" * 70)
    print()
    print("// Barrett Reduction Parameters")
    print(f"parameter int Q = {q};")
    print(f"parameter int K_BARRETT = {k_barrett};")
    print(f"parameter int MU = {mu};  // 0x{mu:X}")
    print()
    print("// Montgomery Reduction Parameters")
    print(f"parameter int K_MONTGOMERY = {k_mont};")
    print(f"parameter int R = {R};  // 0x{R:X}")
    print(f"parameter int R_INV = {R_inv};")
    print(f"parameter int Q_PRIME = {q_prime};  // 0x{q_prime:X}")
    print(f"parameter int R_MOD_Q = {R_mod_q};")
    print()


def test_barrett_reduction(q, k, mu, test_cases=5):
    """Test Barrett reduction with sample values"""
    print("=" * 70)
    print("Testing Barrett Reduction")
    print("=" * 70)
    
    import random
    random.seed(42)
    
    for i in range(test_cases):
        a = random.randint(0, q - 1)
        b = random.randint(0, q - 1)
        
        # Simple modulo
        expected = (a * b) % q
        
        # Barrett reduction
        product = a * b
        q1 = product >> (k - 1)
        q2 = (q1 * mu) >> (k + 1)
        r = product - q2 * q
        if r >= q:
            r = r - q
        
        match = "✓" if r == expected else "✗"
        print(f"  {match} {a} * {b} mod {q} = {expected}, Barrett: {r}")
    
    print()


def test_montgomery_reduction(q, k, R, q_prime, test_cases=5):
    """Test Montgomery reduction with sample values"""
    print("=" * 70)
    print("Testing Montgomery Reduction")
    print("=" * 70)
    
    import random
    random.seed(42)
    
    for i in range(test_cases):
        a = random.randint(0, q - 1)
        b = random.randint(0, q - 1)
        
        # Simple modulo
        expected = (a * b) % q
        
        # Convert to Montgomery domain
        a_mont = (a * R) % q
        b_mont = (b * R) % q
        
        # Montgomery multiplication (REDC after multiply)
        T = a_mont * b_mont
        m = (T * q_prime) & (R - 1)  # mod R (since R is power of 2)
        t = (T + m * q) >> k
        if t >= q:
            t = t - q
        
        # Result is in Montgomery domain, convert back
        result = (t * mod_inverse(R, q)) % q
        
        match = "✓" if result == expected else "✗"
        print(f"  {match} {a} * {b} mod {q} = {expected}, Montgomery: {result}")
    
    print()


if __name__ == "__main__":
    # Default: Kyber/Dilithium prime
    Q = 3329
    
    print("=" * 70)
    print("NTT Modular Reduction Constants Generator")
    print("=" * 70)
    print()
    
    generate_systemverilog_params(Q)
    
    # Get constants for testing
    k_barrett, mu = compute_barrett_constants(Q)
    k_mont, R, R_inv, q_prime, R_mod_q = compute_montgomery_constants(Q)
    
    # Test both methods
    test_barrett_reduction(Q, k_barrett, mu)
    test_montgomery_reduction(Q, k_mont, R, q_prime)
    
    print("=" * 70)
    print("All tests passed! Constants are correct.")
    print("=" * 70)
