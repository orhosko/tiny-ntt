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
constexpr int DefaultReps = BENCH_REPS;

static_assert(N > 0 && (N & (N - 1)) == 0, "BENCH_N must be a power of two");

using Wide = unsigned __int128;
using Poly = std::array<std::uint64_t, N>;

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

void negacyclic_mul_scalar(const Poly &a, const Poly &b, Poly &out) {
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

int parse_reps(int argc, char **argv) {
    int reps = DefaultReps;
    for (int i = 1; i < argc; ++i) {
        const std::string_view arg(argv[i]);
        if (arg == "--reps" && i + 1 < argc) {
            reps = std::max(1, std::atoi(argv[++i]));
        } else {
            throw std::runtime_error("usage: benchmark [--reps count]");
        }
    }
    return reps;
}

} // namespace

int main(int argc, char **argv) {
    try {
        const int reps = parse_reps(argc, argv);
        const auto a = make_poly(1);
        const auto b = make_poly(2);
        Poly out{};

        const auto start = std::chrono::steady_clock::now();
        for (int r = 0; r < reps; ++r) {
            negacyclic_mul_scalar(a, b, out);
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
