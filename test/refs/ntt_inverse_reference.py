"""
Python reference implementation of Constant-Geometry INTT.
N=256, q=8380417, psi=1239911 (primitive 2N-th root)
"""

from .ntt_forward_reference import N, Q, PSI, bit_reverse_list


def ntt_inverse_reference(coeffs, N=N, q=Q, psi=PSI):
    """
    Constant-Geometry inverse NTT (bit-reverse input, CT butterflies)
    with omega^{-1} and final scaling by N^{-1}.

    Input: Normal Order (NTT result)
    Output: Normal Order
    """
    n = len(coeffs)
    if n != N:
        raise ValueError(f"Input must have {N} coefficients, got {n}")

    omega_n = pow(psi, 2, q)
    omega_inv = pow(omega_n, q - 2, q)
    a = bit_reverse_list([value % q for value in coeffs])
    log_n = (N - 1).bit_length()
    A = a

    for stage in range(1, log_n + 1):
        k = N >> stage
        omega_s = pow(omega_inv, k, q)
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

    n_inv = pow(N, q - 2, q)
    return [(value * n_inv) % q for value in A]
