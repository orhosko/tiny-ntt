#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string_view>

namespace {

constexpr std::size_t N = BENCH_N;
constexpr std::uint64_t Q = BENCH_Q;
constexpr std::uint64_t PSI = BENCH_PSI;
constexpr int DefaultReps = BENCH_REPS;

static_assert(N > 0 && (N & (N - 1)) == 0, "BENCH_N must be a power of two");

using Wide = unsigned __int128;
using Poly = std::array<std::uint64_t, N>;

constexpr std::uint64_t mod_mul_constexpr(std::uint64_t a, std::uint64_t b) {
    return static_cast<std::uint64_t>((static_cast<Wide>(a) * b) % Q);
}

constexpr std::uint64_t pow_mod(std::uint64_t base, std::uint64_t exp) {
    std::uint64_t result = 1;
    while (exp != 0) {
        if ((exp & 1U) != 0) {
            result = mod_mul_constexpr(result, base);
        }
        base = mod_mul_constexpr(base, base);
        exp >>= 1U;
    }
    return result;
}

constexpr std::uint64_t mod_inv_constexpr(std::uint64_t value) {
    return pow_mod(value, Q - 2);
}

constexpr std::array<std::uint64_t, N> make_power_table(std::uint64_t root) {
    std::array<std::uint64_t, N> out{};
    std::uint64_t value = 1;
    for (std::size_t i = 0; i < N; ++i) {
        out[i] = value;
        value = mod_mul_constexpr(value, root);
    }
    return out;
}

constexpr std::uint64_t OMEGA = mod_mul_constexpr(PSI, PSI);
constexpr std::uint64_t PSI_INV = mod_inv_constexpr(PSI);
constexpr std::uint64_t OMEGA_INV = mod_inv_constexpr(OMEGA);
constexpr std::uint64_t N_INV = mod_inv_constexpr(N % Q);

static_assert(pow_mod(PSI, 2 * N) == 1, "BENCH_PSI must be a primitive 2N-th root");
static_assert(pow_mod(PSI, N) == Q - 1, "BENCH_PSI must satisfy psi^N == -1 mod Q");

constexpr auto PsiPowers = make_power_table(PSI);
constexpr auto PsiInvPowers = make_power_table(PSI_INV);
constexpr auto OmegaPowers = make_power_table(OMEGA);
constexpr auto OmegaInvPowers = make_power_table(OMEGA_INV);

std::uint64_t mod_add(std::uint64_t a, std::uint64_t b) {
    const std::uint64_t sum = a + b;
    return sum >= Q ? sum - Q : sum;
}

std::uint64_t mod_sub(std::uint64_t a, std::uint64_t b) {
    return a >= b ? a - b : a + Q - b;
}

std::uint64_t mod_mul(std::uint64_t a, std::uint64_t b) {
    return static_cast<std::uint64_t>((static_cast<Wide>(a) * b) % Q);
}

Poly make_poly(std::uint64_t seed) {
    Poly out{};
    std::uint64_t x = seed;
    for (auto &v : out) {
        x = (6364136223846793005ULL * x + 1442695040888963407ULL);
        v = x % Q;
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
        const auto *table = Inverse ? OmegaInvPowers.data() : OmegaPowers.data();
        for (std::size_t base = 0; base < N; base += len) {
            for (std::size_t j = 0; j < len / 2; ++j) {
                const std::uint64_t w = table[j * step];
                const std::uint64_t u = a[base + j];
                const std::uint64_t v = mod_mul(a[base + j + len / 2], w);
                a[base + j] = mod_add(u, v);
                a[base + j + len / 2] = mod_sub(u, v);
            }
        }
    }
    if constexpr (Inverse) {
        for (auto &v : a) {
            v = mod_mul(v, N_INV);
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

void pointwise_mul(Poly &a, const Poly &b) {
    for (std::size_t i = 0; i < N; ++i) {
        a[i] = mod_mul(a[i], b[i]);
    }
}

void negacyclic_mul_ntt(const Poly &a, const Poly &b, Poly &out) {
    Poly lhs = a;
    Poly rhs = b;
    twist(lhs);
    twist(rhs);
    ntt<false>(lhs);
    ntt<false>(rhs);
    pointwise_mul(lhs, rhs);
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
            const std::uint64_t product = mod_mul(a[i], b[j]);
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
                           [](std::uint64_t acc, std::uint64_t v) {
                               return (static_cast<Wide>(acc) * 1315423911ULL + v) %
                                      0xffffffffffffffc5ULL;
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
