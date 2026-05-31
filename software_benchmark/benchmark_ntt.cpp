#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string_view>

#if BENCH_SIMD_KIND == 1
#include <immintrin.h>
#endif

#if BENCH_SIMD_KIND == 2
#include <immintrin.h>
#endif

namespace {

constexpr std::size_t N = BENCH_N;
constexpr std::uint64_t Q = BENCH_Q;
constexpr std::uint64_t PSI = BENCH_PSI;
constexpr int DefaultReps = BENCH_REPS;

static_assert(N > 0 && (N & (N - 1)) == 0, "BENCH_N must be a power of two");

using Poly = std::array<std::uint32_t, N>;

constexpr std::uint64_t pow_mod(std::uint64_t base, std::uint64_t exp) {
    std::uint64_t result = 1;
    while (exp != 0) {
        if ((exp & 1U) != 0) {
            result = (result * base) % Q;
        }
        base = (base * base) % Q;
        exp >>= 1U;
    }
    return result;
}

constexpr std::uint64_t mod_inv_constexpr(std::uint64_t value) {
    return pow_mod(value, Q - 2);
}

constexpr std::array<std::uint32_t, N> make_power_table(std::uint64_t root) {
    std::array<std::uint32_t, N> out{};
    std::uint64_t value = 1;
    for (std::size_t i = 0; i < N; ++i) {
        out[i] = static_cast<std::uint32_t>(value);
        value = (value * root) % Q;
    }
    return out;
}

constexpr std::uint64_t OMEGA = (PSI * PSI) % Q;
constexpr std::uint64_t PSI_INV = mod_inv_constexpr(PSI);
constexpr std::uint64_t OMEGA_INV = mod_inv_constexpr(OMEGA);
constexpr std::uint64_t N_INV = mod_inv_constexpr(N % Q);

static_assert(pow_mod(PSI, 2 * N) == 1, "BENCH_PSI must be a primitive 2N-th root");
static_assert(pow_mod(PSI, N) == Q - 1, "BENCH_PSI must satisfy psi^N == -1 mod Q");

constexpr auto PsiPowers = make_power_table(PSI);
constexpr auto PsiInvPowers = make_power_table(PSI_INV);
constexpr auto OmegaPowers = make_power_table(OMEGA);
constexpr auto OmegaInvPowers = make_power_table(OMEGA_INV);

std::uint32_t mod_add(std::uint32_t a, std::uint32_t b) {
    const std::uint32_t sum = a + b;
    return sum >= Q ? sum - Q : sum;
}

std::uint32_t mod_sub(std::uint32_t a, std::uint32_t b) {
    return a >= b ? a - b : static_cast<std::uint32_t>(a + Q - b);
}

std::uint32_t mod_mul(std::uint32_t a, std::uint32_t b) {
    return static_cast<std::uint32_t>((static_cast<std::uint64_t>(a) * b) % Q);
}

Poly make_poly(std::uint32_t seed) {
    Poly out{};
    std::uint64_t x = seed;
    for (auto &v : out) {
        x = (6364136223846793005ULL * x + 1442695040888963407ULL);
        v = static_cast<std::uint32_t>((x >> 17) % Q);
    }
    return out;
}

std::size_t bit_reverse(std::size_t value) {
    std::size_t reversed = 0;
    for (std::size_t bits = N; bits > 1; bits >>= 1U) {
        reversed = (reversed << 1U) | (value & 1U);
        value >>= 1U;
    }
    return reversed;
}

void bit_reverse_permute(Poly &a) {
    for (std::size_t i = 0; i < N; ++i) {
        const std::size_t j = bit_reverse(i);
        if (i < j) {
            std::swap(a[i], a[j]);
        }
    }
}

template <bool Inverse>
void ntt(Poly &a) {
    bit_reverse_permute(a);
    for (std::size_t len = 2; len <= N; len <<= 1U) {
        const std::size_t step = N / len;
        for (std::size_t base = 0; base < N; base += len) {
            for (std::size_t j = 0; j < len / 2; ++j) {
                const auto *table = Inverse ? OmegaInvPowers.data() : OmegaPowers.data();
                const std::uint32_t w = table[j * step];
                const std::uint32_t u = a[base + j];
                const std::uint32_t v = mod_mul(a[base + j + len / 2], w);
                a[base + j] = mod_add(u, v);
                a[base + j + len / 2] = mod_sub(u, v);
            }
        }
    }
    if constexpr (Inverse) {
        for (auto &v : a) {
            v = mod_mul(v, static_cast<std::uint32_t>(N_INV));
        }
    }
}

void twist(Poly &a) {
    for (std::size_t i = 0; i < N; ++i) {
        a[i] = mod_mul(a[i], PsiPowers[i]);
    }
}

void inverse_twist(Poly &a) {
    for (std::size_t i = 0; i < N; ++i) {
        a[i] = mod_mul(a[i], PsiInvPowers[i]);
    }
}

[[maybe_unused]] void pointwise_mul_scalar(Poly &a, const Poly &b) {
    for (std::size_t i = 0; i < N; ++i) {
        a[i] = mod_mul(a[i], b[i]);
    }
}

#if BENCH_SIMD_KIND == 1
void pointwise_mul_bench(Poly &a, const Poly &b) {
    alignas(32) std::uint64_t products[4]{};
    std::size_t i = 0;
    for (; i + 4 <= N; i += 4) {
        const __m256i av = _mm256_set_epi64x(a[i + 3], a[i + 2], a[i + 1], a[i]);
        const __m256i bv = _mm256_set_epi64x(b[i + 3], b[i + 2], b[i + 1], b[i]);
        const __m256i pv = _mm256_mul_epu32(av, bv);
        _mm256_store_si256(reinterpret_cast<__m256i *>(products), pv);
        a[i + 0] = static_cast<std::uint32_t>(products[0] % Q);
        a[i + 1] = static_cast<std::uint32_t>(products[1] % Q);
        a[i + 2] = static_cast<std::uint32_t>(products[2] % Q);
        a[i + 3] = static_cast<std::uint32_t>(products[3] % Q);
    }
    for (; i < N; ++i) {
        a[i] = mod_mul(a[i], b[i]);
    }
}
#elif BENCH_SIMD_KIND == 2
void pointwise_mul_bench(Poly &a, const Poly &b) {
    alignas(64) std::uint64_t products[8]{};
    std::size_t i = 0;
    for (; i + 8 <= N; i += 8) {
        const __m512i av = _mm512_set_epi64(a[i + 7], a[i + 6], a[i + 5], a[i + 4],
                                            a[i + 3], a[i + 2], a[i + 1], a[i]);
        const __m512i bv = _mm512_set_epi64(b[i + 7], b[i + 6], b[i + 5], b[i + 4],
                                            b[i + 3], b[i + 2], b[i + 1], b[i]);
        const __m512i pv = _mm512_mul_epu32(av, bv);
        _mm512_store_si512(reinterpret_cast<__m512i *>(products), pv);
        for (std::size_t lane = 0; lane < 8; ++lane) {
            a[i + lane] = static_cast<std::uint32_t>(products[lane] % Q);
        }
    }
    for (; i < N; ++i) {
        a[i] = mod_mul(a[i], b[i]);
    }
}
#else
void pointwise_mul_bench(Poly &a, const Poly &b) {
    pointwise_mul_scalar(a, b);
}
#endif

void negacyclic_mul_ntt(const Poly &a, const Poly &b, Poly &out) {
    Poly lhs = a;
    Poly rhs = b;
    twist(lhs);
    twist(rhs);
    ntt<false>(lhs);
    ntt<false>(rhs);
    pointwise_mul_bench(lhs, rhs);
    ntt<true>(lhs);
    inverse_twist(lhs);
    out = lhs;
}

void forward_ntt_bench(const Poly &a, Poly &out) {
    out = a;
    twist(out);
    ntt<false>(out);
}

void negacyclic_mul_reference(const Poly &a, const Poly &b, Poly &out) {
    out.fill(0);
    for (std::size_t i = 0; i < N; ++i) {
        for (std::size_t j = 0; j < N; ++j) {
            const std::uint32_t product = mod_mul(a[i], b[j]);
            const std::size_t degree = i + j;
            if (degree < N) {
                out[degree] = mod_add(out[degree], product);
            } else {
                out[degree - N] = mod_sub(out[degree - N], product);
            }
        }
    }
}

std::uint64_t checksum(const Poly &poly) {
    return std::accumulate(poly.begin(), poly.end(), 0ULL,
                           [](std::uint64_t acc, std::uint32_t v) {
                               return (acc * 1315423911ULL + v) % 0xffffffffffffffc5ULL;
                           });
}

int parse_reps(int argc, char **argv, bool &check) {
    int reps = DefaultReps;
    for (int i = 1; i < argc; ++i) {
        const std::string_view arg(argv[i]);
        if (arg == "--check") {
            check = true;
        } else if (arg == "--reps" && i + 1 < argc) {
            reps = std::max(1, std::atoi(argv[++i]));
        } else {
            throw std::runtime_error("usage: benchmark [--check] [--reps count]");
        }
    }
    return reps;
}

} // namespace

int main(int argc, char **argv) {
    try {
        bool check = false;
        const int reps = parse_reps(argc, argv, check);
        const auto a = make_poly(1);
        const auto b = make_poly(2);
        Poly out{};

        if (check) {
            Poly reference{};
            negacyclic_mul_reference(a, b, reference);
            negacyclic_mul_ntt(a, b, out);
            if (out != reference) {
                std::cerr << "correctness check failed\n";
                return 1;
            }
        }

        const auto fwd_start = std::chrono::steady_clock::now();
        for (int r = 0; r < reps; ++r) {
            forward_ntt_bench(a, out);
        }
        const auto fwd_stop = std::chrono::steady_clock::now();
        const auto fwd_ns =
            std::chrono::duration_cast<std::chrono::nanoseconds>(fwd_stop - fwd_start).count();
        const auto fwd_checksum = checksum(out);

        const auto start = std::chrono::steady_clock::now();
        for (int r = 0; r < reps; ++r) {
            negacyclic_mul_ntt(a, b, out);
        }
        const auto stop = std::chrono::steady_clock::now();
        const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(stop - start).count();

        std::cout << BENCH_TARGET_NAME << "\n"
                  << "N=" << N << " Q=" << Q << " reps=" << reps << "\n"
                  << "forward_ntt_total_ns=" << fwd_ns << "\n"
                  << "forward_ntt_avg_ns=" << (fwd_ns / reps) << "\n"
                  << "forward_ntt_checksum=" << fwd_checksum << "\n"
                  << "total_ns=" << ns << "\n"
                  << "avg_ns=" << (ns / reps) << "\n"
                  << "checksum=" << checksum(out) << "\n";
        return 0;
    } catch (const std::exception &ex) {
        std::cerr << ex.what() << "\n";
        return 2;
    }
}
