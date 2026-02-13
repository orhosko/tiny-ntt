#!/usr/bin/env python3
"""Verify inverse NWC NTT reference implementation."""

import os
import sys
import random

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from refs.ntt_inverse_reference import mod_inv, ntt_inverse_reference
from refs.ntt_forward_reference import N, Q, PSI, ntt_forward_reference


def verify_round_trip(n_value=N, q_value=Q, psi_value=PSI):
    print("Verifying round-trip: INTT(NTT(x)) = x")
    print("=" * 60)

    fixed_tests = [
        ("Impulse", [1] + [0] * (n_value - 1)),
        ("All ones", [1] * n_value),
        ("Simple poly", [1, 2, 3] + [0] * (n_value - 3)),
    ]

    for name, poly in fixed_tests:
        ntt_result = ntt_forward_reference(poly, n_value, q_value, psi_value)
        intt_result = ntt_inverse_reference(ntt_result, n_value, q_value, psi_value)
        matches = all(intt_result[i] == poly[i] for i in range(n_value))
        if matches:
            print(f"{name}: ✓ PASS")
        else:
            print(f"{name}: ✗ FAIL")
            for i in range(n_value):
                if intt_result[i] != poly[i]:
                    print(f"  First mismatch at index {i}:")
                    print(f"    Original: {poly[i]}")
                    print(f"    After round-trip: {intt_result[i]}")
                    break
            return False

    for test_num in range(5):
        poly = [random.randint(0, q_value - 1) for _ in range(n_value)]
        ntt_result = ntt_forward_reference(poly, n_value, q_value, psi_value)
        intt_result = ntt_inverse_reference(ntt_result, n_value, q_value, psi_value)
        matches = all(intt_result[i] == poly[i] for i in range(n_value))
        if matches:
            print(f"Random test {test_num + 1}: ✓ PASS")
        else:
            print(f"Random test {test_num + 1}: ✗ FAIL")
            for i in range(n_value):
                if intt_result[i] != poly[i]:
                    print(f"  First mismatch at index {i}:")
                    print(f"    Original: {poly[i]}")
                    print(f"    After round-trip: {intt_result[i]}")
                    break
            return False

    print("=" * 60)
    print("All round-trip tests passed! ✓")
    return True


if __name__ == "__main__":

    psi_inv = mod_inv(PSI, Q)
    n_inv = mod_inv(N, Q)

    print("Inverse NWC NTT Reference Implementation")
    print("=" * 60)
    print("Parameters:")
    print(f"  N = {N}")
    print(f"  q = {Q}")
    print(f"  ψ = {PSI}")
    print(f"  ψ^(-1) = {psi_inv}")
    print(f"  N^(-1) = {n_inv}")
    print()

    print("Verification:")
    print(f"  {PSI} × {psi_inv} mod {Q} = {(PSI * psi_inv) % Q}")
    print(f"  {N} × {n_inv} mod {Q} = {(N * n_inv) % Q}")
    print()

    print("Test 1: Impulse")
    impulse = [1] + [0] * (N - 1)
    ntt_impulse = [1] * N
    intt_result = ntt_inverse_reference(ntt_impulse, N, Q, PSI)

    if intt_result == impulse:
        print("  ✓ INTT([1,1,1,...]) = [1,0,0,...]")
    else:
        print("  ✗ FAILED")
        print(f"    Expected: {impulse[:5]}...")
        print(f"    Got: {intt_result[:5]}...")
    print()

    verify_round_trip()
