from __future__ import annotations

import random

from cg_ntt import N, Q, cg_intt, cg_ntt, nwc_poly_mult
from cg_ntt_8butterfly import (
    cg_intt_8butterfly,
    cg_ntt_8butterfly,
    nwc_poly_mult_8butterfly,
)

PSI_2N = 1239911
OMEGA_N = pow(PSI_2N, 2, Q)


def negacyclic_convolution(a, b, modulus=Q):
    result = [0] * N
    for i in range(N):
        for j in range(N):
            term = (a[i] * b[j]) % modulus
            k = i + j
            if k >= N:
                k -= N
                term = (-term) % modulus
            result[k] = (result[k] + term) % modulus
    return result


def log_vector(label, values, limit=16):
    print(f"{label} first {limit}: {values[:limit]}")


def assert_equal_with_logs(expected, actual, label, max_mismatches=8):
    if expected == actual:
        return
    print(f"{label} mismatch: {len(expected)} values")
    log_vector(f"{label} expected", expected)
    log_vector(f"{label} actual", actual)
    mismatches = 0
    for idx, (exp, act) in enumerate(zip(expected, actual)):
        if exp != act:
            print(f"  idx {idx}: expected {exp}, got {act}")
            mismatches += 1
            if mismatches >= max_mismatches:
                break
    assert expected == actual


def test_cg_ntt_8butterfly_identity():
    random.seed(2)
    a = [random.randrange(Q) for _ in range(N)]
    transformed = cg_ntt_8butterfly(a, OMEGA_N, Q, verbose=True)
    recovered = cg_intt_8butterfly(transformed, OMEGA_N, Q)
    log_vector("identity input", a)
    log_vector("identity transformed", transformed)
    log_vector("identity recovered", recovered)
    assert_equal_with_logs([x % Q for x in a], recovered, "cg_ntt_8butterfly_identity")


def test_cg_ntt_8butterfly_matches_scalar():
    random.seed(3)
    a = [random.randrange(Q) for _ in range(N)]
    scalar = cg_ntt(a, OMEGA_N, Q)
    vector = cg_ntt_8butterfly(a, OMEGA_N, Q)
    log_vector("match input", a)
    log_vector("match scalar", scalar)
    log_vector("match vector", vector)
    assert_equal_with_logs(scalar, vector, "cg_ntt_8butterfly_matches_scalar")


def test_nwc_poly_mult_8butterfly_basic():
    a = [0] * N
    b = [0] * N
    a[0] = 1
    a[1] = 2
    a[2] = 3
    b[0] = 4
    b[1] = 5
    b[2] = 6

    expected = negacyclic_convolution(a, b, Q)
    actual = nwc_poly_mult_8butterfly(a, b, PSI_2N)
    log_vector("basic a", a)
    log_vector("basic b", b)
    log_vector("basic expected", expected)
    log_vector("basic actual", actual)
    assert_equal_with_logs(expected, actual, "nwc_poly_mult_8butterfly_basic")


def test_nwc_poly_mult_8butterfly_small_example():
    a = [0] * N
    b = [0] * N
    a[0] = 1
    a[1] = 2
    a[2] = 3
    b[0] = 5
    b[1] = 1

    expected = negacyclic_convolution(a, b, Q)
    actual = nwc_poly_mult_8butterfly(a, b, PSI_2N)
    log_vector("small a", a)
    log_vector("small b", b)
    log_vector("small expected", expected)
    log_vector("small actual", actual)
    assert_equal_with_logs(expected, actual, "nwc_poly_mult_8butterfly_small_example")


def test_nwc_poly_mult_8butterfly_matches_scalar():
    random.seed(4)
    a = [random.randrange(Q) for _ in range(N)]
    b = [random.randrange(Q) for _ in range(N)]
    scalar = nwc_poly_mult(a, b, PSI_2N)
    vector = nwc_poly_mult_8butterfly(a, b, PSI_2N)
    log_vector("random a", a)
    log_vector("random b", b)
    log_vector("random scalar", scalar)
    log_vector("random vector", vector)
    assert_equal_with_logs(scalar, vector, "nwc_poly_mult_8butterfly_matches_scalar")


if __name__ == "__main__":
    test_cg_ntt_8butterfly_identity()
    test_cg_ntt_8butterfly_matches_scalar()
    test_nwc_poly_mult_8butterfly_basic()
    test_nwc_poly_mult_8butterfly_matches_scalar()
    print("All CG NTT 8-butterfly tests passed.")
