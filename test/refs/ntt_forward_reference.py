"""
Python reference implementation of Constant-Geometry NTT for testing.
"""

import os

# NTT Parameters
N = int(os.getenv("NTT_N", "1024"))
Q = int(os.getenv("NTT_Q", "8380417"))
PSI = int(os.getenv("NTT_PSI", "5548360"))
OMEGA = pow(PSI, 2, Q)


def bit_reverse(value, bits):
    reversed_value = 0
    for _ in range(bits):
        reversed_value = (reversed_value << 1) | (value & 1)
        value >>= 1
    return reversed_value


def bit_reverse_list(values):
    bits = (len(values) - 1).bit_length()
    reordered = [0] * len(values)
    for idx, val in enumerate(values):
        reordered[bit_reverse(idx, bits)] = val
    return reordered


def bit_reverse_order(n):
    bits = (n - 1).bit_length()
    reversed_indices = [0] * n
    for i in range(n):
        reversed_indices[i] = bit_reverse(i, bits)
    return reversed_indices


def ntt_forward_reference(coeffs, N=N, q=Q, psi=PSI):
    """
    Constant-Geometry NTT (bit-reverse input, CT butterflies).

    Input: Normal Order
    Output: Normal Order
    """
    n = len(coeffs)
    if n != N:
        raise ValueError(f"Input must have {N} coefficients, got {n}")

    omega_n = pow(psi, 2, q)
    a = bit_reverse_list([value % q for value in coeffs])
    log_n = (N - 1).bit_length()
    A = a

    for stage in range(1, log_n + 1):
        k = N >> stage
        omega_s = pow(omega_n, k, q)
        A = [0] * N
        for i in range(N // 2):
            omega = pow(omega_s, i // k, q)
            left = a[2 * i]
            right = a[2 * i + 1]
            t = (omega * right) % q
            A[i] = (left + t) % q
            A[i + N // 2] = (left - t) % q
        if stage != log_n:
            a = A

    return A
