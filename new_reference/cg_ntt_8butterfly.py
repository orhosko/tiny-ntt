from __future__ import annotations

from typing import Iterable, List, Sequence, Tuple

from cg_ntt import N, Q, bit_reverse_list, modinv


def butterfly(a: int, b: int, omega: int, modulus: int = Q) -> Tuple[int, int]:
    t = (omega * b) % modulus
    return (a + t) % modulus, (a - t) % modulus


def butterfly_batch(
    a_vals: Sequence[int],
    b_vals: Sequence[int],
    omega_vals: Sequence[int],
    modulus: int = Q,
) -> Tuple[List[int], List[int]]:
    if not (len(a_vals) == len(b_vals) == len(omega_vals) == 8):
        raise ValueError("Expected 8 butterfly lanes")
    a_out = [0] * 8
    b_out = [0] * 8
    for lane in range(8):
        a_out[lane], b_out[lane] = butterfly(
            a_vals[lane], b_vals[lane], omega_vals[lane], modulus
        )
    return a_out, b_out


def _chunked(iterable: Iterable[int], size: int) -> Iterable[List[int]]:
    chunk: List[int] = []
    for value in iterable:
        chunk.append(value)
        if len(chunk) == size:
            yield chunk
            chunk = []
    if chunk:
        yield chunk


def cg_ntt_8butterfly(
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
        log_fn("CG NTT 8-butterfly start")
        log_fn(f"  omega_n={omega_n} modulus={modulus}")
        log_fn(f"  input(first 16)={a_prime[:16]}")
        log_fn(f"  bitrev(first 16)={a[:16]}")

    for stage in range(1, log_n + 1):
        k = N >> stage
        omega_s = pow(omega_n, k, modulus)
        A = [0] * N
        pairs = N // 2
        for base in range(0, pairs, 8):
            a_vals = []
            b_vals = []
            omega_vals = []
            for offset in range(8):
                i = base + offset
                if i >= pairs:
                    break
                omega = pow(omega_s, i // k, modulus)
                a_vals.append(a[2 * i])
                b_vals.append(a[2 * i + 1])
                omega_vals.append(omega)

            if len(a_vals) < 8:
                for pad in range(len(a_vals), 8):
                    a_vals.append(0)
                    b_vals.append(0)
                    omega_vals.append(1)

            a_out, b_out = butterfly_batch(a_vals, b_vals, omega_vals, modulus)
            for offset in range(min(8, pairs - base)):
                i = base + offset
                A[i] = a_out[offset]
                A[i + pairs] = b_out[offset]

        if verbose:
            log_fn(f"  stage={stage} k={k} omega_s={omega_s}")
            log_fn(f"  stage_out(first 16)={A[:16]}")

        if stage != log_n:
            a = A
    return A


def cg_intt_8butterfly(A: List[int], omega_n: int, modulus: int = Q) -> List[int]:
    omega_inv = modinv(omega_n, modulus)
    a = cg_ntt_8butterfly(A, omega_inv, modulus)
    n_inv = modinv(N, modulus)
    return [(value * n_inv) % modulus for value in a]


def nwc_poly_mult_8butterfly(a: List[int], b: List[int], psi_2n: int) -> List[int]:
    if len(a) != N or len(b) != N:
        raise ValueError(f"Expected {N} coefficients")

    a_twisted = [(a[i] * pow(psi_2n, i, Q)) % Q for i in range(N)]
    b_twisted = [(b[i] * pow(psi_2n, i, Q)) % Q for i in range(N)]

    omega_n = pow(psi_2n, 2, Q)
    A = cg_ntt_8butterfly(a_twisted, omega_n, Q)
    B = cg_ntt_8butterfly(b_twisted, omega_n, Q)
    C = [(A[i] * B[i]) % Q for i in range(N)]

    c_prime = cg_intt_8butterfly(C, omega_n, Q)
    psi_inv = modinv(psi_2n, Q)
    return [(c_prime[i] * pow(psi_inv, i, Q)) % Q for i in range(N)]
