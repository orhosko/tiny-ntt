import numpy as np

def mod_inverse(a, m):
    """Compute modular inverse of a modulo m using Extended Euclidean Algorithm"""
    def extended_gcd(a, b):
        if a == 0: return b, 0, 1
        gcd, x1, y1 = extended_gcd(b % a, a)
        x = y1 - (b // a) * x1
        y = x1
        return gcd, x, y
    gcd, x, _ = extended_gcd(a % m, m)
    if gcd != 1: raise ValueError(f"Modular inverse does not exist for {a} mod {m}")
    return (x % m + m) % m

def bit_reverse_order(n):
    """
    Generate bit-reversed indices for size n.
    [cite_start]Definition 4.1 [cite: 556-559]: The bit-reversal of b is defined by reversing binary bits.
    [cite_start]Example 4.8 [cite: 560-564]: For n=4, indices [0,1,2,3] -> [0,2,1,3].
    """
    width = n.bit_length() - 1
    indices = np.arange(n)
    reversed_indices = np.zeros(n, dtype=int)
    for i in range(n):
        binary = bin(i)[2:].zfill(width)
        reversed_indices[i] = int(binary[::-1], 2)
    return reversed_indices

def fast_ntt_psi(a, psi, q):
    """
    Fast Number Theoretic Transform (Cooley-Tukey Algorithm)
    
    [cite_start]Implementation of Section 4.1[cite: 330].
    - [cite_start]Input: Normal Order (NO) [cite: 553]
    - [cite_start]Output: Bit-Reversed Order (BO) [cite: 553]
    - [cite_start]Complexity: O(n log n) [cite: 322]
    
    Mathematical Basis:
    [cite_start]Equation (24)[cite: 341]: â_j = A_j + ψ^(2j+1)B_j
    
    [cite_start]Structure from Figure 5 [cite: 372-387] [cite_start]and Example 4.1[cite: 351]:
    - Uses 'decimation-in-frequency' style topology (stride n/2 -> 1)
    - But uses Cooley-Tukey butterfly arithmetic (A + WB)
    """
    n = len(a)
    result = np.array(a, dtype=object) # Copy input
    
    # Pre-compute bit-reversed indices for twiddle factor selection
    # The twiddle sequence follows the bit-reversed order of 1..n-1
    brv = bit_reverse_order(n)
    
    t = 1 # Number of blocks
    m = n // 2 # Stride / Block half-size
    
    while m >= 1:
        # Loop through each block
        for k in range(t):
            # Calculate Twiddle Factor W = ψ^p
            # The exponent p comes from the bit-reversed index table
            # Logic derived from Example 4.1 patterns:
            # Stage 1 (t=1): Uses brv[1]=2 -> ψ^2
            # Stage 2 (t=2): Uses brv[2]=1 -> ψ^1, brv[3]=3 -> ψ^3
            p = brv[t + k]
            W = pow(int(psi), int(p), q)
            
            # Apply Butterfly to the block
            for j in range(m):
                idx1 = 2 * m * k + j
                idx2 = idx1 + m
                
                u = result[idx1]
                v = (result[idx2] * W) % q # Multiply by twiddle
                
                # CT Butterfly Operations: A+WB, A-WB
                result[idx1] = (u + v) % q
                result[idx2] = (u - v) % q
        
        t *= 2
        m //= 2
        
    return result.astype(np.int64)

def fast_intt_psi(a_hat, psi, q):
    """
    Fast Inverse Number Theoretic Transform (Gentleman-Sande Algorithm)
    
    [cite_start]Implementation of Section 4.3[cite: 407].
    - [cite_start]Input: Bit-Reversed Order (BO) [cite: 554]
    - [cite_start]Output: Normal Order (NO) [cite: 554]
    
    Mathematical Basis:
    [cite_start]Equation (32)[cite: 492]: a_2i = (A_i + B_i)ψ^-2i
    
    [cite_start]Structure from Figure 9 [cite: 537] [cite_start]and Example 4.3[cite: 437]:
    - Uses 'decimation-in-time' style topology (stride 1 -> n/2)
    - Uses Gentleman-Sande butterfly arithmetic (A+B, (A-B)W)
    """
    n = len(a_hat)
    result = np.array(a_hat, dtype=object)
    
    psi_inv = mod_inverse(psi, q)
    brv = bit_reverse_order(n)
    
    t = n // 2 # Number of blocks (starts high, decreases)
    m = 1      # Stride (starts low, increases)
    
    while m < n:
        # Loop through each block
        for k in range(t):
            # Calculate Twiddle Factor W = ψ^-p
            # Logic derived from Example 4.3:
            # Stage 1 (m=1, t=2): Uses brv[2]=1 -> ψ^-1, brv[3]=3 -> ψ^-3
            # Stage 2 (m=2, t=1): Uses brv[1]=2 -> ψ^-2
            p = brv[t + k]
            W = pow(int(psi_inv), int(p), q)
            
            for j in range(m):
                idx1 = 2 * m * k + j
                idx2 = idx1 + m
                
                u = result[idx1]
                v = result[idx2]
                
                # GS Butterfly Operations: A+B, (A-B)W
                result[idx1] = (u + v) % q
                diff = (u - v) % q
                result[idx2] = (diff * W) % q
                
        t //= 2
        m *= 2
        
    # [cite_start]Final scaling by n^-1 [cite: 485]
    n_inv = mod_inverse(n, q)
    result = (result * n_inv) % q
    
    return result.astype(np.int64)

def fast_ntt_convolution(a, b, psi, q):
    """
    Compute negacyclic convolution using Fast-NTT.
    [cite_start]c = INTT_ψ(NTT_ψ(a) ∘ NTT_ψ(b)) [cite: 288]
    """
    # 1. Forward Transform (O(n log n))
    a_hat = fast_ntt_psi(a, psi, q)
    b_hat = fast_ntt_psi(b, psi, q)
    
    # [cite_start]2. Element-wise Multiplication (O(n)) [cite: 548]
    # Note: Inputs are in Bit-Reversed Order, so we just multiply matching indices
    c_hat = (a_hat * b_hat) % q
    
    # 3. Inverse Transform (O(n log n))
    c = fast_intt_psi(c_hat, psi, q)
    
    return c

if __name__ == "__main__":
    # --- Verification: Example 4.1 (Fast NTT) ---
    print("="*60)
    print("Verifying Example 4.1: Fast NTT (n=4, q=7681)")
    print("="*60)
    n = 4
    q = 7681
    psi = 1925
    g = np.array([1, 2, 3, 4], dtype=np.int64)
    
    print(f"Input g: {g}")
    g_hat = fast_ntt_psi(g, psi, q)
    print(f"Fast-NTT Result (Bit-Reversed): {g_hat}")
    
    # [cite_start]Expected from Example 4.1 text[cite: 390]: 
    # Stage 2 result is [1467, 3471, 2807, 7621] BEFORE reordering to NO.
    # Since our function outputs BO, it should match this exactly?
    # Actually, the paper says "By reordering... we get [1467, 2807, 3471, 7621]".
    # The normal order is [1467, 2807, 3471, 7621].
    # Bit-reversed order of result should be indices [0, 2, 1, 3] of NO.
    # NO[0]=1467, NO[2]=3471, NO[1]=2807, NO[3]=7621.
    # So expected BO output is [1467, 3471, 2807, 7621].
    expected_bo = np.array([1467, 3471, 2807, 7621])
    
    if np.array_equal(g_hat, expected_bo):
        print("✓ Matches Example 4.1 result (in Bit-Reversed Order)")
    else:
        print(f"✗ Mismatch! Expected {expected_bo}")

    # --- Verification: Example 4.3 (Fast INTT) ---
    print("\n" + "="*60)
    print("Verifying Example 4.3: Fast INTT (n=4, q=7681)")
    print("="*60)
    # Input is the Bit-Reversed result from previous step
    # Example 4.3 input is [1467, 2807, 3471, 7621] reordered as BO.
    # BO of NO input: [1467, 3471, 2807, 7621]
    input_hat = g_hat 
    print(f"Input â (Bit-Reversed): {input_hat}")
    
    res = fast_intt_psi(input_hat, psi, q)
    print(f"Fast-INTT Result (Normal Order): {res}")
    
    expected_res = np.array([1, 2, 3, 4])
    if np.array_equal(res, expected_res):
        print("✓ Matches original polynomial g=[1, 2, 3, 4]")
    else:
        print("✗ Mismatch!")

    # --- Verification: Convolution Example 4.7 ---
    print("\n" + "="*60)
    print("Verifying Example 4.7: Fast Convolution")
    print("="*60)
    h = np.array([5, 6, 7, 8], dtype=np.int64)
    conv_result = fast_ntt_convolution(g, h, psi, q)
    print(f"Convolution Result: {conv_result}")
    
    # Check against negative wrapped result: [-56, -36, 2, 60] mod 7681
    # [-56, -36, 2, 60] -> [7625, 7645, 2, 60]
    expected_conv = np.array([7625, 7645, 2, 60])
    
    if np.array_equal(conv_result, expected_conv):
        print("✓ Matches Example 4.7 / 3.12 exactly!")
        print("  Fast-NTT Negacyclic Convolution is working correctly.")
    else:
        print("✗ Mismatch!")