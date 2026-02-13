"""
CORRECT NTT/INTT pair using textbook Cooley-Tukey algorithm
Based on proven implementation
"""

def mod_exp(base, exp, mod):
    result = 1
    base = base % mod
    while exp > 0:
        if exp % 2 == 1:
            result = (result * base) % mod
        exp = exp >> 1
        base = (base * base) % mod
    return result

def mod_inv(a, m):
    def egcd(a, b):
        if a == 0:
            return b, 0, 1
        gcd, x1, y1 = egcd(b % a, a)
        x = y1 - (b // a) * x1
        y = x1
        return gcd, x, y
    gcd, x, _ = egcd(a % m, m)
    return (x % m + m) % m

def ntt_correct(a, omega, q):
    """Correct iterative Cooley-Tukey NTT"""
    n = len(a)
    if n == 1:
        return a
    
    result = list(a)
    
    # Bit-reverse permutation
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j >= bit:
            j -= bit
            bit >>= 1
        j += bit
        if i < j:
            result[i], result[j] = result[j], result[i]
    
    # Cooley-Tukey
    length = 2
    while length <= n:
        wlen = mod_exp(omega, n // length, q)
        for i in range(0, n, length):
            w = 1
            for j in range(length // 2):
                u = result[i + j]
                v = (result[i + j + length // 2] * w) % q
                result[i + j] = (u + v) % q
                result[i + j + length // 2] = (u - v + q) % q
                w = (w * wlen) % q
        length *= 2
    
    return result

def intt_correct(a, omega, q):
    """Correct INTT - inverse of the above NTT"""
    n = len(a)
    omega_inv = mod_inv(omega, q)
    
    # NTT with inverse omega
    result = ntt_correct(a, omega_inv, q)
    
    # Scale by n^(-1)
    n_inv = mod_inv(n, q)
    result = [(x * n_inv) % q for x in result]
    
    return result

# Test
if __name__ == "__main__":
    N, Q, OMEGA = 256, 3329, 17
    
    print("Testing CORRECT NTT/INTT")
    print("="*60)
    
    tests = [
        ("Impulse", [1] + [0] * (N - 1)),
        ("Impulse at 1", [0, 1] + [0] * (N - 2)),
        ("Simple poly", [1, 2, 3] + [0] * (N - 3)),
        ("All ones", [1] * N),
    ]
    
    for name, poly in tests:
        ntt_result = ntt_correct(poly, OMEGA, Q)
        intt_result = intt_correct(ntt_result, OMEGA, Q)
        match = intt_result == poly
        print(f"\n{name}:")
        print(f"  Input: {poly[:10]}")
        print(f"  NTT: {ntt_result[:10]}")
        print(f"  Round-trip: {intt_result[:10]}")
        print(f"  {'✓ PASS' if match else '✗ FAIL'}")
    
    # Multiplication
    print(f"\nPolynomial multiplication:")
    p1 = [1, 5, 1] + [0] * (N - 3)
    p2 = [5, 1] + [0] * (N - 2)
    expected = [5, 10, 6, 1] + [0] * (N - 4)
    
    ntt_p1 = ntt_correct(p1, OMEGA, Q)
    ntt_p2 = ntt_correct(p2, OMEGA, Q)
    ntt_prod = [(ntt_p1[i] * ntt_p2[i]) % Q for i in range(N)]
    result = intt_correct(ntt_prod, OMEGA, Q)
    
    print(f"  Expected: {expected[:10]}")
    print(f"  Got: {result[:10]}")
    print(f"  {'✓ PASS' if result[:4] == expected[:4] else '✗ FAIL'}")
