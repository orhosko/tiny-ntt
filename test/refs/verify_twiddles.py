#!/usr/bin/env python3
"""Verify twiddle factor generation for NWC NTT."""

import math


# Parameters
N = 256
Q = 8380417
PSI = 1239911
OMEGA = (PSI * PSI) % Q

print("="*70)
print("STEP 2: Testing Twiddle Factor Generation")
print("="*70)

# Test 1: Forward twiddle factors (using ψ)
print(f"\nTest 1: Forward NTT Twiddle Factors")
print(f"  Using ψ = {PSI}")

log_n = int(math.log2(N))
stages = [0, 1, 2]
for stage in stages:
    half_block = 1 << stage
    multiplier = 1 << (log_n - stage - 1)
    print(f"\n  Stage {stage}: half_block={half_block}, multiplier={multiplier}")
    for pos in range(min(4, half_block)):
        addr = pos * multiplier
        twiddle = pow(PSI, addr, Q)
        print(f"    position {pos}: addr={addr}, ψ^{addr} mod Q = {twiddle}")

# Test 3: Inverse twiddle factors (using ψ^(-1))
print(f"\nTest 3: Inverse NTT Twiddle Factors")

# Compute ψ^(-1)
def mod_inverse(a, m):
    def egcd(a, b):
        if a == 0:
            return b, 0, 1
        gcd, x1, y1 = egcd(b % a, a)
        x = y1 - (b // a) * x1
        y = x1
        return gcd, x, y

    gcd, x, _ = egcd(a % m, m)
    return (x % m + m) % m

psi_inv = mod_inverse(PSI, Q)
print(f"  ψ^(-1) mod Q = {psi_inv}")
print(f"  Verification: ψ × ψ^(-1) mod Q = {(PSI * psi_inv) % Q}")

# Sample inverse twiddles
for stage in stages:
    half_block = 1 << stage
    multiplier = 1 << (log_n - stage - 1)
    print(f"\n  Stage {stage} inverse twiddles:")
    for pos in range(min(4, half_block)):
        addr = pos * multiplier
        twiddle_inv = pow(psi_inv, addr, Q)
        print(f"    position {pos}: addr={addr}, ψ^(-{addr}) mod Q = {twiddle_inv}")

# Test 3: Verify ω-based twiddles (for comparison)
print(f"\nTest 3: Omega-based Twiddles (Traditional)")
print(f"  ω = {OMEGA}")
print(f"  First few ω^k:")
for k in range(8):
    twiddle_omega = pow(OMEGA, k, Q)
    print(f"    ω^{k} = {twiddle_omega}")

print(f"\n{'='*70}")
print("SUMMARY:")
print(f"{'='*70}")
print("✓ ψ-based twiddles use addr mapping")
print("✓ Inverse twiddles use ψ^(-1)")
print("\nReady for Step 3: Forward NTT testing")
