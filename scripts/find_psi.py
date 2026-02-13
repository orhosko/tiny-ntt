#!/usr/bin/env python3
"""
Find primitive root ψ for NTT parameters
For negative-wrapped convolution (NWC), we need:
- ψ^(2N) ≡ 1 (mod Q) - primitive 2N-th root of unity
- ψ^N ≡ -1 (mod Q) - negacyclic property
"""

def find_psi(n, q, max_search=10000):
    """
    Find primitive 2N-th root of unity ψ for given n and q
    
    Args:
        n: NTT size
        q: Modulus (must be prime)
        max_search: Maximum value to search up to
    
    Returns:
        ψ if found, None otherwise
    """
    print(f"Searching for ψ (primitive {2*n}-th root of unity)")
    print(f"Parameters: N={n}, Q={q}")
    print(f"Required properties:")
    print(f"  1. ψ^{2*n} ≡ 1 (mod {q})")
    print(f"  2. ψ^{n} ≡ -1 (mod {q})")
    print()
    
    for psi in range(2, max_search):
        if pow(psi, 2*n, q) == 1 and pow(psi, n, q) == q - 1:
            omega = (psi * psi) % q
            
            print(f"✓ Found ψ = {psi}")
            print(f"  Verification:")
            print(f"    ψ^{2*n} mod {q} = {pow(psi, 2*n, q)}")
            print(f"    ψ^{n} mod {q} = {pow(psi, n, q)} = -1")
            print(f"  Derived:")
            print(f"    ω = ψ² = {omega}")
            print(f"    ω^{n} mod {q} = {pow(omega, n, q)}")
            
            return psi
    
    print(f"✗ No ψ found in range [2, {max_search})")
    return None

def verify_psi(psi, n, q):
    """Verify that ψ satisfies required properties"""
    cond1 = pow(psi, 2*n, q) == 1
    cond2 = pow(psi, n, q) == q - 1
    
    print(f"Verifying ψ = {psi} for N={n}, Q={q}")
    print(f"  ψ^{2*n} ≡ 1: {'✓' if cond1 else '✗'}")
    print(f"  ψ^{n} ≡ -1: {'✓' if cond2 else '✗'}")
    
    return cond1 and cond2

if __name__ == "__main__":
    import sys
    
    # Common parameter sets
    param_sets = [
        (256, 7681, "Kyber-like"),
        (256, 8380417, "Standard NWC"),
        (512, 12289, "Alternative"),
    ]
    
    print("="*60)
    print("NTT Parameter Finder")
    print("="*60)
    print()
    
    if len(sys.argv) == 3:
        # User-provided parameters
        n = int(sys.argv[1])
        q = int(sys.argv[2])
        print(f"User parameters: N={n}, Q={q}")
        print()
        psi = find_psi(n, q)
    else:
        # Test all common sets
        for n, q, desc in param_sets:
            print(f"{desc}: N={n}, Q={q}")
            psi = find_psi(n, q)
            if psi:
                omega = (psi * psi) % q
                print(f"  → Use: N={n}, Q={q}, ψ={psi}, ω={omega}")
            print()
