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
constexpr int DefaultReps = BENCH_REPS;

static_assert(N > 0 && (N & (N - 1)) == 0, "BENCH_N must be a power of two");

using Poly = std::array<std::uint32_t, N>;

std::uint32_t mod_add(std::uint32_t a, std::uint32_t b) {
    const std::uint32_t sum = a + b;
    return sum >= Q ? sum - Q : sum;
}

std::uint32_t mod_sub(std::uint32_t a, std::uint32_t b) {
    return a >= b ? a - b : static_cast<std::uint32_t>(a + Q - b);
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

void negacyclic_mul_scalar(const Poly &a, const Poly &b, Poly &out) {
    out.fill(0);
    for (std::size_t i = 0; i < N; ++i) {
        for (std::size_t j = 0; j < N; ++j) {
            const std::uint32_t product =
                static_cast<std::uint32_t>((static_cast<std::uint64_t>(a[i]) * b[j]) % Q);
            const std::size_t degree = i + j;
            if (degree < N) {
                out[degree] = mod_add(out[degree], product);
            } else {
                out[degree - N] = mod_sub(out[degree - N], product);
            }
        }
    }
}

[[maybe_unused]] std::uint64_t dot_scalar(const Poly &a, const Poly &b, std::size_t a_start,
                                          std::size_t b_start, std::size_t count) {
    std::uint64_t acc = 0;
    for (std::size_t i = 0; i < count; ++i) {
        acc += static_cast<std::uint64_t>(a[a_start + i]) * b[b_start - i];
    }
    return acc;
}

#if BENCH_SIMD_KIND == 1
[[maybe_unused]] std::uint64_t dot_simd(const Poly &a, const Poly &b, std::size_t a_start,
                                        std::size_t b_start, std::size_t count) {
    std::uint64_t acc = 0;
    alignas(32) std::uint64_t lanes[4]{};
    std::size_t i = 0;
    for (; i + 4 <= count; i += 4) {
        const __m256i av = _mm256_set_epi64x(a[a_start + i + 3], a[a_start + i + 2],
                                             a[a_start + i + 1], a[a_start + i]);
        const __m256i bv = _mm256_set_epi64x(b[b_start - i - 3], b[b_start - i - 2],
                                             b[b_start - i - 1], b[b_start - i]);
        const __m256i pv = _mm256_mul_epu32(av, bv);
        _mm256_store_si256(reinterpret_cast<__m256i *>(lanes), pv);
        acc += lanes[0] + lanes[1] + lanes[2] + lanes[3];
    }
    for (; i < count; ++i) {
        acc += static_cast<std::uint64_t>(a[a_start + i]) * b[b_start - i];
    }
    return acc;
}
#elif BENCH_SIMD_KIND == 2
[[maybe_unused]] std::uint64_t dot_simd(const Poly &a, const Poly &b, std::size_t a_start,
                                        std::size_t b_start, std::size_t count) {
    std::uint64_t acc = 0;
    alignas(64) std::uint64_t lanes[8]{};
    std::size_t i = 0;
    for (; i + 8 <= count; i += 8) {
        const __m512i av = _mm512_set_epi64(a[a_start + i + 7], a[a_start + i + 6],
                                            a[a_start + i + 5], a[a_start + i + 4],
                                            a[a_start + i + 3], a[a_start + i + 2],
                                            a[a_start + i + 1], a[a_start + i]);
        const __m512i bv = _mm512_set_epi64(b[b_start - i - 7], b[b_start - i - 6],
                                            b[b_start - i - 5], b[b_start - i - 4],
                                            b[b_start - i - 3], b[b_start - i - 2],
                                            b[b_start - i - 1], b[b_start - i]);
        const __m512i pv = _mm512_mul_epu32(av, bv);
        _mm512_store_si512(reinterpret_cast<__m512i *>(lanes), pv);
        acc += lanes[0] + lanes[1] + lanes[2] + lanes[3] + lanes[4] + lanes[5] + lanes[6] + lanes[7];
    }
    for (; i < count; ++i) {
        acc += static_cast<std::uint64_t>(a[a_start + i]) * b[b_start - i];
    }
    return acc;
}
#else
[[maybe_unused]] std::uint64_t dot_simd(const Poly &a, const Poly &b, std::size_t a_start,
                                        std::size_t b_start, std::size_t count) {
    return dot_scalar(a, b, a_start, b_start, count);
}
#endif

void negacyclic_mul_bench(const Poly &a, const Poly &b, Poly &out) {
#if BENCH_SIMD_KIND == 0
    negacyclic_mul_scalar(a, b, out);
#else
    for (std::size_t k = 0; k < N; ++k) {
        const std::uint64_t positive = dot_simd(a, b, 0, k, k + 1);
        const std::uint64_t negative = dot_simd(a, b, k + 1, N - 1, N - k - 1);
        out[k] = static_cast<std::uint32_t>((positive % Q + Q - negative % Q) % Q);
    }
#endif
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
            negacyclic_mul_scalar(a, b, reference);
            negacyclic_mul_bench(a, b, out);
            if (out != reference) {
                std::cerr << "correctness check failed\n";
                return 1;
            }
        }

        const auto start = std::chrono::steady_clock::now();
        for (int r = 0; r < reps; ++r) {
            negacyclic_mul_bench(a, b, out);
        }
        const auto stop = std::chrono::steady_clock::now();
        const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(stop - start).count();

        std::cout << BENCH_TARGET_NAME << "\n"
                  << "N=" << N << " Q=" << Q << " reps=" << reps << "\n"
                  << "total_ns=" << ns << "\n"
                  << "avg_ns=" << (ns / reps) << "\n"
                  << "checksum=" << checksum(out) << "\n";
        return 0;
    } catch (const std::exception &ex) {
        std::cerr << ex.what() << "\n";
        return 2;
    }
}
