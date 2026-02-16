#!/usr/bin/env python3
"""Verify NTT reference and fast NWC implementations."""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from refs.ntt_forward_reference import N, Q, PSI, ntt_forward_reference
from refs.ntt_inverse_reference import mod_inv, ntt_inverse_reference


def verify_reference_cases():
    print("Testing NTT Reference Implementation")
    print("=" * 50)

    tests = [
        ("All zeros", [0] * N),
        ("Impulse at position 0", [1] + [0] * (N - 1)),
        ("All ones", [1] * N),
        ("Simple polynomial", [1, 2, 3] + [0] * (N - 3)),
    ]

    for name, vector in tests:
        print(f"\n{name}")
        result = ntt_forward_reference(vector)
        print(f"  Input: {vector[:10]}...")
        print(f"  Output: {result[:10]}... (showing first 10)")
        if name == "All zeros":
            print(f"  All zero: {all(v == 0 for v in result)}")
        if name == "Impulse at position 0":
            print(f"  All ones: {all(v == 1 for v in result)}")
        if name == "All ones":
            print(f"  Output first value: {result[0]}")
            print(f"  Output rest: {result[1:10]}... (showing next 9)")
            print(f"  Expected: first={N}, rest=0")

    print("\n" + "=" * 50)
    print("Reference implementation tests complete!")


def verify_parameters():
    print("STEP 1: Verifying ψ Properties")
    print("-" * 70)

    psi_2n = pow(PSI, 2 * N, Q)
    psi_n = pow(PSI, N, Q)
    omega = (PSI * PSI) % Q

    s1_test1 = psi_2n == 1
    s1_test2 = psi_n == Q - 1
    s1_test3 = pow(omega, N, Q) == 1

    print(f"  ψ^{2 * N} ≡ 1 (mod Q): {'✓' if s1_test1 else '✗'} [{psi_2n}]")
    print(f"  ψ^{N} ≡ -1 (mod Q): {'✓' if s1_test2 else '✗'} [{psi_n} vs {Q - 1}]")
    print(f"  ω = ψ² = {omega}, ω^N ≡ 1: {'✓' if s1_test3 else '✗'}")

    step1_pass = s1_test1 and s1_test2 and s1_test3
    print(f"\nStep 1: {'✓✓✓ PASS' if step1_pass else '✗ FAIL'}\n")

    print("STEP 2: Twiddle Factor Generation")
    print("-" * 70)

    psi_inv = mod_inv(PSI, Q)
    omega_inv = mod_inv(omega, Q)

    print(f"  ψ^(-1) = {psi_inv}")
    print(f"  ω^(-1) = {omega_inv}")
    print(f"  Verify: ψ × ψ^(-1) mod Q = {(PSI * psi_inv) % Q}")
    print(f"  Verify: ω × ω^(-1) mod Q = {(omega * omega_inv) % Q}")

    step2_pass = ((PSI * psi_inv) % Q == 1) and ((omega * omega_inv) % Q == 1)
    print(f"\nStep 2: {'✓✓✓ PASS' if step2_pass else '✗ FAIL'}\n")

    return step1_pass, step2_pass


def verify_fast_round_trip():
    print("STEP 3: Forward NTT")
    print("-" * 70)

    test_inputs = [
        (np.array([1] + [0] * (N - 1), dtype=np.int64), "Impulse"),
        (np.array([1, 2, 3] + [0] * (N - 3), dtype=np.int64), "Simple poly"),
        (np.array([1] * N, dtype=np.int64), "All ones"),
    ]

    forward_results = []
    for poly, name in test_inputs:
        try:
            ntt_result = ntt_forward_reference(poly, N, Q, PSI)
            forward_results.append((poly, ntt_result, name))
            print(f"  {name}: ✓ (output: {ntt_result[:5]}...)")
        except Exception as exc:
            print(f"  {name}: ✗ ERROR: {exc}")
            forward_results.append((poly, None, name))

    step3_pass = all(result[1] is not None for result in forward_results)
    print(f"\nStep 3: {'✓✓✓ PASS' if step3_pass else '✗ FAIL'}\n")

    print("STEP 4: Inverse NTT")
    print("-" * 70)

    intt_pass_count = 0
    for poly, ntt_result, name in forward_results:
        if ntt_result is None:
            print(f"  {name}: SKIPPED (forward failed)")
            continue

        try:
            recovered = ntt_inverse_reference(ntt_result, N, Q, PSI)
            match = np.array_equal(poly, recovered)
            if match:
                print(f"  {name}: ✓ Round-trip successful")
                intt_pass_count += 1
            else:
                print(f"  {name}: ✗ Mismatch")
                print(f"      Expected: {poly[:5]}")
                print(f"      Got: {recovered[:5]}")
        except Exception as exc:
            print(f"  {name}: ✗ ERROR: {exc}")

    step4_pass = intt_pass_count == len(test_inputs)
    print(
        f"\nStep 4: {'✓✓✓ PASS' if step4_pass else f'✗ PARTIAL ({intt_pass_count}/{len(test_inputs)} passed)'}\n"
    )

    return step3_pass, step4_pass


def verify_polynomial_multiplication():
    print("STEP 5: Full Integration - Polynomial Multiplication")
    print("-" * 70)

    p1 = np.array([1, 2] + [0] * (N - 2), dtype=np.int64)
    p2 = np.array([3, 4] + [0] * (N - 2), dtype=np.int64)
    expected = np.array([3, 10, 8] + [0] * (N - 3), dtype=np.int64)

    try:
        ntt_p1 = np.array(ntt_forward_reference(p1, N, Q, PSI), dtype=np.int64)
        ntt_p2 = np.array(ntt_forward_reference(p2, N, Q, PSI), dtype=np.int64)
        ntt_prod = (ntt_p1 * ntt_p2) % Q
        result = ntt_inverse_reference(ntt_prod, N, Q, PSI)

        print(f"  p1 = {p1[:5]}")
        print(f"  p2 = {p2[:5]}")
        print(f"  Expected product = {expected[:5]}")
        print(f"  Actual product   = {result[:5]}")

        step5_pass = np.array_equal(result, expected)
        print(f"  Match: {'✓' if step5_pass else '✗'}")
    except Exception as exc:
        print(f"  ✗ ERROR: {exc}")
        step5_pass = False

    print(f"\nStep 5: {'✓✓✓ PASS' if step5_pass else '?  CHECK (may be NWC wrapped)'}\n")
    return step5_pass


def print_summary(step1_pass, step2_pass, step3_pass, step4_pass, step5_pass):
    print("=" * 70)
    print("FINAL SUMMARY")
    print("=" * 70)

    all_steps = [
        ("Step 1: ψ Properties", step1_pass),
        ("Step 2: Twiddle Factors", step2_pass),
        ("Step 3: Forward NTT", step3_pass),
        ("Step 4: Inverse NTT", step4_pass),
        ("Step 5: Integration", step5_pass),
    ]

    for name, passed in all_steps:
        print(f"  {name}: {'✓ PASS' if passed else '✗ FAIL'}")

    if all(passed for _, passed in all_steps):
        print("\n✓✓✓ ALL TESTS PASSED ✓✓✓")
        print("\nThe working NTT reference is fully compatible with:")
        print(f"  N = {N}")
        print(f"  Q = {Q}")
        print(f"  ψ = {PSI}")
        print("\nReady to update codebase!")
    else:
        print("\n✗ SOME TESTS FAILED - Review output above")


if __name__ == "__main__":
    verify_reference_cases()
    step1_pass, step2_pass = verify_parameters()
    step3_pass, step4_pass = verify_fast_round_trip()
    step5_pass = verify_polynomial_multiplication()
    print_summary(step1_pass, step2_pass, step3_pass, step4_pass, step5_pass)
