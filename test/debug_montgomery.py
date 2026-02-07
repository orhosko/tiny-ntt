#!/usr/bin/env python3
"""
Quick test to verify Montgomery reduction behavior
"""

Q = 3329
K = 13
R = 2**K  # 8192
Q_PRIME = 7039

def simple_mod(a, b, q):
    """Normal modular multiplication"""
    return (a * b) % q

def montgomery_redc(product, q=Q, k=K, q_prime=Q_PRIME):
    """
    Montgomery REDC algorithm
    Given T (product), compute T / R mod q
    """
    R = 2**k
    R_MASK = R - 1
    
    # Step 1: m = (T * q') mod R
    m_temp = product * q_prime
    m = m_temp & R_MASK  # mod R (lower k bits)
    
    #Step 2: t = (T + m * q) >> k
    t_temp = product + (m * q)
    t = t_temp >> k  # Divide by R
    
    # Step 3: Correction
    if t >= q:
        t = t - q
    
    return t

# Test case 1: multiply 1 * 1
a, b = 1, 1
product = a * b

print(f"Test: {a} * {b} mod {Q}")
print(f"Product (normal domain): {product}")
print(f"Expected (simple): {simple_mod(a, b, Q)}")
print(f"Montgomery REDC result: {montgomery_redc(product)}")
print()

# Test case 2: multiply 2 *  3
a, b = 2, 3
product = a * b

print(f"Test: {a} * {b} mod {Q}")
print(f"Product: {product}")
print(f"Expected (simple): {simple_mod(a, b, Q)}")
print(f"Montgomery REDC result: {montgomery_redc(product)}")
print()

# For Montgomery to give correct results with normal inputs,
# we'd need: result = (product * R^-1) mod q
# Let's check if that's what's happening
R_INV = 3186  # R^-1 mod q (from precompute script)

print("If Montgomery is accidentally doing (product * R^-1) mod q:")
print(f"  Result would be: {(product * R_INV) % Q}")
