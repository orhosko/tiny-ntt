#!/usr/bin/env python3
"""Quick test of new parameters"""

N = 256
Q = 8380417
PSI = 1239911

print(f"Parameters: N={N}, Q={Q}, ψ={PSI}")
print(f"Verifying ψ properties:")
print(f"  ψ^{2*N} mod Q = {pow(PSI, 2*N, Q)} (should be 1)")
print(f"  ψ^{N} mod Q = {pow(PSI, N, Q)} (should be {Q-1})")
print(f"  ω = ψ² = {(PSI*PSI) % Q}")
