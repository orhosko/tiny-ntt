from __future__ import annotations

from typing import List

N = 256
Q = 8380417


def modinv(value: int, modulus: int = Q) -> int:
    return pow(value, modulus - 2, modulus)


def bit_reverse(value: int, bits: int) -> int:
    reversed_value = 0
    for _ in range(bits):
        reversed_value = (reversed_value << 1) | (value & 1)
        value >>= 1
    return reversed_value


def bit_reverse_list(values: List[int]) -> List[int]:
    bits = (len(values) - 1).bit_length()
    reordered = [0] * len(values)
    for idx, val in enumerate(values):
        reordered[bit_reverse(idx, bits)] = val
    return reordered


def cg_ntt(
    a_prime: List[int],
    omega_n: int,
    modulus: int = Q,
    verbose: bool = False,
    log_fn=print,
) -> List[int]:
    if len(a_prime) != N:
        raise ValueError(f"Expected {N} coefficients, got {len(a_prime)}")

    a = bit_reverse_list(a_prime)
    log_n = (N - 1).bit_length()
    A = a

    if verbose:
        log_fn("CG NTT start")
        log_fn(f"  omega_n={omega_n} modulus={modulus}")
        log_fn(f"  input(first 16)={a_prime[:16]}")
        log_fn(f"  bitrev(first 16)={a[:16]}")

    for stage in range(1, log_n + 1):
        k = N >> stage
        omega_s = pow(omega_n, k, modulus)
        A = [0] * N
        for i in range(N // 2):
            omega = pow(omega_s, i // k, modulus)
            left = a[2 * i]
            right = a[2 * i + 1]
            t = (omega * right) % modulus
            A[i] = (left + t) % modulus
            A[i + N // 2] = (left - t) % modulus
        if verbose:
            log_fn(f"  stage={stage} k={k} omega_s={omega_s}")
            log_fn(f"  stage_out(first 16)={A[:16]}")
        if stage != log_n:
            a = A
    return A


def cg_intt(A: List[int], omega_n: int, modulus: int = Q) -> List[int]:
    if len(A) != N:
        raise ValueError(f"Expected {N} coefficients, got {len(A)}")

    omega_inv = modinv(omega_n, modulus)
    a = cg_ntt(A, omega_inv, modulus)
    n_inv = modinv(N, modulus)
    return [(value * n_inv) % modulus for value in a]


def nwc_poly_mult(a: List[int], b: List[int], psi_2n: int) -> List[int]:
    if len(a) != N or len(b) != N:
        raise ValueError(f"Expected {N} coefficients")

    a_twisted = [(a[i] * pow(psi_2n, i, Q)) % Q for i in range(N)]
    b_twisted = [(b[i] * pow(psi_2n, i, Q)) % Q for i in range(N)]

    omega_n = pow(psi_2n, 2, Q)
    A = cg_ntt(a_twisted, omega_n, Q)
    B = cg_ntt(b_twisted, omega_n, Q)
    C = [(A[i] * B[i]) % Q for i in range(N)]

    c_prime = cg_intt(C, omega_n, Q)
    psi_inv = modinv(psi_2n, Q)
    return [(c_prime[i] * pow(psi_inv, i, Q)) % Q for i in range(N)]
